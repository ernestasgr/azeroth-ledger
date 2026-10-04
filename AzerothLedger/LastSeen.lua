local _, addon = ...
local LastSeen = {}
local areas = { "bags", "bank", "equipped" }

local function matches(scope, character, realm)
    return (not scope.character or scope.character == character) and (not scope.realm or scope.realm == realm)
end

local function observationFor(record, character, realm, area)
    local latest
    for _, observation in ipairs(record.observations) do
        if observation.character == character and observation.realm == realm and observation.area == area then
            if not latest or observation.seenAt >= latest.seenAt then
                latest = observation
            end
        end
    end
    return latest
end

---@class ALLastSeen
---@field state 'present'|'unknown'|'historical'
---@field asOf? integer
---@field checks {character: string, realm: string, area: string, quantity?: integer, at?: integer, online: boolean}[]
---@field checkedUnits? integer
---@field checkedAt? integer
---@field uncheckedAreas integer
---@field firstChecked? integer
---@field latestCheck? {character: string, realm: string, area: string, quantity?: integer, at: integer}

---@param store ALStore
---@param record AzerothLedgerRecord
---@param character string
---@param realm string
---@param scope? AzerothLedgerCollectionFilter
---@return ALLastSeen
-- Project dated storage facts once. Display wording is deliberately outside this
-- module, and checked units never imply current ownership on an offline character.
function LastSeen.project(store, record, character, realm, scope)
    scope = scope or {}
    local characters, selected = {}, {}
    local function add(name, actorRealm)
        local key = actorRealm .. ":" .. name
        if matches(scope, name, actorRealm) and not selected[key] then
            selected[key] = true
            characters[#characters + 1] = { name = name, realm = actorRealm }
        end
    end
    add(character, realm)
    for _, actor in ipairs(store:characters()) do
        add(actor.character, actor.realm)
    end
    for _, seen in ipairs(record.characters) do
        add(seen.name, seen.realm)
    end

    local result = { checks = {}, uncheckedAreas = 0 }
    local present, unknown, earliestCheck = false, false, nil
    for _, actor in ipairs(characters) do
        local online = actor.name == character and actor.realm == realm
        local characterCheck
        for _, area in ipairs(areas) do
            local state = store:area(actor.name, actor.realm, area)
            local observation = observationFor(record, actor.name, actor.realm, area)
            local quantity
            if state and state.complete then
                quantity = observation and observation.quantity or 0
                if quantity > 0 then
                    if online then
                        present = true
                    else
                        unknown = true
                    end
                end
                if characterCheck and characterCheck ~= state.seenAt then
                    unknown = true
                end
                characterCheck = state.seenAt
            elseif state and observation and observation.seenAt == state.seenAt then
                quantity = observation.quantity
                if quantity > 0 then
                    if online then
                        present = true
                    else
                        unknown = true
                    end
                else
                    unknown = true
                end
            else
                unknown = true
            end
            local check = {
                character = actor.name,
                realm = actor.realm,
                area = area,
                quantity = quantity,
                at = state and state.seenAt,
                online = online,
            }
            result.checks[#result.checks + 1] = check
            if check.at and (not result.checkedAt or check.at >= result.checkedAt) then
                result.checkedAt = check.at
                result.latestCheck = check
            end
        end
        if characterCheck then
            earliestCheck = math.min(earliestCheck or characterCheck, characterCheck)
        end
    end
    for _, check in ipairs(result.checks) do
        if check.at == result.checkedAt and check.quantity ~= nil then
            result.checkedUnits = (result.checkedUnits or 0) + check.quantity
        else
            result.uncheckedAreas = result.uncheckedAreas + 1
        end
    end
    for _, seen in ipairs(record.characters) do
        if matches(scope, seen.name, seen.realm) then
            for _, observation in ipairs(record.observations) do
                if
                    observation.character == seen.name
                    and observation.realm == seen.realm
                    and observation.quantity > 0
                then
                    result.firstChecked = (result.firstChecked or 0) + observation.quantity
                    break
                end
            end
        end
    end
    result.state = present and "present" or ((unknown or #characters == 0) and "unknown" or "historical")
    result.asOf = earliestCheck
    return result
end

addon.LastSeen = LastSeen
