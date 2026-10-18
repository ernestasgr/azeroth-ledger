local addonName, addon = ...

-- Composition root. It opens the store when the addon's SavedVariables load,
-- wires the event channels to one frame, and exposes the slash command, key
-- binding, and minimap button. Event rules live in the channel modules: Loot,
-- Reward, Vendor, Exchange and GuildBank.
local Events, Runtime, Trace = addon.Events, addon.Runtime, addon.Trace

local client = addon.Client.inspect(_G)
local revision = Runtime.revision(_G, addonName)
local store
local listeners = { snapshot = {}, flushed = {} }

local function getStore()
    return store
end

local function notify(kind, ...)
    for _, listener in ipairs(listeners[kind]) do
        listener(...)
    end
end

-- Registration failures are reported by /al status rather than raised.
local function register(module, ...)
    if not module then
        return
    end
    local ok, registered, failure = pcall(module.register, ...)
    if not ok or not registered then
        client.issues[#client.issues + 1] = tostring(ok and failure or registered)
    end
end

local function openStore()
    if store then
        return
    end
    store = addon.Schema.open(AzerothLedgerDB, function(nextValue)
        AzerothLedgerDB = nextValue
    end)
    addon.store = store
    register(addon.Presentation, _G, store)
    register(addon.Settings, _G, store)
    if #client.issues == 0 then
        store:setEnvironment({
            build = client.build,
            interface = client.interface,
            locale = client.locale,
            revision = revision,
        })
    end
end

local inventory = addon.Inventory.new(_G, function(snapshot)
    local accepted = store:scan(snapshot)
    if Trace.enabled then
        addon.Diagnostics.traceStored(store, snapshot, accepted)
    end
    notify("snapshot", snapshot)
    addon.Book.refresh(store, snapshot.character, snapshot.realm)
end, function()
    notify("flushed")
end)

local function clock()
    return Runtime.now(_G)
end

local function commands(channel)
    return Runtime.commands(_G, clock, getStore, channel.commands)
end

local function check(area)
    inventory:check(area)
end

local function refresh(character, realm)
    addon.Book.refresh(store, character, realm)
end

-- Hooks install as each channel is created, so creation order is hook order.
local vendor = addon.Vendor.new({
    api = _G,
    clock = clock,
    issues = client.issues,
    commands = commands(addon.Vendor),
    check = check,
    refresh = refresh,
})
local exchange = addon.Exchange.new({
    api = _G,
    issues = client.issues,
    commands = commands(addon.Exchange),
    mailProgress = function(ids)
        return store:mailProgress(ids)
    end,
    check = check,
})
local guildBank = addon.GuildBank.new({
    api = _G,
    issues = client.issues,
    commands = commands(addon.GuildBank),
    check = check,
})
local reward = addon.Reward.new({
    api = _G,
    clock = clock,
    commands = commands(addon.Reward),
    check = check,
    refresh = refresh,
    exchangeOpen = function()
        return exchange.isOpen() or guildBank.isOpen()
    end,
})
local channels = {
    vendor,
    exchange,
    guildBank,
    addon.Loot.new({
        api = _G,
        commands = commands(addon.Loot),
        refresh = refresh,
        merchantOpen = vendor.isOpen,
        received = reward.received,
        clock = clock,
    }),
    reward,
}
for _, channel in ipairs(channels) do
    for kind, list in pairs(listeners) do
        if channel[kind] then
            list[#list + 1] = channel[kind]
        end
    end
end

local commandContext = {
    api = _G,
    store = getStore,
    client = client,
    revision = revision,
    inventory = inventory,
    -- Resolved per call, so chat frame replacements loaded later still apply.
    print = function(...)
        _G.print(...)
    end,
}

local function toggle()
    openStore()
    local character, realm = Runtime.identity(_G)
    if character and realm then
        addon.Book.toggle(_G, store, character, realm)
    end
end

-- Native key binding entry points from Bindings.xml.
_G.BINDING_HEADER_AZEROTHLEDGER = "Azeroth Ledger"
_G.BINDING_NAME_AZEROTHLEDGER_TOGGLE = "Toggle Ledger"
_G.AzerothLedgerToggle = toggle

SLASH_AZEROTHLEDGER1 = "/al"
SlashCmdList.AZEROTHLEDGER = addon.Commands.new(commandContext)

local function forwardInventory(event)
    return function(...)
        inventory:event(event, ...)
    end
end

-- The addon's own routes. They run only after the store is open.
local ledgerRoutes = {
    -- The player's name and realm are settled by PLAYER_LOGIN, before any
    -- loot, quest, vendor, mail or trade event of this login.
    PLAYER_LOGIN = function()
        local character, realm = Runtime.identity(_G)
        if character and realm then
            store:setCharacter(character, realm)
        end
        addon.MinimapButton.create(_G, toggle)
        inventory:check("all")
        addon.Commands.printStatus(commandContext)
    end,
    PLAYER_ENTERING_WORLD = function(isInitialLogin)
        if isInitialLogin then
            inventory:check("possessions")
            inventory:event("PLAYER_ENTERING_WORLD")
        end
    end,
    BAG_UPDATE = forwardInventory("BAG_UPDATE"),
    BAG_UPDATE_DELAYED = forwardInventory("BAG_UPDATE_DELAYED"),
    PLAYER_EQUIPMENT_CHANGED = forwardInventory("PLAYER_EQUIPMENT_CHANGED"),
    UNIT_INVENTORY_CHANGED = forwardInventory("UNIT_INVENTORY_CHANGED"),
    BANKFRAME_OPENED = forwardInventory("BANKFRAME_OPENED"),
    BANKFRAME_CLOSED = forwardInventory("BANKFRAME_CLOSED"),
    -- Item data events carry (itemID, success); the inventory needs only success.
    GET_ITEM_INFO_RECEIVED = function(_, success)
        inventory:event("GET_ITEM_INFO_RECEIVED", success)
    end,
    ITEM_DATA_LOAD_RESULT = function(_, success)
        inventory:event("ITEM_DATA_LOAD_RESULT", success)
    end,
}

local routeTables = { ledgerRoutes }
for _, channel in ipairs(channels) do
    routeTables[#routeTables + 1] = channel.events
end
local routes = Events.merge(unpack(routeTables))

-- Lifecycle events run before the store opens or after the session ends.
local lifecycle = {
    ADDON_LOADED = function(name)
        if name ~= addonName then
            return
        end
        Trace.attach(AzerothLedgerTraceDB, function(value)
            AzerothLedgerTraceDB = value
        end)
        Trace.log("addon-loaded", "revision=" .. revision, "client=" .. client.build, "features=pending-gear,trace")
        openStore()
    end,
    PLAYER_LOGOUT = function()
        addon.Book.save()
    end,
}

local function expireEvidence()
    local at = Runtime.now(_G)
    if store and at then
        store:expireEvidence(at)
    end
end

local function handle(event, ...)
    local early = lifecycle[event]
    if early then
        early(...)
        return
    end
    if not store then
        return
    end
    if Trace.enabled then
        Trace.log("event", event, ...)
    end
    expireEvidence()
    Events.run(routes, event, ...)
end

if client.frame then
    local names = Events.names(routes)
    for event in pairs(lifecycle) do
        names[#names + 1] = event
    end
    Events.attach(client.frame, names, function(_, event, ...)
        local arguments = { n = select("#", ...), ... }
        addon.Work.measure(_G, "Event " .. event, function()
            handle(event, unpack(arguments, 1, arguments.n))
        end)
    end, client.issues)
    Events.every(_G, client.frame, 1, expireEvidence, client.issues)
else
    print("Azeroth Ledger: event frame unavailable; saved data was not opened")
end

addon.name = addonName
AzerothLedger = addon
