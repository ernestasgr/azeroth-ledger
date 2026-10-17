local _, addon = ...

-- Unresolved evidence, correlation expiry, late gain corrections and the
-- per-character candidate limit shared by every correlating domain.

local V = addon.SchemaValidate
local gainMethods, vendorKinds, isInteger, isName = V.gainMethods, V.vendorKinds, V.isInteger, V.isName
local copyValue, validLootSource = V.copyValue, V.validLootSource
local copyRecord, validPlaceKind = V.copyRecord, V.validPlaceKind
local validRewardContext, sameSource = V.validRewardContext, V.sameSource

---@class AzerothLedgerEngine A correlating domain: loot, rewards, vendor or exchange.
---@field stale fun(at: integer): boolean Whether an active entry is at least 60 seconds old
---@field expire fun(at: integer, reason: string, retain: function): table?, boolean
---@field visit fun(emit: function, pause: function)
---@field check fun(scan: AzerothLedgerCheck): table

local StoreEvidence = {}

local function validEvidence(state)
    if
        type(state) ~= "table"
        or not isInteger(state.nextID)
        or state.nextID < 1
        or type(state.unresolved) ~= "table"
        or #state.unresolved > 2000
        or not isInteger(state.discarded)
        or state.discarded < 0
    then
        return false
    end
    if
        state.discarded > 0
        and (
            not isInteger(state.firstDiscarded)
            or not isInteger(state.lastDiscarded)
            or state.firstDiscarded < 0
            or state.lastDiscarded < state.firstDiscarded
        )
    then
        return false
    end
    local ids = {}
    for _, entry in ipairs(state.unresolved) do
        if
            type(entry) ~= "table"
            or not isInteger(entry.id)
            or entry.id < 1
            or entry.id >= state.nextID
            or ids[entry.id]
            or not isName(entry.kind)
            or not isName(entry.reason)
            or not isInteger(entry.at)
            or entry.at < 0
            or not isName(entry.character)
            or not isName(entry.realm)
            or type(entry.detail) ~= "table"
        then
            return false
        end
        ids[entry.id] = true
    end
    return true
end

---@type AzerothLedgerSlice
StoreEvidence.slice = { name = "evidence", validate = validEvidence }

-- Whether an active session or action is at least 60 seconds old.
---@param entries table[]?
---@param at integer
---@param active? fun(entry: table): boolean Every entry is active when omitted
function StoreEvidence.staleEntries(entries, at, active)
    for _, entry in ipairs(entries or {}) do
        if (not active or active(entry)) and at - (entry.openedAt or entry.at) >= 60 then
            return true
        end
    end
    return false
end

-- Removes stale active entries in place, newest first, after retaining each as
-- evidence. A reload makes every active entry stale. Returns whether any went.
---@param entries table[]?
---@param at integer
---@param reason string
---@param active? fun(entry: table): boolean Every entry is active when omitted
---@param retainEntry fun(entry: table, openedAt: integer)
function StoreEvidence.expireEntries(entries, at, reason, active, retainEntry)
    local changed = false
    if type(entries) ~= "table" then
        return changed
    end
    for index = #entries, 1, -1 do
        local entry = entries[index]
        local openedAt = entry.openedAt or entry.at
        local stale = reason == "reload" or (isInteger(openedAt) and at - openedAt >= 60)
        if
            stale
            and (not active or active(entry))
            and isInteger(openedAt)
            and isName(entry.character)
            and isName(entry.realm)
        then
            retainEntry(entry, openedAt)
            table.remove(entries, index)
            changed = true
        end
    end
    return changed
end

local function retain(state, kind, reason, at, actor, detail)
    state.unresolved[#state.unresolved + 1] = {
        id = state.nextID,
        kind = kind,
        reason = reason,
        at = at,
        character = actor.character,
        realm = actor.realm,
        detail = copyValue(detail),
    }
    state.nextID = state.nextID + 1
    if #state.unresolved > 2000 then
        local discarded = table.remove(state.unresolved, 1)
        state.discarded = state.discarded + 1
        state.firstDiscarded = math.min(state.firstDiscarded or discarded.at, discarded.at)
        state.lastDiscarded = math.max(state.lastDiscarded or discarded.at, discarded.at)
    end
end

