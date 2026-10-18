local _, addon = ...

-- The one entry point for store writes: loot, quest and craft rewards, vendor
-- actions, mail and trade. It checks each action's time and character once,
-- ends the correlation the action outlives, counts candidate signals against
-- the per-character limit, and passes the action to the domain that declared it.
--
-- One login plays one character, and changing character reloads the UI and
-- reopens the store. So a store accepts writes only from the character it was
-- logged in as; any other character's write is refused.

local V = addon.SchemaValidate
local isInteger, isName = V.isInteger, V.isName

---@class AzerothLedgerCommand
---@field valid fun(payload: any, actor: table): boolean Whether the action is well formed
---@field run fun(payload: any, at: integer, actor: table): any
---@field cost? integer|fun(payload: any): integer The candidate limit a candidate signal takes
---@field unmatched? boolean Whether a refused receipt is kept as unmatched evidence

local StoreCommand = {}

-- Merges each domain's commands into one table. A name declared twice is a
-- wiring error, never an override.
---@param lists table<string, AzerothLedgerCommand>[]
---@return table<string, AzerothLedgerCommand>
function StoreCommand.merge(lists)
    local commands = {}
    for _, list in ipairs(lists) do
        for name, command in pairs(list) do
            assert(not commands[name], "store command declared twice: " .. name)
            commands[name] = command
        end
    end
    return commands
end

---@param commands table<string, AzerothLedgerCommand>
function StoreCommand.install(store, kernel, correlation, commands)
    local readable, saveFields = kernel.readable, kernel.save
    local evidenceState, retain = correlation.state, correlation.retain
    local endCorrelation, reserve = correlation.endCorrelation, correlation.reserve
    local current

    -- Names the character this login plays. It is set once: a second call
    -- succeeds only for the same character.
    function store.setCharacter(_self, character, realm)
        if not isName(character) or not isName(realm) then
            return false
        end
        if current then
            return current.character == character and current.realm == realm
        end
        current = { character = character, realm = realm }
        return true
    end

    ---@param name string
    ---@param payload any
    ---@param at integer
    ---@param actor AzerothLedgerActor
    function store.command(_self, name, payload, at, actor)
        local command = commands[name]
        if
            not command
            or not readable
            or not isInteger(at)
            or at < 0
            or not current
            or type(actor) ~= "table"
            or actor.character ~= current.character
            or actor.realm ~= current.realm
            or not command.valid(payload, actor)
        then
            return false
        end
        -- Pending actions at least 60 seconds older than this one end before
        -- it can match them; a reload already ended the rest when the store
        -- opened. A malformed action never moves correlation.
        if not endCorrelation(at, "expired") then
            return false
        end
        local cost = command.cost
        if type(cost) == "function" then
            cost = cost(payload)
        end
        if cost then
            local detail = type(payload) == "table" and payload or { value = payload }
            if not reserve(name, detail, at, actor, math.max(1, cost)) then
                return false
            end
        end
        local result = command.run(payload, at, actor)
        if not result and command.unmatched then
            local evidence = evidenceState()
            if evidence then
                retain(evidence, name, "unmatched", at, actor, payload)
                saveFields({ evidence = evidence })
            end
        end
        return result
    end
end

addon.StoreCommand = StoreCommand
