local _, addon = ...

-- Owns what the Collection says about an item: its ownership status from the
-- last checks, how you got it, and its Source. Callers pass a state and get
-- wording back; they never compare labels.
local LastSeen = {}
local areas = { "bags", "bank", "equipped" }

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = copy(item)
    end
    return result
end

local function stamp(seconds)
    return seconds and date("%Y-%m-%d %H:%M", seconds) or "Unknown"
end

local ownershipOrder = { "present", "unknown", "historical" }
local ownershipStates = {
    present = {
        label = "Present",
        colour = "green",
        help = "Present: the item was found on at least one character in the selected view.",
    },
    unknown = {
        label = "Unknown",
        colour = "gold",
        help = "Unknown: the addon could not check all the storage it needs, "
            .. "so it cannot tell whether the item is still there.",
    },
    historical = {
        label = "Historical only",
        colour = "gold",
        help = "Historical only: the item was found before, but not on complete checks of the selected "
            .. "characters' relevant bags, bank, and gear. "
            .. "This describes the last check dates, not where the item is now.",
    },
}

---@class ALOwnershipWording
---@field label string
---@field help string
---@field colour string A BookWidgets colour name

---@param state string
---@return ALOwnershipWording?
function LastSeen.ownership(state)
    return copy(ownershipStates[state])
end

