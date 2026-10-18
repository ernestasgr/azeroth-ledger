local _, addon = ...

-- Player, clock, and store actions shared by the event sessions. Readers return
-- nil when the client cannot answer, so a session skips its work instead of
-- recording evidence without a character, realm, or time.
local Runtime = {}

---@param api table
---@return integer?
function Runtime.now(api)
    return type(api.GetServerTime) == "function" and api.GetServerTime() or nil
end

---@param api table
---@return string?, string?
function Runtime.identity(api)
    if type(api.UnitName) ~= "function" or type(api.GetRealmName) ~= "function" then
        return nil, nil
    end
    return api.UnitName("player"), api.GetRealmName()
end

-- The merchant, quest giver, or other NPC the player is talking to.
---@param api table
---@return string?
function Runtime.npcName(api)
    if type(api.UnitName) ~= "function" then
        return nil
    end
    local ok, name = pcall(api.UnitName, "npc")
    return ok and type(name) == "string" and name ~= "" and name or nil
end

-- The acting character with the time, level, and place of an action:
-- { character, realm, at, level, place, placeKind? }.
---@param api table
---@return table?
function Runtime.player(api)
    local character, realm = Runtime.identity(api)
    local at = Runtime.now(api)
    if not character or not realm or not at then
        return nil
    end
    local level = type(api.UnitLevel) == "function" and api.UnitLevel("player") or 0
    local place, placeKind = addon.Client.place(api)
    return { character = character, realm = realm, at = at, level = level, place = place, placeKind = placeKind }
end

-- The TOC version, so saved environments and traces never drift from a release.
---@param api table
---@param addonName string
---@return string
function Runtime.revision(api, addonName)
    local addOns = api.C_AddOns
    local read = type(addOns) == "table" and addOns.GetAddOnMetadata or api.GetAddOnMetadata
    if type(read) == "function" then
        local ok, version = pcall(read, addonName, "Version")
        if ok and type(version) == "string" and version ~= "" and #version <= 64 then
            return version
        end
    end
    return "dev"
end

---@class ALRuntime
---@field api table
---@field issues string[]
---@field store fun(): ALStore
---@field inventory table
---@field now fun(): integer?
---@field identity fun(): string?, string?
---@field player fun(): table?
---@field refresh fun(character: string, realm: string)
---@field command fun(name: ALCommandName, payload: any, context?: table): any, table?
---@field exchangeIntent fun(intent: table): any
---@field exchangeConfirm fun(channel: string, direction: string, ids: table<string, true>?)
---@field reward fun(receipt: table?)

-- Binds the readers to one client and the lazily opened store.
---@param api table
---@param issues string[]
---@param store fun(): ALStore
---@param inventory table
---@return ALRuntime
function Runtime.new(api, issues, store, inventory)
    local runtime = { api = api, issues = issues, store = store, inventory = inventory }

    function runtime.now()
        return Runtime.now(api)
    end

    function runtime.identity()
        return Runtime.identity(api)
    end

    function runtime.player()
        return Runtime.player(api)
    end

    function runtime.refresh(character, realm)
        addon.Collection.refresh(store(), character, realm)
    end

    -- Sends one write to the store as the acting character at its time. A
    -- session passes its own context when it adds fields such as a vendor name.
    -- Returns the store's result and the context, or nothing without one.
    function runtime.command(name, payload, context)
        context = context or Runtime.player(api)
        if context then
            return store():command(name, payload, context.at, context), context
        end
    end

    function runtime.exchangeIntent(intent)
        if intent then
            return (runtime.command("exchangeIntent", intent))
        end
    end

    function runtime.exchangeConfirm(channel, direction, ids)
        if runtime.command("exchangeConfirm", { channel = channel, direction = direction, ids = ids }) then
            inventory:check("bags")
        end
    end

    -- Quest rewards can go straight into gear, so the gain is checked against
    -- bags and equipped slots together.
    function runtime.reward(receipt)
        if not receipt then
            return
        end
        local accepted, context = runtime.command("rewardReceipt", receipt)
        if accepted and context then
            if receipt.method == "Quest" then
                inventory:check("possessions")
            end
            runtime.refresh(context.character, context.realm)
        end
    end

    return runtime
end

addon.Runtime = Runtime