-- Count incoming candidate signals at the public boundary, across all
-- channels for each character. Overflow is retained before it can match.
local function validCandidate(name, detail, actor)
    if name == "questPrepared" then
        return isInteger(detail) and detail > 0
    end
    if type(detail) ~= "table" then
        return false
    end
    if name == "lootOpen" then
        if
            not isInteger(detail.level)
            or type(detail.place) ~= "string"
            or not validPlaceKind(detail.placeKind)
            or type(detail.slots) ~= "table"
        then
            return false
        end
        for _, slot in ipairs(detail.slots) do
            if
                type(slot) ~= "table"
                or type(slot.key) ~= "string"
                or not validLootSource(slot.source)
                or (slot.quantity ~= nil and (not isInteger(slot.quantity) or slot.quantity < 1))
            then
                return false
            end
        end
        return true
    end
    if type(detail.key) ~= "string" or not isInteger(detail.quantity) or detail.quantity < 1 then
        return false
    end
    if name == "lootReceipt" or name == "vendorReceipt" then
        return true
    end
    if not isInteger(actor.level) or type(actor.place) ~= "string" or not validPlaceKind(actor.placeKind) then
        return false
    end
    if name == "rewardReceipt" then
        return (detail.method == "Quest" or detail.method == "Crafted")
            and validRewardContext(detail.context, detail.method)
            and (detail.preview == nil or type(detail.preview) == "boolean")
            and (
                detail.choiceGroup == nil
                or (isName(detail.choiceGroup) and detail.method == "Quest" and detail.preview == true)
            )
    end
    if
        not isInteger(detail.itemID)
        or detail.itemID < 1
        or addon.Item.key(detail.link, detail.itemID) ~= detail.key
    then
        return false
    end
    if name == "vendorAction" then
        return vendorKinds[detail.kind] == true
            and (detail.area == nil or detail.area == "bags" or detail.area == "equipped")
            and (actor.vendorName == nil or isName(actor.vendorName))
    end
    return (detail.channel == "mail" or detail.channel == "trade")
        and (detail.direction == "in" or detail.direction == "out")
        and (detail.peerName == nil or isName(detail.peerName))
        and (detail.peerRealm == nil or isName(detail.peerRealm))
end

