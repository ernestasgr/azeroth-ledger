local _, addon = ...

-- Owns one opened save: the raw data, records, check areas, Journal history,
-- revision counter, runtime index and the single saveFields commit path. Each
-- domain owns one named part of the save and reaches it only through the
-- handle the kernel gives it.

local V = addon.SchemaValidate
local CURRENT_SCHEMA, retentionDefaults, isInteger = V.CURRENT_SCHEMA, V.retentionDefaults, V.isInteger
local validCheckID, validRetention, gainRoot = V.validCheckID, V.validRetention, V.gainRoot
local chronological, trimHistory, isName, areaKey = V.chronological, V.trimHistory, V.isName, V.areaKey
local copyArray, copyValue, areas, gainMethods = V.copyArray, V.copyValue, V.areas, V.gainMethods
local compactObservations, copyRecord, validPlaceKind = V.compactObservations, V.copyRecord, V.validPlaceKind

---@alias AzerothLedgerPossessions fun(character: string, realm: string): integer Units held before a change

---@class AzerothLedgerSlice
---@field name string The SavedVariables field this domain owns
---@field validate? fun(state: any): boolean
---@field journal? string Retention category of the state's `journal` list
---@field beforeChange? fun(state: table?, key: string, possessions: AzerothLedgerPossessions, before: table?)
---@field discoveries? fun(state: any): boolean Whether newly discovered items are queued for toasts

local StoreKernel = {}

local function validRefunded(gain)
    return gain.refunded == nil
        or (
            gain.method == "Vendor"
            and isInteger(gain.refunded)
            and gain.refunded >= 0
            and gain.refunded <= gain.quantity
        )
end

local function validRecord(key, record)
    if
        type(key) ~= "string"
        or type(record) ~= "table"
        or record.key ~= key
        or (record.evidencedDiscovery ~= nil and type(record.evidencedDiscovery) ~= "boolean")
        or (record.firstSeenLater ~= nil and type(record.firstSeenLater) ~= "boolean")
        or not isInteger(record.itemID)
        or record.itemID <= 0
        or not isInteger(record.firstSeen)
        or not isInteger(record.lastSeen)
        or record.firstSeen < 0
        or record.lastSeen < record.firstSeen
        or not isInteger(record.firstSeenUnits)
        or record.firstSeenUnits < 0
        or not isInteger(record.totalGained)
        or record.totalGained < 0
        or (record.firstGained ~= nil and not isInteger(record.firstGained))
        or (record.lastGained ~= nil and not isInteger(record.lastGained))
        or type(record.links) ~= "table"
        or type(record.characters) ~= "table"
        or type(record.observations) ~= "table"
        or (record.gains ~= nil and type(record.gains) ~= "table")
        or #record.links == 0
        or #record.characters == 0
        or #record.observations == 0
    then
        return false
    end
    for _, link in ipairs(record.links) do
        if addon.Item.key(link, record.itemID) ~= key then
            return false
        end
    end
    for _, character in ipairs(record.characters) do
        if
            type(character) ~= "table"
            or not isName(character.name)
            or not isName(character.realm)
            or not isInteger(character.firstSeen)
            or not isInteger(character.lastSeen)
            or not isInteger(character.firstSeenUnits)
            or (character.transferredUnits ~= nil and not isInteger(character.transferredUnits))
            or (character.firstSeenLater ~= nil and type(character.firstSeenLater) ~= "boolean")
        then
            return false
        end
    end
    for _, observation in ipairs(record.observations) do
        if
            type(observation) ~= "table"
            or not isName(observation.character)
            or not isName(observation.realm)
            or not areas[observation.area]
            or not isInteger(observation.seenAt)
            or not isInteger(observation.quantity)
            or observation.quantity < 0
        then
            return false
        end
    end
    local gained = 0
    local gainIDs = {}
    for _, gain in ipairs(record.gains or {}) do
        if
            type(gain) ~= "table"
            or type(gain.id) ~= "string"
            or not isInteger(gain.at)
            or (gain.openedAt ~= nil and not isInteger(gain.openedAt))
            or (gain.baselinePossessionsComplete ~= nil and type(gain.baselinePossessionsComplete) ~= "boolean")
            or not isInteger(gain.quantity)
            or gain.quantity < 1
            or not isName(gain.character)
            or not isName(gain.realm)
            or not isInteger(gain.level)
            or type(gain.place) ~= "string"
            or not validPlaceKind(gain.placeKind)
            or not gainMethods[gain.method]
            or (gain.mailKind ~= nil and (gain.mailKind ~= "auction-purchase" or gain.method ~= "Obtained"))
            or (gain.channel ~= nil and gain.channel ~= "mail" and gain.channel ~= "trade")
            or (gain.channel ~= nil and gain.method ~= "Obtained")
            or not validRefunded(gain)
            or gainIDs[gain.id]
        then
            return false
        end
        if gain.source ~= nil then
            if type(gain.source) ~= "table" or (gain.source.name ~= nil and not isName(gain.source.name)) then
                return false
            end
            if gain.method == "Looted" then
                if (gain.source.kind ~= "mob" and gain.source.kind ~= "container") or not isName(gain.source.guid) then
                    return false
                end
            elseif gain.method == "Vendor" then
                if gain.source.kind ~= "vendor" or not isName(gain.source.name) or gain.source.guid ~= nil then
                    return false
                end
            elseif gain.method == "Obtained" then
                if gain.source.kind ~= "player" or not isName(gain.source.name) or not isName(gain.source.realm) then
                    return false
                end
            else
                return false
            end
        end
        if gain.context ~= nil then
            if
                type(gain.context) ~= "table"
                or gain.method == "Looted"
                or gain.method == "Vendor"
                or gain.context.kind ~= (gain.method == "Quest" and "quest" or "recipe")
                or not isInteger(gain.context.id)
                or gain.context.id < 1
                or (gain.context.name ~= nil and not isName(gain.context.name))
            then
                return false
            end
        end
        gainIDs[gain.id] = true
        if gain.corrections ~= nil then
            if type(gain.corrections) ~= "table" then
                return false
            end
            local ids = {}
            for _, id in ipairs(gain.corrections) do
                if not isName(id) or ids[id] then
                    return false
                end
                ids[id] = true
            end
        end
        gained = gained + gain.quantity - (gain.refunded or 0)
    end
    if gained ~= record.totalGained then
        return false
    end
    if #record.gains > 0 and (not isInteger(record.firstGained) or not isInteger(record.lastGained)) then
        return false
    end
    return true
