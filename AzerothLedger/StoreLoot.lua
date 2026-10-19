local _, addon = ...

-- Loot-window sessions: slot sources, personal receipts and measured awards.

local V = addon.SchemaValidate
local isInteger, copyValue, validLootSource = V.isInteger, V.copyValue, V.validLootSource
local copyRecord, validGainActor = V.copyRecord, V.validGainActor
local Evidence = addon.StoreEvidence

local StoreLoot = {}
local Session = addon.StoreLootSession
local validLootState, sessionIsLive, attributeLoot =
    Session.validLootState, Session.sessionIsLive, Session.attributeLoot
local lootSlots, unsettledSlot, competingLoot = Session.lootSlots, Session.unsettledSlot, Session.competingLoot

---@type AzerothLedgerSlice
StoreLoot.slice = {
    name = "loot",
    validate = validLootState,
    -- Capture previously unheld items lazily before their first change during
    -- an open loot session. Late item identification keeps the pre-loot totals.
    beforeChange = function(state, key, possessions, before)
        for _, session in ipairs(state and state.sessions or {}) do
            if session.baselinePossessions and session.baselinePossessions[key] == nil then
                session.baselinePossessions[key] = possessions(session.character, session.realm)
            end
            if session.baselineGains[key] == nil then
                session.baselineGains[key] = before and before.totalGained or 0
                session.baselineQuantities[key] = possessions(session.character, session.realm)
            end
        end
    end,
}

