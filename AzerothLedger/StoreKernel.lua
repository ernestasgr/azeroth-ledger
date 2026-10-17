local _, addon = ...

-- Owns one opened save: the raw data, revision counter, runtime index and the
-- single saveFields commit path. Domain files never touch these directly.

local V = addon.SchemaValidate
local CURRENT_SCHEMA, retentionDefaults, isInteger = V.CURRENT_SCHEMA, V.retentionDefaults, V.isInteger
local validCheckID, validRetention, gainRoot = V.validCheckID, V.validRetention, V.gainRoot
local chronological, trimHistory, isName, areaKey = V.chronological, V.trimHistory, V.isName, V.areaKey
local copyArray, copyValue, validEvidence = V.copyArray, V.copyValue, V.validEvidence
local validLootState, compactObservations, copyRecord = V.validLootState, V.compactObservations, V.copyRecord
local validRecord, recoverableRecord, validEnvironment = V.validRecord, V.recoverableRecord, V.validEnvironment
local validRewardState, validVendorState = V.validRewardState, V.validVendorState
local validExchangeState, validDisplay, validJournal = V.validExchangeState, V.validDisplay, V.validJournal

local StoreKernel = {}

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

-- Opens saved data once. Domains receive this narrow interface; only the kernel
-- reassigns `raw`, so domains must read `kernel.raw()` at each point of use.
---@param raw any
---@param save fun(value: AzerothLedgerData)
function StoreKernel.open(raw, save)
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
    if supported and raw.environment ~= nil and not validEnvironment(raw.environment) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.rewards ~= nil and not validRewardState(raw.rewards) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.loot ~= nil and not validLootState(raw.loot) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.vendor ~= nil and not validVendorState(raw.vendor) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.exchange ~= nil and not validExchangeState(raw.exchange) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.evidence ~= nil and not validEvidence(raw.evidence) then
        damagedCount = damagedCount + 1
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
        for _, category in ipairs({ "exchange", "vendor" }) do
            local state = raw[category]
            local validState = category == "exchange" and validExchangeState or validVendorState
            for _, entry in ipairs(state and validState(state) and state.journal or {}) do
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

    if supported and raw.display ~= nil and not validDisplay(raw.display) then
        damagedCount = damagedCount + 1
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
    local vendorHealthy = readable and (raw.vendor == nil or validVendorState(raw.vendor))
    local exchangeHealthy = readable and (raw.exchange == nil or validExchangeState(raw.exchange))
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
            marker = fields.marker or raw.marker,
            environment = fields.environment or raw.environment,
            records = raw.records,
            areas = fields.areas or raw.areas,
            loot = fields.loot or raw.loot,
            rewards = fields.rewards or raw.rewards,
            vendor = fields.vendor or raw.vendor,
            exchange = fields.exchange or raw.exchange,
            evidence = fields.evidence or raw.evidence,
            retention = fields.retention or raw.retention,
            display = fields.display or raw.display,
            book = fields.book or raw.book,
            journal = journalHealthy and raw.journal or { nextSequence = 1, gains = {} },
        }
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
        for _, category in ipairs({ "exchange", "vendor" }) do
            local state = nextValue[category]
            local validState = category == "exchange" and validExchangeState or validVendorState
            if state and (fields[category] or fields.retention) and validState(state) then
                state = copyValue(state)
                nextValue[category] = state
                for _, entry in ipairs(state.journal) do
                    if not isInteger(entry.sequence) or entry.sequence < 1 then
                        sequence(entry)
                    end
                end
                trimHistory(state.journal, limits[category == "exchange" and "transfers" or "vendor"])
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
            for _, session in ipairs(nextValue.loot and nextValue.loot.sessions or {}) do
                if session.baselinePossessions and session.baselinePossessions[key] == nil then
                    session.baselinePossessions[key] = possessionsQuantity(before, session.character, session.realm)
                end
                if session.baselineGains[key] == nil then
                    session.baselineGains[key] = before and before.totalGained or 0
                    session.baselineQuantities[key] = possessionsQuantity(before, session.character, session.realm)
                end
            end
            for _, preparation in ipairs(nextValue.rewards and nextValue.rewards.preparations or {}) do
                if not preparation.baseline[key] then
                    preparation.baseline[key] = {
                        quantity = possessionsQuantity(before, preparation.character, preparation.realm),
                        gained = before and before.totalGained or 0,
                        discovery = before == nil,
                    }
                end
            end
            record.observations = compactObservations(record.observations)
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
        if not validDisplay(nextValue.display) or nextValue.display.toasts then
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

    return {
        supported = supported,
        readable = readable,
        damagedCount = damagedCount,
        vendorHealthy = vendorHealthy,
        exchangeHealthy = exchangeHealthy,
        -- Validated facts by key; callers replace entries after each save.
        valid = valid,
        recordHealthy = recordHealthy,
        raw = function()
            return raw
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
        editGainRoot = editGainRoot,
        characterGained = characterGained,
        areaQuantity = priorQuantity,
        bagQuantity = bagQuantity,
        possessionsQuantity = possessionsQuantity,
        checkedPossessions = checkedPossessions,
    }
end

addon.StoreKernel = StoreKernel