end

local function recoverableRecord(key, record)
    if
        type(key) ~= "string"
        or type(record) ~= "table"
        or record.key ~= key
        or not isInteger(record.itemID)
        or record.itemID <= 0
        or not isInteger(record.firstSeen)
        or not isInteger(record.lastSeen)
        or not isInteger(record.firstSeenUnits)
        or not isInteger(record.totalGained)
        or type(record.links) ~= "table"
        or type(record.characters) ~= "table"
        or type(record.observations) ~= "table"
        or type(record.gains) ~= "table"
        or #record.links == 0
        or #record.characters == 0
        or #record.observations == 0
    then
        return false
    end
    for _, gain in ipairs(record.gains) do
        if
            type(gain) ~= "table"
            or (gain.source ~= nil and type(gain.source) ~= "table")
            or (gain.context ~= nil and type(gain.context) ~= "table")
        then
            return false
        end
    end
    return true
end

local function validJournal(value)
    if
        type(value) ~= "table"
        or not isInteger(value.nextSequence)
        or value.nextSequence < 1
        or type(value.gains) ~= "table"
    then
        return false
    end
    local seen = {}
    for _, entry in ipairs(value.gains) do
        if
            type(entry) ~= "table"
            or not isName(entry.id)
            or not isName(entry.key)
            or not isInteger(entry.at)
            or not isInteger(entry.sequence)
            or entry.sequence < 1
            or entry.sequence >= value.nextSequence
            or seen[entry.sequence]
        then
            return false
        end
        seen[entry.sequence] = true
    end
    return true
end

