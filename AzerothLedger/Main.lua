local addonName, addon = ...

-- Composition root. It opens the store when the addon's SavedVariables load,
-- wires the event sessions to one frame, and exposes the slash command, key
-- binding, and minimap button. Event rules live in the *Session modules.
local Events, Runtime, Trace = addon.Events, addon.Runtime, addon.Trace
local Sessions = addon.Sessions

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
    addon.Collection.refresh(store, snapshot.character, snapshot.realm)
end, function()
    notify("flushed")
end)

local runtime = Runtime.new(_G, client.issues, getStore, inventory)

-- Hooks install as each session is created, so creation order is hook order.
local merchant = Sessions.Merchant.new(runtime)
local sessions = {
    merchant,
    Sessions.Mail.new(runtime),
    Sessions.Trade.new(runtime),
    Sessions.Loot.new(runtime, merchant.isOpen),
    Sessions.Quest.new(runtime),
    Sessions.Craft.new(runtime),
}
for _, session in ipairs(sessions) do
    for kind, list in pairs(listeners) do
        if session[kind] then
            list[#list + 1] = session[kind]
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
for _, session in ipairs(sessions) do
    routeTables[#routeTables + 1] = session.events
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
