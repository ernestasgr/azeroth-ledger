local _, addon = ...

-- Player, clock, and store commands shared by the event channels. Readers return
-- nil when the client cannot answer, so a channel skips its work instead of
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
---@param clock? fun(): integer?
---@return table?
function Runtime.player(api, clock)
    local character, realm = Runtime.identity(api)
    local at = clock and clock() or Runtime.now(api)
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

---@alias ALCommandWriter fun(payload?: any, context?: table): any, table?
---@alias ALCommands table<ALCommandName, ALCommandWriter>

-- The store commands one channel writes through, and no others. Each sends its
-- payload as the acting character at the clock's time; a channel passes its own
-- context when it adds fields such as a vendor name. A command returns the
-- store's result and the context, or nothing when no character can act.
---@param api table
---@param clock fun(): integer?
---@param store fun(): ALStore
---@param names ALCommandName[]
---@return ALCommands
function Runtime.commands(api, clock, store, names)
    local commands = {}
    for _, name in ipairs(names) do
        commands[name] = function(payload, context)
            context = context or Runtime.player(api, clock)
            if context then
                return store():command(name, payload, context.at, context), context
            end
        end
    end
    return commands
end

addon.Runtime = Runtime