local function changeTooltip(facts, gain, direction)
    local actor = areaKey(gain.character, gain.realm, "")
    facts.gained[actor] = (facts.gained[actor] or 0) + direction * (gain.quantity - (gain.refunded or 0))
    facts.methods[gain.method] = (facts.methods[gain.method] or 0) + direction
    facts.count = facts.count + direction
    local quantity = gain.quantity - (gain.refunded or 0)
    if quantity <= 0 then
        return
    end
    local identity, neutral, name = V.sourceIdentity(gain)
    local group = facts.sources[identity] or { quantity = 0, neutral = neutral, names = {} }
    local before = group.quantity
    group.quantity = group.quantity + direction * quantity
    if name then
        group.names[name] = (group.names[name] or 0) + direction
        if group.names[name] == 0 then
            group.names[name] = nil
        end
    end
    facts.sources[identity] = group
    if before <= 0 and group.quantity > 0 then
        facts.sourceCount = facts.sourceCount + 1
        facts.onlySource = identity
    elseif before > 0 and group.quantity <= 0 then
        facts.sourceCount = facts.sourceCount - 1
        facts.sources[identity] = nil
        if facts.sourceCount == 1 then
            facts.onlySource = next(facts.sources)
        end
    end
end

local function emptyTooltip()
    return { methods = {}, sources = {}, gained = {}, count = 0, sourceCount = 0 }
end