---@return {label: string, value?: string}[]
function LastSeen.ownershipChoices()
    local result = { { label = "Any status" } }
    for _, state in ipairs(ownershipOrder) do
        result[#result + 1] = { label = ownershipStates[state].label, value = state }
    end
    return result
end

---@param lastSeen ALLastSeen
---@return string
function LastSeen.ownershipText(lastSeen)
    local label = ownershipStates[lastSeen.state].label
    return lastSeen.state == "historical" and (label .. " as of " .. stamp(lastSeen.asOf)) or label
end

-- How you got it. Units at a first check were Seen; a confirmed gain was Looted
-- or Obtained. `source` names the breakdown bucket for units with no recorded Source.
local methodOrder = { "Seen", "Appeared", "Looted", "Quest", "Crafted", "Vendor", "Obtained", "Transfer" }
local methods = {
    Seen = {
        label = "Already had at first check",
        choice = "Already had",
        fact = "Seen",
        group = "Seen",
        source = "Initial stock",
    },
    Appeared = {
        label = "Appeared after an earlier check",
        choice = "Appeared later",
        fact = "Appeared later",
        group = "Seen",
        source = "Appeared later",
    },
    Looted = { label = "Looted", choice = "Looted", fact = "Looted", group = "Looted" },
    Quest = { label = "Quest", choice = "Quest reward", fact = "Obtained (Quest)", group = "Obtained" },
    Crafted = { label = "Crafted", choice = "Crafted", fact = "Obtained (Crafted)", group = "Obtained" },
    Vendor = { label = "Vendor", choice = "Vendor purchase", fact = "Obtained (Vendor)", group = "Obtained" },
    Obtained = { label = "Obtained", choice = "Obtained", fact = "Obtained (way unknown)", group = "Obtained" },
    Transfer = { label = "Transfer from another character", group = "Transfer", source = "Your characters" },
}
local bucketLabels = {
    ["Initial stock"] = "Already had before first check",
    ["Appeared later"] = "Unknown, appeared after an earlier check",
    ["Your characters"] = "Your other characters",
}

---@class ALMethodWording
---@field label string Breakdown label
---@field group 'Seen'|'Looted'|'Obtained'|'Transfer' Glossary term
---@field choice? string Filter label; Transfers are not filtered
---@field fact? string Tooltip fact
---@field source? string Breakdown Source for units with no recorded Source

---@param method string
---@return ALMethodWording?
function LastSeen.method(method)
    return copy(methods[method])
end

---@param method string
---@return string
function LastSeen.methodLabel(method)
    return methods[method] and methods[method].label or method
end

---@param appeared boolean? Units arrived after an earlier complete check
---@return 'Seen'|'Appeared'
function LastSeen.firstCheckMethod(appeared)
    return appeared and "Appeared" or "Seen"
end

---@return {label: string, value?: string}[]
function LastSeen.methodChoices()
    local result = { { label = "Any method" } }
    for _, method in ipairs(methodOrder) do
        if methods[method].choice then
            result[#result + 1] = { label = methods[method].choice, value = method }
        end
    end
    return result
end

---@param record {firstSeenUnits: integer, firstSeenLater?: boolean}
---@param summary {methods: table<string, boolean>, hasGains: boolean}
---@return string[]
function LastSeen.tooltipFacts(record, summary)
    local facts = {}
    if record.firstSeenUnits > 0 or not summary.hasGains then
        local method = LastSeen.firstCheckMethod(record.firstSeenLater and record.firstSeenUnits > 0)
        facts[1] = methods[method].fact
    end
    for _, method in ipairs(methodOrder) do
        if methods[method].group ~= "Seen" and methods[method].fact and summary.methods[method] then
            facts[#facts + 1] = methods[method].fact
        end
    end
    return facts
end

-- The Journal names how a gain arrived, including mail and trade with no other proof.
---@param gain AzerothLedgerGain
---@return string
function LastSeen.gainAction(gain)
    if gain.method == "Obtained" and not gain.mailKind then
        return ({ mail = "Mail", trade = "Trade" })[gain.channel] or methods.Obtained.fact
    end
    return gain.mailKind == "auction-purchase" and "Auction purchase"
        or gain.method == "Vendor" and "Purchase"
        or gain.method
end

-- The entry ID identifies the creature/container type; the final field identifies a
-- particular spawn. Keep the complete GUID in the gain as its original proof.
local function entryID(source)
    if not source or (source.kind ~= "container" and source.kind ~= "mob") then
        return nil
    end
    local prefix = source.kind == "container" and "GameObject" or "Creature"
    local id = source.guid:match("^" .. prefix .. "%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    local entry = id and tonumber(id)
    return entry and entry > 0 and entry <= 4294967295 and tostring(entry) or nil
end

---@param source? AzerothLedgerLootSource|AzerothLedgerVendorSource|AzerothLedgerPlayerSource
---@return string
function LastSeen.sourceText(source)
    if not source then
        return "Unknown"
    elseif source.kind == "player" then
        return source.name .. "-" .. source.realm
    end
    local id = entryID(source)
    local kind = source.kind == "container" and "Container" or "Mob"
    return source.name or (id and (kind .. " #" .. id)) or ("Unnamed " .. source.kind)
end

---@param gain AzerothLedgerGain
---@return string
function LastSeen.gainSourceText(gain)
    if gain.mailKind == "auction-purchase" then
        return "Auction purchase"
    elseif gain.source then
        return LastSeen.sourceText(gain.source)
    elseif gain.context then
        return gain.context.name or (gain.context.kind .. " " .. gain.context.id)
    end
    return "Unknown source"
end

-- Identity is independent of its display name. Unparseable GUIDs remain
-- separate spawn evidence; vendor names explicitly carry no proven ID.
---@param gain AzerothLedgerGain
---@return string key
---@return string neutral
---@return string? name
function LastSeen.sourceIdentity(gain)
    local context = gain.context
    if context then
        local kind = context.kind == "quest" and "Quest" or "Recipe"
        return context.kind .. ":" .. context.id, kind .. " #" .. context.id, context.name
    elseif gain.mailKind == "auction-purchase" then
        return "auction", "Auction purchase"
    end
    local source = gain.source
    if not source then
        return "unknown", "Unknown"
    elseif source.kind == "player" then
        local label = source.name .. "-" .. source.realm
        return "player:" .. label, "Player: " .. label
    elseif source.kind == "vendor" then
        return "vendor:" .. source.name, "Vendor: " .. source.name
    end
    local id = entryID(source)
    local kind = source.kind == "container" and "Container" or "Mob"
    return source.kind .. ":" .. (id or source.guid),
        id and (kind .. " #" .. id) or ("Unknown " .. source.kind),
        source.name
end

---@class ALSourceGroup
---@field key string
---@field neutral string
---@field quantity integer
---@field names table<string, boolean>
---@field label? string

---@param groups table<string, ALSourceGroup>
---@param gain AzerothLedgerGain
---@param quantity integer
function LastSeen.addSource(groups, gain, quantity)
    if quantity <= 0 then
        return
    end
    local key, neutral, name = LastSeen.sourceIdentity(gain)
    local group = groups[key] or { key = key, neutral = neutral, quantity = 0, names = {} }
    groups[key] = group
    group.quantity = group.quantity + quantity
    if name then
        group.names[name] = true
    end
end

---@param groups table<string, ALSourceGroup>
---@param pause? fun()
---@return ALSourceGroup[]
function LastSeen.sourceGroups(groups, pause)
    -- Source comparisons are small; checkpoint in bounded batches rather than
    -- spending a coroutine resume on each comparison of a large source list.
    local steps = 0
    local checkpoint = pause
            and function()
                steps = steps + 1
                if steps == 8 then
                    steps = 0
                    pause()
                end
            end
        or nil
    local rows, labels = {}, {}
    for _, group in pairs(groups) do
        local name = next(group.names)
        group.label = name and not next(group.names, name) and name or group.neutral
        labels[group.label] = (labels[group.label] or 0) + 1
        rows[#rows + 1] = group
        if checkpoint then
            checkpoint()
        end
    end
    addon.Work.sort(rows, function(left, right)
        return left.key < right.key
    end, checkpoint)
    -- Breakdown buckets share the label space, so a recorded Source never takes one.
    local used = {}
    for bucket in pairs(bucketLabels) do
        used[bucket] = true
    end
    for index, group in ipairs(rows) do
        if labels[group.label] > 1 or used[group.label] then
            local identity = group.key:match("^(%a+:%d+)$")
            group.label = group.label
                .. " ("
                .. (identity and identity:gsub(":", " #", 1) or ("recorded source " .. index))
                .. ")"
        end
        while used[group.label] do
            group.label = group.label .. " (recorded source " .. index .. ")"
        end
        used[group.label] = true
        if checkpoint then
            checkpoint()
        end
    end
    addon.Work.sort(rows, function(left, right)
        return left.label < right.label or (left.label == right.label and left.key < right.key)
    end, checkpoint)
    return rows
end

-- A breakdown Source is a recorded group label or a first-check bucket.
---@param source string
---@return string
function LastSeen.sourceLabel(source)
    return bucketLabels[source] or source
end

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
            total = { quantity = 0, transferred = 0, firstSeenAt = seen.firstSeen }
            actorOveralls[key] = total
        elseif seen.firstSeen < total.firstSeenAt then
            total.firstSeenAt = seen.firstSeen
        end
        total.quantity = total.quantity + seen.firstSeenUnits
        total.transferred = total.transferred + (seen.transferredUnits or 0)
    end
    for _, gain in ipairs(record.gains or {}) do
        local key = gain.realm .. ":" .. gain.character
        local total = actorOveralls[key]
        if not total then
            total = { quantity = 0, transferred = 0 }
            actorOveralls[key] = total
        end
        if
            total.firstSeenAt
            and gain.openedAt
            and gain.openedAt <= total.firstSeenAt
            and gain.baselinePossessionsComplete == false
        then
            total.ambiguous = true
        else
            -- First-check units exclude every unit a gain explains, so each gain adds.
            total.quantity = total.quantity + gain.quantity - (gain.refunded or 0)
        end
    end
    -- Units moved in from another of your characters belong to this character's
    -- overall, but the account already counted them where they started.
    local function overallFor(actorName, actorRealm, withTransfers)
        local total = actorOveralls[actorRealm .. ":" .. actorName]
        if not total then
            return 0
        end
        if total.ambiguous then
            return nil
        end
        return total.quantity + (withTransfers and total.transferred or 0)
    end
    if targetName and targetRealm then
        result.characterOverall = overallFor(targetName, targetRealm, true)
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
