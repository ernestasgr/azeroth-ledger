local _, addon = ...
local LastSeen = {}
local areas = { "bags", "bank", "equipped" }

local function matches(scope, character, realm)
    return (not scope.character or scope.character == character) and (not scope.realm or scope.realm == realm)
end

local function observationFor(record, character, realm, area)
    local latest
    for _, observation in ipairs(record.observations or {}) do
        if observation.character == character and observation.realm == realm and observation.area == area then
            if not latest or observation.seenAt >= latest.seenAt then
                latest = observation
            end
        end
    end
    return latest
end

---@class ALStorageCheck
---@field character string
---@field realm string
---@field area string
---@field quantity? integer
---@field at? integer
---@field online boolean
---@field observedQuantity? integer
---@field observedAt? integer

---@class ALLastSeen
---@field state 'present'|'unknown'|'historical'
---@field asOf? integer
---@field checks ALStorageCheck[]
---@field characterOverall? integer
---@field allCharactersOverall? integer
---@field characterCurrent? integer
---@field allCharactersCurrent? integer
---@field currentAt? integer
---@field latestCheck? {character: string, realm: string, area: string, quantity?: integer, at: integer}

---@param store ALStore
---@param record AzerothLedgerRecord|ALRecordDescription
---@param character string
---@param realm string
---@param scope? AzerothLedgerCollectionFilter
---@return ALLastSeen
-- Project dated storage facts and counts once. Counts use each area's latest
-- known quantity, even when that observation is stale or belongs to an offline character.
function LastSeen.project(store, record, character, realm, scope)
    scope = scope or {}
    local characters, selected, allCharacters, allSelected = {}, {}, {}, {}
    local function addAll(name, actorRealm)
        local key = actorRealm .. ":" .. name
        if not allSelected[key] then
            allSelected[key] = true
            allCharacters[#allCharacters + 1] = { name = name, realm = actorRealm }
        end
    end
    local function add(name, actorRealm)
        local key = actorRealm .. ":" .. name
        if matches(scope, name, actorRealm) and not selected[key] then
            selected[key] = true
            characters[#characters + 1] = { name = name, realm = actorRealm }
        end
    end
    addAll(character, realm)
    for _, actor in ipairs(store:characters()) do
        addAll(actor.character, actor.realm)
    end
    for _, seen in ipairs(record.characters or {}) do
        addAll(seen.name, seen.realm)
    end
    for _, gain in ipairs(record.gains or {}) do
        addAll(gain.character, gain.realm)
    end
    for _, actor in ipairs(allCharacters) do
        add(actor.name, actor.realm)
    end

    local result = { checks = {} }
    local present, unknown, earliestCheck, latestCheckAt = false, false, nil, nil
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
                observedQuantity = observation and observation.quantity,
                observedAt = observation and observation.seenAt,
            }
            -- A complete check also dates absence, even in storage where this
            -- item has never been held. Unreadable attempts cannot renew it.
            if state and state.lastCompleteAt and (not observation or state.lastCompleteAt >= observation.seenAt) then
                check.observedQuantity = observation and observation.quantity or 0
                check.observedAt = state.lastCompleteAt
            end
            result.checks[#result.checks + 1] = check
            if check.at and (not latestCheckAt or check.at >= latestCheckAt) then
                latestCheckAt = check.at
                result.latestCheck = check
            end
        end
        if characterCheck then
            earliestCheck = math.min(earliestCheck or characterCheck, characterCheck)
        end
    end
    local targetName, targetRealm = scope.character, scope.realm
    if not targetName then
        targetName, targetRealm = character, realm
    elseif not targetRealm then
        local matchingRealm
        for _, actor in ipairs(allCharacters) do
            if actor.name == targetName then
                if matchingRealm and matchingRealm ~= actor.realm then
                    matchingRealm = nil
                    break
                end
                matchingRealm = actor.realm
            end
        end
        targetRealm = matchingRealm
    end
    if targetRealm and scope.realm and targetRealm ~= scope.realm then
        targetName, targetRealm = nil, nil
    end
    local actorOveralls = {}
    for _, seen in ipairs(record.characters or {}) do
        local key = seen.realm .. ":" .. seen.name
        local total = actorOveralls[key]
        if not total then
            total = { quantity = 0, firstSeenAt = seen.firstSeen }
            actorOveralls[key] = total
        elseif seen.firstSeen < total.firstSeenAt then
            total.firstSeenAt = seen.firstSeen
        end
        total.quantity = total.quantity + seen.firstSeenUnits
    end
    for _, gain in ipairs(record.gains or {}) do
        local key = gain.realm .. ":" .. gain.character
        local total = actorOveralls[key]
        if not total then
            total = { quantity = 0 }
            actorOveralls[key] = total
        end
        if
            total.firstSeenAt
            and gain.openedAt
            and gain.openedAt <= total.firstSeenAt
            and gain.baselinePossessionsComplete == false
        then
            total.ambiguous = true
        elseif
            not total.firstSeenAt
            or (gain.openedAt and gain.openedAt <= total.firstSeenAt)
            or gain.at > total.firstSeenAt
        then
            total.quantity = total.quantity + gain.quantity - (gain.refunded or 0)
        end
    end
    local function overallFor(actorName, actorRealm)
        local total = actorOveralls[actorRealm .. ":" .. actorName]
        if not total then
            return 0
        end
        if total.ambiguous then
            return nil
        end
        return total.quantity
    end
    if targetName and targetRealm then
        result.characterOverall = overallFor(targetName, targetRealm)
    end
    local allCharactersOverall, allCharactersOverallKnown = 0, true
    for _, actor in ipairs(allCharacters) do
        local quantity = overallFor(actor.name, actor.realm)
        if quantity == nil then
            allCharactersOverallKnown = false
        else
            allCharactersOverall = allCharactersOverall + quantity
        end
    end
    if allCharactersOverallKnown then
        result.allCharactersOverall = allCharactersOverall
    end

    local function latestKnownQuantity(actor, area)
        local state = store:area(actor.name, actor.realm, area)
        local observation = observationFor(record, actor.name, actor.realm, area)
        if state and state.lastCompleteAt and (not observation or state.lastCompleteAt >= observation.seenAt) then
            -- A complete check proves zero when it found no copy of this item.
            return observation and observation.quantity or 0, state.lastCompleteAt
        end
        if observation then
            return observation.quantity, observation.seenAt
        end
        return nil
    end
    local function currentQuantity(actors)
        local quantity, latestAt, found = 0, nil, false
        for _, actor in ipairs(actors) do
            for _, area in ipairs(areas) do
                local areaQuantity, at = latestKnownQuantity(actor, area)
                if areaQuantity ~= nil and at ~= nil then
                    found = true
                    quantity = quantity + areaQuantity
                    latestAt = math.max(latestAt or at, at)
                end
            end
        end
        return found and quantity or nil, latestAt
    end
    if targetName and targetRealm then
        result.characterCurrent, result.currentAt = currentQuantity({ { name = targetName, realm = targetRealm } })
    end
    result.allCharactersCurrent = currentQuantity(allCharacters)
    result.state = present and "present" or ((unknown or #characters == 0) and "unknown" or "historical")
    result.asOf = earliestCheck
    return result
end

addon.LastSeen = LastSeen