local function applyGainPlan(gains, plan, detached)
    local undo = { count = #gains, replacements = {}, removed = {} }
    for index, gain in pairs(plan.replacements) do
        undo.replacements[index] = gains[index]
        gains[index] = detached and copyValue(gain) or gain
    end
    for index = #plan.removed, 1, -1 do
        local position = plan.removed[index]
        undo.removed[position] = table.remove(gains, position)
    end
    for _, gain in ipairs(plan.appended) do
        gains[#gains + 1] = detached and copyValue(gain) or gain
    end
    return undo
end

local function undoGainPlan(gains, plan, undo)
    for index = #gains, undo.count - #plan.removed + 1, -1 do
        gains[index] = nil
    end
    for _, position in ipairs(plan.removed) do
        table.insert(gains, position, undo.removed[position])
    end
    for index, gain in pairs(undo.replacements) do
        gains[index] = gain
    end
end

local function priorQuantity(record, character, realm, area)
    local quantity = 0
    for _, observation in ipairs(record and record.observations or {}) do
        if observation.character == character and observation.realm == realm and observation.area == area then
            quantity = observation.quantity
        end
    end
    return quantity
end

local function possessionsQuantity(record, character, realm)
    return priorQuantity(record, character, realm, "bags") + priorQuantity(record, character, realm, "equipped")
end

local function bagQuantity(record, character, realm)
    return priorQuantity(record, character, realm, "bags")
end

local function checkedPossessions(record, character, realm, equipped)
    return bagQuantity(record, character, realm) + (equipped and equipped.quantity or 0)
end

-- Opens saved data once. Returns the kernel interface and one handle per slice;
-- only the kernel reassigns `raw`, so handles read the slice at each call.
-- Slices are listed in the order their Journal lists receive sequence numbers.
---@param raw any
---@param save fun(value: AzerothLedgerData)
---@param slices AzerothLedgerSlice[]
function StoreKernel.open(raw, save, slices)
    if raw == nil then
        raw = { schema = CURRENT_SCHEMA, records = {}, areas = {} }
        save(raw)
    end
    local supported = type(raw) == "table" and raw.schema == CURRENT_SCHEMA
    local readable = supported and type(raw.records) == "table" and type(raw.areas) == "table"
    local valid, recordHealthy = {}, {}
    local damagedCount = 0
    if readable then
        for key, record in pairs(raw.records) do
            if validRecord(key, record) then
                recordHealthy[key] = true
                valid[key] = copyRecord(record)
                valid[key].observations = compactObservations(valid[key].observations)
            elseif recoverableRecord(key, record) then
                valid[key] = copyRecord(record)
                damagedCount = damagedCount + 1
            else
                damagedCount = damagedCount + 1
            end
        end
        for key, state in pairs(raw.areas) do
            if
                type(key) ~= "string"
                or type(state) ~= "table"
                or not isInteger(state.seenAt)
                or type(state.complete) ~= "boolean"
                or not validCheckID(state.checkID)
                or (state.character ~= nil and not isName(state.character))
                or (state.realm ~= nil and not isName(state.realm))
            then
                damagedCount = damagedCount + 1
            end
        end
    elseif supported then
        damagedCount = 1
    end
    for _, slice in ipairs(slices) do
        if supported and slice.validate and raw[slice.name] ~= nil and not slice.validate(raw[slice.name]) then
            damagedCount = damagedCount + 1
        end
    end
    if supported and raw.retention ~= nil and not validRetention(raw.retention) then
        damagedCount = damagedCount + 1
    end

    local function retention()
        return type(raw) == "table" and validRetention(raw.retention) and copyValue(raw.retention)
            or copyValue(retentionDefaults)
    end
    if supported and raw.journal ~= nil and not validJournal(raw.journal) then
        damagedCount = damagedCount + 1
    end
    if readable then
        for _, slice in ipairs(slices) do
            local state = slice.journal and raw[slice.name]
            for _, entry in ipairs(state and slice.validate(state) and state.journal or {}) do
                if not valid[entry.key] then
                    damagedCount = damagedCount + 1
                end
            end
        end
        for _, entry in ipairs(validJournal(raw.journal) and raw.journal.gains or {}) do
            if not valid[entry.key] then
                damagedCount = damagedCount + 1
            end
        end
    end

    -- Runtime indexes are rebuilt from validated facts, never persisted or pruned.
    local scopeRecords, actorIndex, recordKeys, keyIndex, gainIndex = {}, {}, {}, {}, {}
    local gainPositions, tooltipIndex = {}, {}
    local revision = 0
    local function indexRecord(key, record, edits, suffix)
        if not recordHealthy[key] then
            recordHealthy[key] = validRecord(key, record)
        end
        if not keyIndex[key] then
            recordKeys[#recordKeys + 1], keyIndex[key] = key, true
        end
        local previous = valid[key]
        if edits then
            gainIndex[key], gainPositions[key], tooltipIndex[key] =
                gainIndex[key] or {}, gainPositions[key] or {}, tooltipIndex[key] or emptyTooltip()
            for root, entries in pairs(edits) do
                for _, gain in ipairs(gainIndex[key][root] or {}) do
                    changeTooltip(tooltipIndex[key], gain, -1)
                    gainPositions[key][gain.id] = nil
                end
                gainIndex[key][root] = entries
                for _, gain in ipairs(entries) do
                    changeTooltip(tooltipIndex[key], gain, 1)
                end
            end
            for index = suffix, #record.gains do
                gainPositions[key][record.gains[index].id] = index
            end
        elseif not gainIndex[key] or not previous or previous.gains ~= record.gains then
            local roots, positions, facts = {}, {}, emptyTooltip()
            for index, gain in ipairs(record.gains) do
                local root = gainRoot(gain.id)
                roots[root] = roots[root] or {}
                roots[root][#roots[root] + 1] = gain
                positions[gain.id] = index
                changeTooltip(facts, gain, 1)
            end
            gainIndex[key], gainPositions[key], tooltipIndex[key] = roots, positions, facts
        end
        for _, observation in ipairs(previous and previous.observations or {}) do
            local scope = scopeRecords[areaKey(observation.character, observation.realm, observation.area)]
            if scope then
                scope[key] = nil
            end
        end
        for _, seen in ipairs(record.characters) do
            actorIndex[areaKey(seen.name, seen.realm, "")] = { character = seen.name, realm = seen.realm }
        end
        for _, observation in ipairs(record.observations) do
            local scopeKey = areaKey(observation.character, observation.realm, observation.area)
            scopeRecords[scopeKey] = scopeRecords[scopeKey] or {}
            scopeRecords[scopeKey][key] = observation.quantity > 0 and true or nil
        end
    end
    for key, record in pairs(valid) do
        indexRecord(key, record)
    end

    local function heldKeys(character, realm, area)
        return scopeRecords[areaKey(character, realm, area)] or {}
    end

    local journalHealthy = readable and validJournal(raw.journal)
    local journalEntries = journalHealthy and copyArray(raw.journal.gains) or {}
    table.sort(journalEntries, chronological)
    local function editGainRoot(record, root)
        local result = copyRecord(record, true)
        local edits = {}
        for id, entries in pairs(record.gainEdits or {}) do
            edits[id] = entries
        end
        result.baseGains = record.baseGains or record.gains
        result.gains = copyValue(edits[root] or (gainIndex[record.key] and gainIndex[record.key][root]) or {})
        edits[root], result.gainEdits = result.gains, edits
        return result
    end

    -- Whether the gain's character made the item's earliest sighting. Another
    -- character's earlier or concurrent sighting keeps its own first-check units.
    local function firstFound(record, entry)
        for _, seen in ipairs(record.characters) do
            if seen.firstSeen == record.firstSeen and seen.name == entry.character and seen.realm == entry.realm then
                return true
            end
        end
        return false
    end

    -- Records one confirmed gain on a copy of record, merging by gain id. The
    -- kernel alone writes Total gained, gain dates and discovered first-check
    -- units.
    --
    -- `discovery` says the item was unknown when the action began; `since` is
    -- loot's opening time. Loot measures its discoveries itself and its gains
    -- carry `openedAt`, so Last seen counts them even before their character's
    -- first sighting: their units leave that character's first-check units.
    -- Another channel's gain discovers the item only when its character also
    -- made the earliest sighting. Last seen counts such a gain only after its
    -- character's first sighting, so that character's first-check units keep it.
    ---@param record AzerothLedgerRecord
    ---@param entry table
    ---@param options? {discovery?: boolean, since?: integer, full?: boolean}
    local function recordGain(record, entry, options)
        options = options or {}
        local discovered = options.discovery and (entry.openedAt ~= nil or firstFound(record, entry))
        record = options.full and copyRecord(record) or editGainRoot(record, entry.id)
        local target
        for _, existing in ipairs(record.gains) do
            if existing.id == entry.id then
                target = existing
                break
            end
        end
        if target then
            target.quantity = target.quantity + entry.quantity
        else
            target = entry
            record.gains[#record.gains + 1] = entry
        end
        local quantity = entry.quantity
        record.totalGained = record.totalGained + quantity
        -- The dates only widen; the book derives its dates from the gains themselves.
        record.firstGained = record.firstGained and math.min(record.firstGained, target.at) or target.at
        record.lastGained = record.lastGained and math.max(record.lastGained, target.at) or target.at
        if discovered then
            record.evidencedDiscovery = true
            if not options.since or record.firstSeen >= options.since then
                record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
            end
            for _, seen in ipairs(entry.openedAt and record.characters or {}) do
                if seen.name == entry.character and seen.realm == entry.realm then
                    seen.firstSeenUnits = math.max(0, seen.firstSeenUnits - quantity)
                    break
                end
            end
        end
        return record
    end

    -- Refunds units of one earlier gain with the given method, on a copy of
    -- record. Returns nil when that gain cannot absorb the refund.
    ---@param record AzerothLedgerRecord
    ---@param gainID string
    ---@param quantity integer
    ---@param method string
    local function recordRefund(record, gainID, quantity, method)
        record = copyRecord(record)
        for _, entry in ipairs(record.gains) do
            if entry.id == gainID and entry.method == method and entry.quantity - (entry.refunded or 0) >= quantity then
                if record.totalGained < quantity then
                    return nil
                end
                entry.refunded = (entry.refunded or 0) + quantity
                record.totalGained = record.totalGained - quantity
                return record
            end
        end
        return nil
    end

    local function netGained(entries)
        local total = 0
        for _, entry in ipairs(entries or {}) do
            total = total + entry.quantity - (entry.refunded or 0)
        end
        return total
    end

    -- Total gained follows from the gains: the saved total moves by exactly the
    -- net change of the edited gain groups, or of the whole list when copied.
    local function derivedGained(key, record)
        local before = valid[key]
        local total = before and before.totalGained or 0
        if record.baseGains then
            for root, entries in pairs(record.gainEdits) do
                total = total + netGained(entries) - netGained(gainIndex[key] and gainIndex[key][root])
            end
        elseif not before or record.gains ~= before.gains then
            total = total + netGained(record.gains) - netGained(before and before.gains)
        end
        return total
    end

    local function gainPlan(key, record)
        local plan = {
            replacements = {},
            removed = {},
            appended = {},
            edits = record.gainEdits,
            base = record.baseGains,
            suffix = #record.baseGains + 1,
        }
        for root, entries in pairs(record.gainEdits) do
            local old = gainIndex[key] and gainIndex[key][root] or {}
            for index, gain in ipairs(old) do
                local position = gainPositions[key][gain.id]
                plan.suffix = math.min(plan.suffix, position)
                if entries[index] then
                    plan.replacements[position] = entries[index]
                else
                    plan.removed[#plan.removed + 1] = position
                end
            end
            for index = #old + 1, #entries do
                plan.appended[#plan.appended + 1] = entries[index]
            end
        end
        table.sort(plan.removed)
        table.sort(plan.appended, function(left, right)
            return left.at < right.at or (left.at == right.at and left.id < right.id)
        end)
        return plan
    end

    local discoveries = {}
    local function saveFields(fields)
        local nextValue = {
            schema = CURRENT_SCHEMA,
            records = raw.records,
            areas = fields.areas or raw.areas,
            retention = fields.retention or raw.retention,
            journal = journalHealthy and raw.journal or { nextSequence = 1, gains = {} },
        }
        for _, slice in ipairs(slices) do
            nextValue[slice.name] = fields[slice.name] or raw[slice.name]
        end
        local history = { nextSequence = nextValue.journal.nextSequence, gains = journalEntries }
        nextValue.journal = history
        local function sequence(entry)
            entry.sequence = history.nextSequence
            history.nextSequence = history.nextSequence + 1
        end
        -- Permanent contributions are assembled first. Only their new event roots
        -- enter history; corrections and later shares cannot resurrect pruned rows.
        local pending = {}
        for key, record in pairs(fields.records or {}) do
            if not valid[key] or record.gains ~= valid[key].gains then
                local known = {}
                for _, entries in pairs(record.gainEdits or { record.gains }) do
                    for _, gain in ipairs(entries) do
                        local id = gainRoot(gain.id)
                        if not known[id] and not (gainIndex[key] and gainIndex[key][id]) then
                            pending[#pending + 1] = { id = id, key = key, at = gain.at }
                            known[id] = true
                        end
                    end
                end
            end
        end
        -- A single scan can commit several items. Sort these explicitly rather
        -- than letting Lua's hash iteration choose their sequence.
        table.sort(pending, function(a, b)
            if a.at ~= b.at then
                return a.at < b.at
            end
            if a.id ~= b.id then
                return a.id < b.id
            end
            return a.key < b.key
        end)
        if #pending > 0 or fields.retention then
            history.gains = copyArray(history.gains)
        end
        for _, entry in ipairs(pending) do
            sequence(entry)
            local first, last = 1, #history.gains
            while first <= last do
                local middle = math.floor((first + last) / 2)
                if chronological(history.gains[middle], entry) then
                    first = middle + 1
                else
                    last = middle - 1
                end
            end
            table.insert(history.gains, first, entry)
        end
        local limits = validRetention(nextValue.retention) and nextValue.retention or retentionDefaults
        if #pending > 0 or fields.retention then
            trimHistory(history.gains, limits.gains, true)
        end
        for _, slice in ipairs(slices) do
            local state = slice.journal and nextValue[slice.name]
            if state and (fields[slice.name] or fields.retention) and slice.validate(state) then
                state = copyValue(state)
                nextValue[slice.name] = state
                for _, entry in ipairs(state.journal) do
                    if not isInteger(entry.sequence) or entry.sequence < 1 then
                        sequence(entry)
                    end
                end
                trimHistory(state.journal, limits[slice.journal])
            end
        end
        local discovered = {}
        for key, record in pairs(fields.records or {}) do
            if record.evidencedDiscovery and not (raw.records[key] and raw.records[key].evidencedDiscovery) then
                discovered[#discovered + 1] = copyRecord(record)
            end
        end
        table.sort(discovered, function(a, b)
            return a.key < b.key
        end)
        -- Capture previously unheld items lazily before their first change during
        -- an active action. Late item identification keeps the pre-action totals.
        local previousRecords, plans = {}, {}
        for key, record in pairs(fields.records or {}) do
            local before = valid[key]
            local function possessions(character, realm)
                return possessionsQuantity(before, character, realm)
            end
            for _, slice in ipairs(slices) do
                if slice.beforeChange then
                    slice.beforeChange(nextValue[slice.name], key, possessions, before)
                end
            end
            record.observations = compactObservations(record.observations)
            record.totalGained = derivedGained(key, record)
            previousRecords[key] = raw.records[key] or false
            local persisted = copyRecord(record, true)
            if record.baseGains then
                local plan = gainPlan(key, record)
                local gains = raw.records[key] and raw.records[key].gains or {}
                plan.saved, plan.undo = gains, applyGainPlan(gains, plan, true)
                plans[key] = plan
                persisted.gains = gains
            elseif valid[key] and record.gains == valid[key].gains then
                persisted.gains = raw.records[key].gains
            else
                persisted.gains = copyValue(record.gains)
            end
            persisted.baseGains, persisted.gainEdits = nil, nil
            nextValue.records[key] = persisted
        end
        local savedOK, failure = pcall(save, nextValue)
        if not savedOK then
            for _, plan in pairs(plans) do
                undoGainPlan(plan.saved, plan, plan.undo)
            end
            for key, record in pairs(previousRecords) do
                raw.records[key] = record or nil
            end
            error(failure)
        end
        for key, record in pairs(fields.records or {}) do
            local plan = plans[key]
            if plan then
                applyGainPlan(plan.base, plan, false)
                record.gains, record.baseGains, record.gainEdits = plan.base, nil, nil
            end
            indexRecord(key, record, plan and plan.edits, plan and plan.suffix)
        end
        revision = revision + 1
        journalHealthy = true
        journalEntries = history.gains
        raw = nextValue
        local queue = true
        for _, slice in ipairs(slices) do
            if slice.discoveries and not slice.discoveries(nextValue[slice.name]) then
                queue = false
            end
        end
        if queue then
            for _, record in ipairs(discovered) do
                discoveries[#discoveries + 1] = record
            end
        end
    end

    local function characterGained(record, character, realm)
        local function quantity(gain)
            return gain.character == character and gain.realm == realm and (gain.quantity - (gain.refunded or 0)) or 0
        end
        local facts = record and tooltipIndex[record.key]
        if facts and (record.baseGains or record.gains == valid[record.key].gains) then
            local total = facts.gained[areaKey(character, realm, "")] or 0
            for root, entries in pairs(record.gainEdits or {}) do
                for _, gain in ipairs(gainIndex[record.key][root] or {}) do
                    total = total - quantity(gain)
                end
                for _, gain in ipairs(entries) do
                    total = total + quantity(gain)
                end
            end
            return total
        end
        local total = 0
        for _, gain in ipairs(record and record.gains or {}) do
            total = total + quantity(gain)
        end
        return total
    end

    -- Each domain reads its own slice through its handle; `healthy` is fixed at open.
    local handles = {}
    for _, slice in ipairs(slices) do
        local name, validate = slice.name, slice.validate
        local function state()
            return type(raw) == "table" and raw[name] or nil
        end
        handles[name] = {
            state = state,
            healthy = readable and (raw[name] == nil or not validate or validate(raw[name])),
            damaged = function()
                return state() ~= nil and validate ~= nil and not validate(state())
            end,
        }
    end

    return {
        supported = supported,
        readable = readable,
        damagedCount = damagedCount,
        -- Validated facts by key; callers replace entries after each save.
        valid = valid,
        recordHealthy = recordHealthy,
        validRecord = validRecord,
        schema = function()
            return type(raw) == "table" and raw.schema or nil
        end,
        -- The dated check of one character's bags, bank or equipped gear.
        area = function(scopeKey)
            return raw.areas[scopeKey]
        end,
        areas = function()
            return raw.areas
        end,
        journal = function()
            return raw.journal
        end,
        journalDamaged = function()
            return raw.journal ~= nil and not validJournal(raw.journal)
        end,
        -- The Journal lists slices keep beside the gain history, in slice order.
        journalLists = function()
            local lists = {}
            for _, slice in ipairs(slices) do
                if slice.journal then
                    local handle = handles[slice.name]
                    local state = handle.state()
                    lists[#lists + 1] = {
                        retention = slice.journal,
                        entries = state and handle.healthy and state.journal or {},
                        damaged = handle.damaged,
                    }
                end
            end
            return lists
        end,
        save = saveFields,
        retention = retention,
        revision = function()
            return revision
        end,
        journalHealthy = function()
            return journalHealthy
        end,
        takeDiscoveries = function()
            local result = discoveries
            discoveries = {}
            return result
        end,
        count = function()
            return #recordKeys
        end,
        keyAt = function(index)
            return recordKeys[index]
        end,
        actors = function()
            return actorIndex
        end,
        tooltip = function(key)
            return tooltipIndex[key]
        end,
        gains = function(key, root)
            return gainIndex[key] and gainIndex[key][root]
        end,
        heldKeys = heldKeys,
        gain = recordGain,
        refund = recordRefund,
        characterGained = characterGained,
        areaQuantity = priorQuantity,
        bagQuantity = bagQuantity,
        possessionsQuantity = possessionsQuantity,
        checkedPossessions = checkedPossessions,
    },
        handles
end

addon.StoreKernel = StoreKernel