-- Returns the evidence interface the correlating domains share. Their engines
-- are attached once every domain is installed.
function StoreEvidence.install(store, kernel, slice)
    local valid, readable, saveFields, validRecord = kernel.valid, kernel.readable, kernel.save, kernel.validRecord
    local savedState = slice.state
    local candidates = {}
    ---@type {name: string, engine: AzerothLedgerEngine}[]
    local engines = {}

    local function evidenceState()
        if savedState() == nil then
            return { nextID = 1, unresolved = {}, discarded = 0 }
        end
        return validEvidence(savedState()) and copyValue(savedState()) or nil
    end

    -- End correlation independently of event traffic. Completed vendor and outgoing
    -- transfer references remain available for refunds, buybacks and alt receipts.
    local function endCorrelation(at, reason)
        if not readable then
            return false
        end
        for index = #candidates, 1, -1 do
            if at - candidates[index].at >= 60 then
                table.remove(candidates, index)
            end
        end
        if reason ~= "reload" then
            local stale = false
            for _, entry in ipairs(engines) do
                stale = stale or entry.engine.stale(at)
            end
            if not stale then
                return savedState() == nil or validEvidence(savedState())
            end
        end
        local evidence = evidenceState()
        if not evidence then
            return false
        end
        local function retainInto(kind, ...)
            retain(evidence, kind, ...)
        end
        local fields = { evidence = evidence }
        local changed = false
        for _, entry in ipairs(engines) do
            local state, expired = entry.engine.expire(at, reason, retainInto)
            fields[entry.name] = state
            changed = changed or expired
        end
        if changed then
            saveFields(fields)
        end
        return true
    end

    function store.expireEvidence(_self, at)
        return isInteger(at) and at >= 0 and endCorrelation(at, "expired") or false
    end

    function store.unresolved(_self)
        local state = evidenceState()
        return state and state.unresolved or {}
    end

    function store.evidenceSummary(_self)
        return evidenceState() or { nextID = 1, unresolved = {}, discarded = 0 }
    end

    -- The book warning needs counts, not deep copies of up to 2,000 payloads.
    function store.evidenceStatus(_self)
        local state = savedState()
        if not state or not validEvidence(state) then
            return { count = 0, discarded = 0 }
        end
        return {
            count = #state.unresolved,
            discarded = state.discarded,
            firstDiscarded = state.firstDiscarded,
            lastDiscarded = state.lastDiscarded,
        }
    end

    -- Copy only presentation fields, one candidate at a time. Never resume,
    -- expire or settle a match from a read-only query.
    function store.visitEvidence(_self, visit, pause)
        pause = pause or function() end
        local function emit(id, kind, reason, at, actor, detail)
            local slot = type(detail.slot) == "table" and detail.slot or {}
            local quantity = detail.quantity or slot.limit
            local preparationID = kind == "quest" and detail.id or detail.questPreparationID
            visit({
                id = id,
                kind = kind,
                reason = reason,
                at = at,
                character = actor.character,
                realm = actor.realm,
                key = type(detail.key) == "string" and detail.key or nil,
                link = type(detail.link) == "string" and detail.link or nil,
                itemID = isInteger(detail.itemID) and detail.itemID > 0 and detail.itemID or nil,
                quantity = isInteger(quantity) and quantity > 0 and quantity or nil,
                action = type(detail.kind) == "string" and detail.kind or nil,
                method = (detail.method == "Quest" or detail.method == "Crafted") and detail.method or nil,
                channel = (detail.channel == "mail" or detail.channel == "trade") and detail.channel or nil,
                direction = (detail.direction == "in" or detail.direction == "out") and detail.direction or nil,
                area = type(detail.area) == "string" and detail.area or nil,
                location = type(detail.location) == "string" and detail.location or nil,
                confirmed = detail.confirmed == true,
                sourceKnown = slot.source ~= nil and validLootSource(slot.source),
                preparationID = isInteger(preparationID) and preparationID > 0 and preparationID or nil,
            })
            pause()
        end
        local evidence = savedState()
        if evidence and validEvidence(evidence) then
            for _, entry in ipairs(evidence.unresolved) do
                if entry.kind == "lootOpen" and type(entry.detail.slots) == "table" and #entry.detail.slots > 0 then
                    for index, slot in ipairs(entry.detail.slots) do
                        slot = type(slot) == "table" and slot or {}
                        emit(
                            "saved:" .. entry.id .. ":" .. index,
                            entry.kind,
                            entry.reason,
                            entry.at,
                            entry,
                            { key = slot.key, quantity = slot.quantity }
                        )
                    end
                else
                    emit("saved:" .. entry.id, entry.kind, entry.reason, entry.at, entry, entry.detail)
                end
            end
        end
        for _, entry in ipairs(engines) do
            entry.engine.visit(emit, pause)
        end
        return {
            discarded = evidence and validEvidence(evidence) and evidence.discarded or 0,
            firstDiscarded = evidence and evidence.firstDiscarded,
            lastDiscarded = evidence and evidence.lastDiscarded,
        }
    end

    function store.correctGain(_self, proof)
        if
            not readable
            or type(proof) ~= "table"
            or not isName(proof.id)
            or type(proof.key) ~= "string"
            or type(proof.gainID) ~= "string"
            or not isInteger(proof.quantity)
            or proof.quantity < 1
            or not gainMethods[proof.method]
            or (proof.source ~= nil and type(proof.source) ~= "table")
            or (proof.fromSource ~= nil and type(proof.fromSource) ~= "table")
        then
            return false
        end
        local existing = valid[proof.key]
        if
            not existing
            or not validRecord(proof.key, existing)
            or (proof.link ~= nil and addon.Item.key(proof.link, existing.itemID) ~= proof.key)
        then
            return false
        end
        local record = copyRecord(existing)
        local gain
        for _, entry in ipairs(record.gains) do
            for _, id in ipairs(entry.corrections or {}) do
                if id == proof.id then
                    return false
                end
            end
            if entry.id == proof.gainID then
                gain = entry
            end
        end
        local newLink = false
        if proof.link then
            newLink = true
            for _, storedLink in ipairs(record.links) do
                if storedLink == proof.link then
                    newLink = false
                end
            end
        end
        if
            not gain
            or gain.method ~= proof.fromMethod
            or not sameSource(gain.source, proof.fromSource)
            or proof.quantity > gain.quantity - (gain.refunded or 0)
            or (
                gain.method == proof.method
                and sameSource(gain.source, proof.source)
                and (not proof.context or (gain.context and gain.context.id == proof.context.id))
                and not newLink
            )
        then
            return false
        end
        -- A refund references a complete purchase. Never split or reclassify it.
        if gain.method == "Vendor" and (proof.method ~= "Vendor" or proof.quantity ~= gain.quantity) then
            return false
        end
        if proof.quantity < gain.quantity then
            local share = copyValue(gain)
            gain.quantity = gain.quantity - proof.quantity
            share.id = gain.id .. ":proof:" .. proof.id
            share.quantity = proof.quantity
            share.refunded = nil
            record.gains[#record.gains + 1] = share
            gain = share
        end
        gain.method = proof.method
        if proof.method ~= "Obtained" then
            gain.channel = nil
        end
        gain.source = copyValue(proof.source)
        gain.context = copyValue(proof.context)
        gain.corrections = gain.corrections or {}
        gain.corrections[#gain.corrections + 1] = proof.id
        if proof.link then
            local found = false
            for _, storedLink in ipairs(record.links) do
                if storedLink == proof.link then
                    found = true
                end
            end
            if not found then
                record.links[#record.links + 1] = proof.link
            end
        end
        if not validRecord(proof.key, record) then
            return false
        end
        local records = {}
        records[proof.key] = record
        saveFields({ records = records })
        valid[proof.key] = copyRecord(record)
        return true
    end

    local function reserveCandidate(kind, detail, at, actor, cost)
        if not endCorrelation(at, "expired") then
            return false
        end
        local count = 0
        for _, entry in ipairs(candidates) do
            if entry.character == actor.character and entry.realm == actor.realm then
                count = count + 1
            end
        end
        cost = cost or 1
        if count + cost > 256 then
            local evidence = evidenceState()
            retain(evidence, kind, "overflow", at, actor, detail)
            saveFields({ evidence = evidence })
            return false
        end
        for _ = 1, cost do
            candidates[#candidates + 1] = { at = at, character = actor.character, realm = actor.realm }
        end
        return true
    end

    -- Engines expire and list in this order, so evidence ids keep their order.
    ---@param list {name: string, engine: AzerothLedgerEngine}[]
    local function attach(list)
        for _, entry in ipairs(list) do
            engines[#engines + 1] = entry
        end
    end

    return {
        state = evidenceState,
        retain = retain,
        endCorrelation = endCorrelation,
        reserve = reserveCandidate,
        attach = attach,
    }
end

-- Count incoming candidate signals at the public boundary. Installed after every
-- domain so these wrappers enclose the domain commands, not internal calls.
function StoreEvidence.guardCandidates(store, kernel, correlation)
    local readable, saveFields = kernel.readable, kernel.save
    local evidenceState, reserveCandidate = correlation.state, correlation.reserve
    for _, name in ipairs({
        "lootOpen",
        "lootReceipt",
        "rewardReceipt",
        "questPrepared",
        "vendorAction",
        "vendorReceipt",
        "exchangeIntent",
    }) do
        local command = store[name]
        store[name] = function(self, detail, at, actor, ...)
            if name == "lootOpen" then
                actor = detail
                at = type(detail) == "table" and detail.at or nil
            end
            if
                readable
                and isInteger(at)
                and at >= 0
                and type(actor) == "table"
                and isName(actor.character)
                and isName(actor.realm)
                and validCandidate(name, detail, actor)
            then
                local payload = type(detail) == "table" and detail or { value = detail }
                local cost = name == "lootOpen" and type(payload.slots) == "table" and #payload.slots or 1
                if not reserveCandidate(name, payload, at, actor, math.max(1, cost)) then
                    return false
                end
            end
            local result = command(self, detail, at, actor, ...)
            if
                not result
                and (name == "lootReceipt" or name == "vendorReceipt")
                and readable
                and type(detail) == "table"
                and type(detail.key) == "string"
                and isInteger(detail.quantity)
                and detail.quantity > 0
                and isInteger(at)
                and at >= 0
                and type(actor) == "table"
                and isName(actor.character)
                and isName(actor.realm)
            then
                local evidence = evidenceState()
                if evidence then
                    retain(evidence, name, "unmatched", at, actor, detail)
                    saveFields({ evidence = evidence })
                end
            end
            return result
        end
    end
end

addon.StoreEvidence = StoreEvidence
