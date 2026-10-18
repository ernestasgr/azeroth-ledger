local _, addon = ...

-- Pure gain arithmetic the kernel applies to copies of records: tooltip facts,
-- gain-list plans, refunds and the quantities a character held.

local V = addon.SchemaValidate
local areaKey = V.areaKey
local copyValue = V.copyValue
local copyRecord = V.copyRecord

local StoreGainMath = {}

local function changeTooltip(facts, gain, direction)
    local actor = areaKey(gain.character, gain.realm, "")
    facts.gained[actor] = (facts.gained[actor] or 0) + direction * (gain.quantity - (gain.refunded or 0))
    facts.methods[gain.method] = (facts.methods[gain.method] or 0) + direction
    facts.count = facts.count + direction
    local quantity = gain.quantity - (gain.refunded or 0)
    if quantity <= 0 then
        return
    end
    local identity, neutral, name = addon.LastSeen.sourceIdentity(gain)
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
-- `roots` is the item's saved gains by acquisition root.
local function derivedGained(before, record, roots)
    local total = before and before.totalGained or 0
    if record.baseGains then
        for root, entries in pairs(record.gainEdits) do
            total = total + netGained(entries) - netGained(roots and roots[root])
        end
    elseif not before or record.gains ~= before.gains then
        total = total + netGained(record.gains) - netGained(before and before.gains)
    end
    return total
end

-- How an edited record's gain groups replace, remove and append saved gains.
-- `positions` maps each saved gain id to its index in the saved list.
local function gainPlan(record, roots, positions)
    local plan = {
        replacements = {},
        removed = {},
        appended = {},
        edits = record.gainEdits,
        base = record.baseGains,
        suffix = #record.baseGains + 1,
    }
    for root, entries in pairs(record.gainEdits) do
        local old = roots and roots[root] or {}
        for index, saved in ipairs(old) do
            local position = positions[saved.id]
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

StoreGainMath.changeTooltip = changeTooltip
StoreGainMath.emptyTooltip = emptyTooltip
StoreGainMath.applyGainPlan = applyGainPlan
StoreGainMath.undoGainPlan = undoGainPlan
StoreGainMath.priorQuantity = priorQuantity
StoreGainMath.possessionsQuantity = possessionsQuantity
StoreGainMath.bagQuantity = bagQuantity
StoreGainMath.checkedPossessions = checkedPossessions
StoreGainMath.firstFound = firstFound
StoreGainMath.recordRefund = recordRefund
StoreGainMath.netGained = netGained
StoreGainMath.derivedGained = derivedGained
StoreGainMath.gainPlan = gainPlan

addon.StoreGainMath = StoreGainMath
