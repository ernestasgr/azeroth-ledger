local _, addon = ...

-- Owns one opened save: the raw data, records, check areas, Journal history,
-- revision counter, runtime index and the single saveFields commit path. Each
-- domain owns one named part of the save and reaches it only through the
-- handle the kernel gives it.

local V = addon.SchemaValidate
local CURRENT_SCHEMA, retentionDefaults, isInteger = V.CURRENT_SCHEMA, V.retentionDefaults, V.isInteger
local validCheckID, validRetention, gainRoot = V.validCheckID, V.validRetention, V.gainRoot
local chronological, trimHistory, isName, areaKey = V.chronological, V.trimHistory, V.isName, V.areaKey
local copyArray, copyValue = V.copyArray, V.copyValue
local compactObservations, copyRecord = V.compactObservations, V.copyRecord

---@alias AzerothLedgerPossessions fun(character: string, realm: string): integer Units held before a change

---@class AzerothLedgerSlice
---@field name string The SavedVariables field this domain owns
---@field validate? fun(state: any): boolean
---@field journal? string Retention category of the state's `journal` list
---@field beforeChange? fun(state: table?, key: string, possessions: AzerothLedgerPossessions, before: table?)
---@field discoveries? fun(state: any): boolean Whether newly discovered items are queued for toasts

local StoreKernel = {}

local Check, Gain = addon.StoreRecordCheck, addon.StoreGainMath
local validRecord, recoverableRecord = Check.validRecord, Check.recoverableRecord
local validJournal, changeTooltip, emptyTooltip = Check.validJournal, Gain.changeTooltip, Gain.emptyTooltip
local applyGainPlan, undoGainPlan, priorQuantity = Gain.applyGainPlan, Gain.undoGainPlan, Gain.priorQuantity
local possessionsQuantity, bagQuantity = Gain.possessionsQuantity, Gain.bagQuantity
local checkedPossessions, firstFound = Gain.checkedPossessions, Gain.firstFound
local recordRefund = Gain.recordRefund

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

    -- Records one confirmed gain on a copy of record, merging by gain id. The
    -- kernel alone writes Total gained, gain dates and discovered first-check
    -- units.
    --
    -- `discovery` says the item was unknown when the action began; `since` is
    -- loot's opening time. Loot measures its discoveries itself; another
    -- channel's gain discovers the item only when its character also made the
    -- earliest sighting.
    --
    -- A character's first-check units exclude every unit its gains explain, so
    -- every view counts first-check units plus gains. A discovery leaves them,
    -- and so does any other gain made before the character's first sighting:
    -- that sighting already held the gained units. Loot handles its own
    -- sightings and leaves only on a measured discovery.
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
        -- A check can credit one record twice before it saves, and the second
        -- credit reads this total; kernel.save then derives the saved total.
        record.totalGained = record.totalGained + quantity
        -- The dates only widen; the book derives its dates from the gains themselves.
        record.firstGained = record.firstGained and math.min(record.firstGained, target.at) or target.at
        record.lastGained = record.lastGained and math.max(record.lastGained, target.at) or target.at
        if discovered then
            record.evidencedDiscovery = true
            if not options.since or record.firstSeen >= options.since then
                record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
            end
        end
        for _, seen in ipairs(record.characters) do
            if seen.name == entry.character and seen.realm == entry.realm then
                if discovered or (entry.openedAt == nil and target.at <= seen.firstSeen) then
                    seen.firstSeenUnits = math.max(0, seen.firstSeenUnits - quantity)
                end
                break
            end
        end
        return record
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
            record.totalGained = Gain.derivedGained(valid[key], record, gainIndex[key])
            previousRecords[key] = raw.records[key] or false
            local persisted = copyRecord(record, true)
            if record.baseGains then
                local plan = Gain.gainPlan(record, gainIndex[key], gainPositions[key])
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
        recordGain = recordGain,
        recordRefund = recordRefund,
        characterGained = characterGained,
        areaQuantity = priorQuantity,
        bagQuantity = bagQuantity,
        possessionsQuantity = possessionsQuantity,
        checkedPossessions = checkedPossessions,
    },
        handles
end

addon.StoreKernel = StoreKernel
