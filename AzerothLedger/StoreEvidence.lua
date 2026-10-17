local _, addon = ...

-- Unresolved evidence, correlation expiry, late gain corrections and the
-- per-character candidate limit shared by every correlating domain.

local V = addon.SchemaValidate
local gainMethods, vendorKinds, isInteger, isName = V.gainMethods, V.vendorKinds, V.isInteger, V.isName
local copyValue, validEvidence, validLootSource = V.copyValue, V.validEvidence, V.validLootSource
local validLootState, copyRecord, validPlaceKind = V.validLootState, V.copyRecord, V.validPlaceKind
local validRecord, validRewardContext, validRewardState = V.validRecord, V.validRewardContext, V.validRewardState
local sameSource, preparationLive = V.sameSource, V.preparationLive

local StoreEvidence = {}

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

-- Returns the evidence interface the correlating domains share.
function StoreEvidence.install(store, kernel)
    local valid, readable, saveFields = kernel.valid, kernel.readable, kernel.save
    local vendorHealthy, exchangeHealthy = kernel.vendorHealthy, kernel.exchangeHealthy
    local candidates = {}

    local function evidenceState()
        if kernel.raw().evidence == nil then
            return { nextID = 1, unresolved = {}, discarded = 0 }
        end
        return validEvidence(kernel.raw().evidence) and copyValue(kernel.raw().evidence) or nil
    end

    -- End correlation independently of event traffic. Completed vendor and outgoing
    -- transfer references remain available for refunds, buybacks and alt receipts.
    local function endCorrelation(at, reason)
        if not readable then
            return false
        end
        local engines = {
            loot = kernel.raw().loot and validLootState(kernel.raw().loot) and kernel.raw().loot or nil,
            rewards = kernel.raw().rewards and validRewardState(kernel.raw().rewards) and kernel.raw().rewards or nil,
            vendor = kernel.raw().vendor and vendorHealthy and kernel.raw().vendor or nil,
            exchange = kernel.raw().exchange and exchangeHealthy and kernel.raw().exchange or nil,
        }
        for index = #candidates, 1, -1 do
            if at - candidates[index].at >= 60 then
                table.remove(candidates, index)
            end
        end
        if reason ~= "reload" then
            local stale = false
            for _, name in ipairs({ "loot", "rewards", "vendor", "exchange" }) do
                local state = engines[name]
                local list = (name == "loot" or name == "rewards") and "sessions" or "actions"
                for _, entry in ipairs(state and state[list] or {}) do
                    local active = name == "loot"
                        or name == "rewards"
                        or entry.status == "pending"
                        or entry.status == "unresolved"
                    if active and at - (entry.openedAt or entry.at) >= 60 then
                        stale = true
                        break
                    end
                end
                for _, entry in ipairs(name == "rewards" and state and state.preparations or {}) do
                    if at >= entry.at and not preparationLive(entry, at) then
                        stale = true
                        break
                    end
                end
            end
            if not stale then
                return kernel.raw().evidence == nil or validEvidence(kernel.raw().evidence)
            end
        end
        local evidence = evidenceState()
        if not evidence then
            return false
        end
        local fields = { evidence = evidence }
        local changed = false
        for _, name in ipairs({ "loot", "rewards", "vendor", "exchange" }) do
            local original = engines[name]
            if type(original) == "table" then
                local state = copyValue(original)
                local list = (name == "loot" or name == "rewards") and "sessions" or "actions"
                local entries = state[list]
                if type(entries) == "table" then
                    for index = #entries, 1, -1 do
                        local entry = entries[index]
                        local openedAt = entry.openedAt or entry.at
                        local stale = reason == "reload" or (isInteger(openedAt) and at - openedAt >= 60)
                        local active = name == "loot"
                            or name == "rewards"
                            or entry.status == "pending"
                            or entry.status == "unresolved"
                        if
                            stale
                            and active
                            and isInteger(openedAt)
                            and isName(entry.character)
                            and isName(entry.realm)
                        then
                            if name == "loot" then
                                for key, slot in pairs(entry.slots or {}) do
                                    local received = entry.receipts and entry.receipts[key]
                                    local quantity = math.max(
                                        slot.limit or 0,
                                        received and received.quantity or 0,
                                        entry.credits and entry.credits[key] or 0
                                    )
                                    if quantity == 0 or quantity > (entry.awarded[key] or 0) then
                                        retain(evidence, name, reason, openedAt, entry, {
                                            key = key,
                                            slot = slot,
                                            receipt = received,
                                            measured = entry.credits[key],
                                            awarded = entry.awarded[key],
                                        })
                                    end
                                end
                            elseif name ~= "rewards" or entry.awarded < entry.quantity or not entry.confirmed then
                                retain(evidence, name, reason, openedAt, entry, entry)
                            end
                            table.remove(entries, index)
                            changed = true
                        end
                    end
                end
                if name == "rewards" then
                    for index = #(state.preparations or {}), 1, -1 do
                        local entry = state.preparations[index]
                        if reason == "reload" or (at >= entry.at and not preparationLive(entry, at)) then
                            -- Declining an offered quest is ordinary, not evidence.
                            if not entry.confirmed and entry.stage ~= "accept" then
                                retain(evidence, "quest", reason, entry.at, entry, entry)
                            end
                            table.remove(state.preparations, index)
                            changed = true
                        end
                    end
                end
                fields[name] = state
            end
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
        local state = kernel.raw().evidence
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
        local evidence = kernel.raw().evidence
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
        for _, kind in ipairs({ "loot", "rewards", "vendor", "exchange" }) do
            local state = kernel.raw()[kind]
            local healthy
            if kind == "loot" then
                healthy = state and validLootState(state)
            elseif kind == "rewards" then
                healthy = state and validRewardState(state)
            elseif kind == "vendor" then
                healthy = vendorHealthy
            else
                healthy = exchangeHealthy
            end
            if readable and state and healthy then
                local list = (kind == "loot" or kind == "rewards") and state.sessions or state.actions
                for _, entry in ipairs(list) do
                    local id = kind .. ":" .. entry.id
                    if kind == "loot" then
                        for key, slot in pairs(entry.slots) do
                            local receipt = entry.receipts[key]
                            local quantity =
                                math.max(slot.limit or 0, receipt and receipt.quantity or 0, entry.credits[key] or 0)
                            if quantity == 0 or quantity > (entry.awarded[key] or 0) then
                                emit(
                                    id .. ":" .. key,
                                    kind,
                                    "active",
                                    entry.openedAt,
                                    entry,
                                    { key = key, slot = slot, quantity = quantity > 0 and quantity or nil }
                                )
                            end
                            pause()
                        end
                    elseif kind == "rewards" then
                        if entry.awarded < entry.quantity or not entry.confirmed then
                            emit(id, kind, "active", entry.at, entry, entry)
                        end
                    elseif entry.status == "pending" or entry.status == "unresolved" then
                        local stopped = entry.status == "unresolved" and (kind == "vendor" or not entry.confirmed)
                        local reason = stopped and "stopped" or "active"
                        emit(id, kind, reason, entry.at, entry, entry)
                    end
                    pause()
                end
                for _, entry in ipairs(kind == "rewards" and state.preparations or {}) do
                    if not entry.confirmed then
                        emit("quest:" .. entry.questID .. ":" .. entry.at, "quest", "active", entry.at, entry, entry)
                    end
                    pause()
                end
            end
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

    return {
        state = evidenceState,
        retain = retain,
        endCorrelation = endCorrelation,
        reserve = reserveCandidate,
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