-- Returns the correlation engine a possessions check and evidence expiry use.
---@param rewards {confirmed: fun(key: string, at: integer, actor: table): table?}
function StoreLoot.install(store, kernel, slice, correlation, rewards)
    local valid, readable, saveFields, recordGain = kernel.valid, kernel.readable, kernel.save, kernel.recordGain
    local heldKeys, possessionsQuantity = kernel.heldKeys, kernel.possessionsQuantity
    local checkedPossessions, validRecord, lootState = kernel.checkedPossessions, kernel.validRecord, slice.state
    local evidenceState, reserveCandidate = correlation.state, correlation.reserve

    local function activeSession(at, pending)
        local loot = pending or lootState()
        local sessions = type(loot) == "table" and loot.sessions or nil
        if type(sessions) == "table" then
            for index = #sessions, 1, -1 do
                local session = sessions[index]
                if sessionIsLive(session, at) and (not session.endedAt or at < session.endedAt) then
                    return session
                end
            end
        end
        return nil
    end

    local function receiptSession(key, at, actor)
        local loot = lootState()
        local sessions = type(loot) == "table" and loot.sessions or nil
        if type(sessions) ~= "table" then
            return nil
        end
        local latest
        for _, session in ipairs(sessions) do
            if
                sessionIsLive(session, at)
                and session.character == actor.character
                and session.realm == actor.realm
                and type(session.slots[key]) == "table"
            then
                latest = session
                local credit = isInteger(session.credits[key]) and session.credits[key] or 0
                local awarded = isInteger(session.awarded[key]) and session.awarded[key] or 0
                local limit = session.slots[key].limit
                local capacity = math.min(credit, isInteger(limit) and limit or math.huge)
                if capacity > awarded then
                    return session
                end
            end
        end
        return latest
    end

    -- Craft/quest receipts can share the chat channel with loot. A newer,
    -- item-specific loot cycle is required to override a confirmed reward.
    local function lootRewardSession(key, at, actor, context)
        local latest = rewards.confirmed(key, at, actor)
        if not latest then
            return false
        end
        local current = context or activeSession(at)
        if
            not current
            or current.openedAt <= latest.at
            or type(current.slots[key]) ~= "table"
            or current.character ~= actor.character
            or current.realm ~= actor.realm
        then
            return true
        end
        return false, current
    end

    -- A late source proof edits gain shares before awarding, so it passes no
    -- `incremental` and the kernel copies the whole record.
    local function award(session, key, records, at, incremental)
        if session.baselineEquipmentUncertain then
            return
        end
        local receipt = session.receipts[key]
        local record = records[key] or valid[key]
        if type(receipt) ~= "table" or not isInteger(receipt.quantity) or not isInteger(receipt.at) or not record then
            return
        end
        local awarded = isInteger(session.awarded[key]) and session.awarded[key] or 0
        local credit = isInteger(session.credits[key]) and session.credits[key] or 0
        local slot = session.slots[key]
        if type(slot) ~= "table" then
            return
        end
        if lootRewardSession(key, at or receipt.at, session, session) then
            return
        end
        local limit = slot.limit
        local target = math.min(credit, receipt.quantity, isInteger(limit) and limit or math.huge)
        local baselineGained = session.baselineGains[key]
        if not isInteger(baselineGained) then
            return
        end
        local otherGains = math.max(0, record.totalGained - baselineGained - awarded)
        target = math.min(target, math.max(0, credit - otherGains))
        local quantity = target - awarded
        if quantity <= 0 then
            return
        end
        record = recordGain(record, {
            id = tostring(session.id) .. ":" .. key,
            at = receipt.at,
            openedAt = session.openedAt,
            baselinePossessionsComplete = session.baselinePossessions ~= nil,
            quantity = quantity,
            character = session.character,
            realm = session.realm,
            level = session.level,
            place = session.place,
            placeKind = session.placeKind,
            method = "Looted",
            source = type(session.slots[key]) == "table" and session.slots[key].source or nil,
        }, { discovery = session.discoveries[key] == true, since = session.openedAt, full = not incremental })
        session.awarded[key] = target
        attributeLoot(session, key, record)
        records[key] = record
    end

    ---@param window {slots: AzerothLedgerLootSlot[]}
    ---@param at integer
    ---@param context AzerothLedgerGainActor
    local function lootOpen(window, at, context)
        local baseline = store:area(context.character, context.realm, "bags")
        if not baseline or not baseline.complete then
            return false
        end
        local slots = lootSlots(window.slots)
        if not slots then
            return false
        end
        local baselineQuantities = {}
        local equipped = store:area(context.character, context.realm, "equipped")
        local baselinePossessions = equipped and equipped.complete and equipped.seenAt == baseline.seenAt and {} or nil
        local baselineGains = {}
        -- Even an incomparable gear observation proves previously owned units.
        -- Preserve them in the bag threshold without allowing gear-only credit.
        for _, area in ipairs({ "bags", "equipped" }) do
            for key in pairs(heldKeys(context.character, context.realm, area)) do
                local record = valid[key]
                baselineQuantities[key] = possessionsQuantity(record, context.character, context.realm)
                baselineGains[key] = record.totalGained
                if baselinePossessions then
                    baselinePossessions[key] = baselineQuantities[key]
                end
            end
        end
        for key in pairs(slots) do
            baselineGains[key] = baselineGains[key] or (valid[key] and valid[key].totalGained or 0)
        end
        local loot = type(lootState()) == "table" and lootState() or nil
        local previousID = loot and loot.nextID or nil
        local nextID = (isInteger(previousID) and previousID or 0) + 1
        local sessions = {}
        for _, session in ipairs(loot and loot.sessions or {}) do
            if sessionIsLive(session, at) then
                if not session.endedAt then
                    session.endedAt = at
                end
                for key, slot in pairs(slots) do
                    if competingLoot(session, key, context) then
                        slot.source = nil
                        slot.shares = nil
                        session.slots[key].source = nil
                        session.slots[key].shares = nil
                    end
                end
                sessions[#sessions + 1] = session
            end
        end
        sessions[#sessions + 1] = {
            id = nextID,
            openedAt = at,
            character = context.character,
            realm = context.realm,
            level = context.level,
            place = context.place,
            placeKind = context.placeKind,
            slots = slots,
            credits = {},
            baselineQuantities = baselineQuantities,
            baselinePossessions = baselinePossessions,
            baselineEquipmentUncertain = equipped and not baselinePossessions or nil,
            baselineGains = baselineGains,
            receipts = {},
            awarded = {},
            discoveries = {},
        }
        saveFields({
            loot = {
                nextID = nextID,
                sessions = sessions,
            },
        })
        return true
    end

    local lootSourceProof = addon.StoreLootProof.install({
        valid = valid,
        saveFields = saveFields,
        validRecord = validRecord,
        lootState = lootState,
        activeSession = activeSession,
        award = award,
        evidenceState = evidenceState,
        reserveCandidate = reserveCandidate,
    })

    ---@param receipt AzerothLedgerLootClaim
    ---@param at integer
    ---@param actor AzerothLedgerActor
    local function lootReceipt(receipt, at, actor)
        local session = receiptSession(receipt.key, at, actor)
        local handled, preferred = lootRewardSession(receipt.key, at, actor)
        if handled then
            return true
        end
        session = preferred or session
        local pendingLoot = copyValue(lootState())
        local selectedID = session and session.id
        session = nil
        for _, entry in ipairs(pendingLoot and pendingLoot.sessions or {}) do
            if entry.id == selectedID then
                session = entry
                break
            end
        end
        local current = activeSession(at, pendingLoot)
        if
            session
            and current
            and not current.closedAt
            and current.id ~= session.id
            and current.character == actor.character
            and current.realm == actor.realm
            and not current.slots[receipt.key]
        then
            local credit = session.credits[receipt.key] or 0
            local limit = session.slots[receipt.key].limit or math.huge
            if math.min(credit, limit) <= (session.awarded[receipt.key] or 0) then
                session = nil
            end
        end
        if not session then
            local pending = activeSession(at, pendingLoot)
            if
                pending
                and not pending.closedAt
                and pending.character == actor.character
                and pending.realm == actor.realm
            then
                -- A personal receipt can precede its readable slot. It remains
                -- unresolved until that same live cycle proves the item.
                local existing = pending.receipts[receipt.key]
                pending.receipts[receipt.key] = {
                    quantity = (existing and existing.quantity or 0) + receipt.quantity,
                    at = existing and existing.at or at,
                }
                saveFields({ loot = pendingLoot })
            end
            return false
        end
        if type(session.slots[receipt.key]) ~= "table" then
            return false
        end
        local existing = session.receipts[receipt.key]
        session.receipts[receipt.key] = {
            quantity = (existing and existing.quantity or 0) + receipt.quantity,
            at = existing and existing.at or at,
        }
        local nextRecords = {}
        award(session, receipt.key, nextRecords, at, true)
        saveFields({ loot = pendingLoot, records = nextRecords })
        if nextRecords[receipt.key] then
            valid[receipt.key] = copyRecord(nextRecords[receipt.key], true)
        end
        return true
    end

    local function lootClose(_, at)
        local session = activeSession(at)
        if not session then
            return false
        end
        if not session.closedAt then
            session.closedAt = at
            saveFields({})
        end
        return true
    end

    local function healthyState()
        local state = lootState()
        return state and validLootState(state) and state or nil
    end

    local function stale(at)
        local state = healthyState()
        return Evidence.staleEntries(state and state.sessions, at)
    end

    local function expire(at, reason, retain)
        local original = healthyState()
        if type(original) ~= "table" then
            return nil, false
        end
        local state = copyValue(original)
        local changed = Evidence.expireEntries(state.sessions, at, reason, nil, function(entry, openedAt)
            for key, slot in pairs(entry.slots or {}) do
                local quantity, received = unsettledSlot(entry, key, slot)
                if quantity then
                    retain("loot", reason, openedAt, entry, {
                        key = key,
                        slot = slot,
                        receipt = received,
                        measured = entry.credits[key],
                        awarded = entry.awarded[key],
                    })
                end
            end
        end)
        return state, changed
    end

    local function visit(emit, pause)
        local state = healthyState()
        if not readable or not state then
            return
        end
        for _, entry in ipairs(state.sessions) do
            local id = "loot:" .. entry.id
            for key, slot in pairs(entry.slots) do
                local quantity = unsettledSlot(entry, key, slot)
                if quantity then
                    emit(
                        id .. ":" .. key,
                        "loot",
                        "active",
                        entry.openedAt,
                        entry,
                        { key = key, slot = slot, quantity = quantity > 0 and quantity or nil }
                    )
                end
                pause()
            end
            pause()
        end
    end

    -- The live sessions a check measures, oldest first: the active one, and
    -- any ended earlier whose receipts arrived before their items reached
    -- the bags. Fast looting opens the next corpse before that happens.
    local function measuredSessions(pending, at, character, realm)
        local active = activeSession(at, pending)
        local result = {}
        for _, session in ipairs(pending and pending.sessions or {}) do
            if
                session.character == character
                and session.realm == realm
                and sessionIsLive(session, at)
                and (session == active or (session.endedAt and next(session.receipts)))
            then
                result[#result + 1] = session
            end
        end
        return result
    end

    -- Measures the live loot sessions against one possessions check.
    ---@param scan AzerothLedgerCheck
    local function check(scan)
        local snapshot, oldScope = scan.snapshot, scan.oldScope
        local pending = healthyState() and copyValue(lootState()) or nil
        local sessions = (snapshot.area == "bags" or snapshot.area == "equipped")
                and measuredSessions(pending, snapshot.seenAt, snapshot.character, snapshot.realm)
            or {}
        local handler = {}
        function handler.commit(fields)
            fields.loot = pending
        end
        if #sessions == 0 then
            return handler
        end
        local measured = snapshot.area == "bags"
            and snapshot.complete
            and type(oldScope) == "table"
            and oldScope.complete
            and not scan.unresolvedIdentity
        function handler.item(key, group, known)
            for _, session in ipairs(sessions) do
                if session.baselinePossessions and not known then
                    session.discoveries[key] = true
                end
                if measured and not session.baselineEquipmentUncertain then
                    -- Bags alone prove a lower bound when they exceed all pre-loot
                    -- possessions, even if every previously equipped unit moved in.
                    local baselineQuantity = session.baselinePossessions and (session.baselinePossessions[key] or 0)
                        or session.baselineQuantities[key]
                        or 0
                    local increase = group.quantity - baselineQuantity
                    if increase > 0 then
                        local credit = isInteger(session.credits[key]) and session.credits[key] or 0
                        session.credits[key] = math.max(credit, increase)
                        if not valid[key] then
                            session.discoveries[key] = true
                        end
                    end
                end
            end
        end
        function handler.record(key, _group, record, seen, known)
            for _, session in ipairs(sessions) do
                if session.discoveries[key] and not known then
                    local gainID = tostring(session.id) .. ":" .. key
                    for _, gain in ipairs(record.gains) do
                        if gain.id == gainID then
                            local firstSeenUnits = seen and seen.firstSeenUnits
                            if firstSeenUnits ~= nil then
                                seen.firstSeenUnits = math.max(0, firstSeenUnits - gain.quantity + (gain.refunded or 0))
                            end
                            break
                        end
                    end
                end
                if snapshot.area == "bags" and snapshot.complete then
                    award(session, key, scan.records, snapshot.seenAt, true)
                end
            end
        end
        -- The paired check follows the bag commit. Measure the whole
        -- possession change so equipping cannot hide or invent a gain.
        function handler.finish()
            if not scan.paired then
                return
            end
            for _, session in ipairs(sessions) do
                if session.baselinePossessions then
                    for key in pairs(scan.pairedKeys()) do
                        local record = scan.records[key] or valid[key]
                        local gear = scan.grouped[key]
                        local quantity = checkedPossessions(record, snapshot.character, snapshot.realm, gear)
                        local increase = quantity - (session.baselinePossessions[key] or 0)
                        session.credits[key] = math.max(session.credits[key] or 0, increase)
                        award(session, key, scan.records, snapshot.seenAt, true)
                    end
                end
            end
        end
        return handler
    end

    -- Each slot names an item and, when readable, its source.
    local function validSlots(window)
        if type(window) ~= "table" or type(window.slots) ~= "table" then
            return false
        end
        for _, slot in ipairs(window.slots) do
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

    return {
        engine = { stale = stale, expire = expire, visit = visit, check = check },
        ---@type table<string, AzerothLedgerCommand>
        commands = {
            -- A loot window takes one candidate per readable slot.
            lootOpen = {
                valid = function(window, actor)
                    return validSlots(window) and validGainActor(actor)
                end,
                run = lootOpen,
                cost = function(window)
                    return #window.slots
                end,
            },
            lootSourceProof = { valid = validSlots, run = lootSourceProof },
            lootReceipt = { valid = Evidence.validReceipt, run = lootReceipt, cost = 1, unmatched = true },
            lootClose = {
                valid = function()
                    return true
                end,
                run = lootClose,
            },
        },
    }
end

addon.StoreLoot = StoreLoot
