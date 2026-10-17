local _, addon = ...

-- Loot-window sessions: slot sources, personal receipts and measured awards.

local V = addon.SchemaValidate
local isInteger, isName, copyValue, validLootSource = V.isInteger, V.isName, V.copyValue, V.validLootSource
local copyRecord, validPlaceKind, validRecord = V.copyRecord, V.validPlaceKind, V.validRecord
local validRewardSession, sameSource = V.validRewardSession, V.sameSource
local canEnrichLootSource = V.canEnrichLootSource

local StoreLoot = {}

local function sessionIsLive(session, at)
    return type(session) == "table"
        and isInteger(session.openedAt)
        and isInteger(session.id)
        and isName(session.character)
        and isName(session.realm)
        and type(session.slots) == "table"
        and type(session.credits) == "table"
        and type(session.receipts) == "table"
        and type(session.awarded) == "table"
        and type(session.discoveries) == "table"
        and type(session.baselineQuantities) == "table"
        and type(session.baselineGains) == "table"
        and (session.closedAt == nil or isInteger(session.closedAt))
        and (session.endedAt == nil or isInteger(session.endedAt))
        and isInteger(at)
        and at >= session.openedAt
        and at - session.openedAt < 60
        and ((session.closedAt == nil and session.endedAt == nil) or at <= (session.closedAt or session.endedAt) + 60)
end

local function attributeLoot(session, key, record)
    local slot = session.slots[key]
    local shares = slot and slot.shares
    if not shares then
        return
    end
    local gainID = tostring(session.id) .. ":" .. key
    local gain
    local contributions, total, corrected = {}, 0, false
    for _, entry in ipairs(record.gains) do
        if entry.id == gainID or entry.id:sub(1, #gainID + 7) == gainID .. ":share:" then
            contributions[#contributions + 1] = entry
            total = total + entry.quantity
            corrected = corrected or entry.corrections ~= nil
        end
        if entry.id == gainID then
            gain = entry
        end
    end
    if #contributions > 1 and not corrected and slot.limit == session.awarded[key] and total == slot.limit then
        gain = copyValue(contributions[1])
        gain.id, gain.quantity, gain.source = gainID, total, nil
        for index = #record.gains, 1, -1 do
            local entry = record.gains[index]
            if entry.id == gainID or entry.id:sub(1, #gainID + 7) == gainID .. ":share:" then
                table.remove(record.gains, index)
            end
        end
        record.gains[#record.gains + 1] = gain
    end
    if not gain then
        for index, share in ipairs(shares) do
            for _, entry in ipairs(record.gains) do
                if
                    entry.id == gainID .. ":share:" .. index
                    and entry.quantity == share.quantity
                    and not entry.corrections
                    and share.source
                then
                    entry.source = copyValue(share.source)
                end
            end
        end
        return
    end
    if gain.corrections then
        return
    end
    -- A partial take needs no division when every possible share proves
    -- the same corpse or container. Missing or different sources still
    -- require the complete measured take below.
    local commonSource = shares[1] and shares[1].source
    for _, share in ipairs(shares) do
        if not sameSource(commonSource, share.source) then
            commonSource = nil
            break
        end
    end
    if commonSource then
        gain.source = copyValue(commonSource)
        return
    end
    if #shares == 1 then
        return
    end
    -- Only a complete, measured take of every slot proves the division.
    if slot.limit ~= session.awarded[key] or gain.quantity ~= slot.limit then
        return
    end
    local proven = 0
    local knownSource = false
    for _, share in ipairs(shares) do
        if not isInteger(share.quantity) or share.quantity < 1 then
            return
        end
        if share.source then
            knownSource = true
        end
        proven = proven + share.quantity
    end
    if proven ~= gain.quantity or not knownSource then
        return
    end
    for index, entry in ipairs(record.gains) do
        if entry == gain then
            table.remove(record.gains, index)
            break
        end
    end
    for index, share in ipairs(shares) do
        local contribution = copyValue(gain)
        contribution.id = gainID .. ":share:" .. index
        contribution.quantity = share.quantity
        contribution.source = copyValue(share.source)
        record.gains[#record.gains + 1] = contribution
    end
end

---@param entries AzerothLedgerLootSlot[]
---@return table<string, AzerothLedgerLootSessionSlot>?
local function lootSlots(entries)
    local slots = {}
    for index, entry in ipairs(entries) do
        if
            type(entry) ~= "table"
            or type(entry.key) ~= "string"
            or not validLootSource(entry.source)
            or (entry.quantity ~= nil and (not isInteger(entry.quantity) or entry.quantity < 1))
        then
            return nil
        end
        local share = {
            source = copyValue(entry.source),
            quantity = entry.quantity,
            slot = entry.slot or index,
            sourceIndex = entry.sourceIndex or 1,
        }
        local slot = slots[entry.key]
        if slot then
            slot.shares[#slot.shares + 1] = share
            slot.source = nil
            slot.limit = slot.limit and entry.quantity and slot.limit + entry.quantity or nil
        else
            slots[entry.key] = { source = copyValue(entry.source), limit = entry.quantity, shares = { share } }
        end
    end
    return slots
end

local function competingLoot(session, key, actor)
    local slot = session.slots[key]
    return session.character == actor.character
        and session.realm == actor.realm
        and slot ~= nil
        and (not slot.limit or (session.awarded[key] or 0) < slot.limit)
end

-- Returns the session hooks a possessions scan settles.
function StoreLoot.install(store, kernel, correlation)
    local valid, readable, saveFields, gainRecord = kernel.valid, kernel.readable, kernel.save, kernel.gain
    local heldKeys, possessionsQuantity = kernel.heldKeys, kernel.possessionsQuantity
    local evidenceState, reserveCandidate = correlation.state, correlation.reserve

    local function activeSession(at, pending)
        local loot = pending or kernel.raw().loot
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
        local loot = kernel.raw().loot
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
        local rewards = type(kernel.raw().rewards) == "table" and kernel.raw().rewards.sessions or nil
        local latest
        for _, reward in ipairs(type(rewards) == "table" and rewards or {}) do
            if
                validRewardSession(reward)
                and reward.confirmed
                and reward.key == key
                and reward.character == actor.character
                and reward.realm == actor.realm
                and at >= reward.at
                and at - reward.at < 60
            then
                if not latest or reward.at > latest.at then
                    latest = reward
                end
            end
        end
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
        record = gainRecord(record, {
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
        }, session.discoveries[key] and { since = session.openedAt }, { full = not incremental })
        session.awarded[key] = target
        attributeLoot(session, key, record)
        records[key] = record
    end

    ---@param context AzerothLedgerLootContext
    function store.lootOpen(_self, context)
        if
            not readable
            or type(context) ~= "table"
            or not isName(context.character)
            or not isName(context.realm)
            or not isInteger(context.at)
            or not isInteger(context.level)
            or type(context.place) ~= "string"
            or not validPlaceKind(context.placeKind)
            or type(context.slots) ~= "table"
        then
            return false
        end
        local baseline = store:area(context.character, context.realm, "bags")
        if not baseline or not baseline.complete then
            return false
        end
        local slots = lootSlots(context.slots)
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
        local loot = type(kernel.raw().loot) == "table" and kernel.raw().loot or nil
        local previousID = loot and loot.nextID or nil
        local nextID = (isInteger(previousID) and previousID or 0) + 1
        local sessions = {}
        for _, session in ipairs(loot and loot.sessions or {}) do
            if sessionIsLive(session, context.at) then
                if not session.endedAt then
                    session.endedAt = context.at
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
            openedAt = context.at,
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

    function store.lootSourceProof(_self, slots, at, actor)
        if
            not readable
            or type(slots) ~= "table"
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        for _, proof in ipairs(slots) do
            if
                type(proof) ~= "table"
                or type(proof.key) ~= "string"
                or not validLootSource(proof.source)
                or (proof.quantity ~= nil and (not isInteger(proof.quantity) or proof.quantity < 1))
            then
                return false
            end
        end
        if not store:expireEvidence(at) then
            return false
        end
        local current = activeSession(at)
        if not current or current.character ~= actor.character or current.realm ~= actor.realm then
            return false
        end
        local session = copyValue(current)
        local keys = {}
        local additions = {}
        -- Loot slot links can become readable after LOOT_CLOSED. activeSession
        -- bounds this late proof to the same recent, current actor session.
        for index, proof in ipairs(slots) do
            local existing = session.slots[proof.key]
            local captured = existing ~= nil and existing.shares == nil
            for _, share in ipairs(existing and existing.shares or {}) do
                if share.slot == (proof.slot or index) then
                    captured = true
                    break
                end
            end
            if not captured then
                local addition = copyValue(proof)
                addition.slot = proof.slot or index
                additions[#additions + 1] = addition
            end
        end
        local newSlots = lootSlots(additions) or {}
        if #additions > 0 then
            if not reserveCandidate("lootOpen", { slots = additions }, at, actor, #additions) then
                return false
            end
            for key, slot in pairs(newSlots) do
                local existing = session.slots[key]
                if existing and existing.shares then
                    for _, share in ipairs(slot.shares or {}) do
                        existing.shares[#existing.shares + 1] = share
                    end
                    existing.limit = existing.limit and slot.limit and existing.limit + slot.limit or nil
                    existing.source = nil
                else
                    session.slots[key] = slot
                end
                session.baselineGains[key] = session.baselineGains[key] or (valid[key] and valid[key].totalGained or 0)
                keys[key] = true
            end
        end
        for key, incoming in pairs(lootSlots(slots) or {}) do
            local slot = session.slots[key]
            local gainID = tostring(session.id) .. ":" .. key
            local corrected = false
            for _, entry in ipairs(valid[key] and valid[key].gains or {}) do
                if
                    (entry.id == gainID or entry.id:sub(1, #gainID + 7) == gainID .. ":share:")
                    and entry.corrections
                then
                    corrected = true
                end
            end
            if slot and slot.shares and not corrected then
                for index = #slot.shares, 1, -1 do
                    local share = slot.shares[index]
                    if not share.source and share.quantity then
                        local captured, quantity, known = 0, 0, false
                        local replacement = {}
                        for _, existing in ipairs(slot.shares) do
                            if existing.slot == share.slot then
                                captured = captured + 1
                            end
                        end
                        for _, proof in ipairs(incoming.shares or {}) do
                            if proof.slot == share.slot then
                                replacement[#replacement + 1] = proof
                                quantity = quantity + (proof.quantity or 0)
                                known = known or proof.source ~= nil
                            end
                        end
                        if captured == 1 and #replacement > 1 and known and quantity == share.quantity then
                            table.remove(slot.shares, index)
                            for replacementIndex = #replacement, 1, -1 do
                                table.insert(slot.shares, index, copyValue(replacement[replacementIndex]))
                            end
                            slot.source = nil
                            keys[key] = true
                        end
                    end
                end
            end
        end
        for index, proof in ipairs(slots) do
            if type(proof) ~= "table" or type(proof.key) ~= "string" or not validLootSource(proof.source) then
                return false
            end
            local slot = session.slots[proof.key]
            for _, share in ipairs(slot and slot.shares or {}) do
                if
                    share.slot == (proof.slot or index)
                    and share.sourceIndex == (proof.sourceIndex or 1)
                    and share.quantity == proof.quantity
                    and proof.source
                    and canEnrichLootSource(share.source, proof.source)
                    and not sameSource(share.source, proof.source)
                then
                    share.source = copyValue(proof.source)
                    if #slot.shares == 1 then
                        slot.source = copyValue(proof.source)
                    end
                    keys[proof.key] = true
                end
            end
        end
        if not next(keys) then
            return false
        end
        local loot = copyValue(kernel.raw().loot)
        for index, entry in ipairs(loot.sessions) do
            if entry.id == session.id then
                loot.sessions[index] = session
            else
                for key in pairs(newSlots) do
                    if competingLoot(entry, key, actor) then
                        -- An overlapping session cannot prove either source.
                        entry.slots[key].source, entry.slots[key].shares = nil, nil
                        session.slots[key].source, session.slots[key].shares = nil, nil
                    end
                end
            end
        end
        local records = {}
        for key in pairs(keys) do
            if valid[key] then
                local record = copyRecord(valid[key])
                local previous = current.slots[key]
                local gainID = tostring(session.id) .. ":" .. key
                for _, entry in ipairs(record.gains) do
                    if
                        entry.id:sub(1, #gainID + 7) == gainID .. ":share:"
                        and entry.source
                        and not entry.corrections
                    then
                        local previousIndex = tonumber(entry.id:sub(#gainID + 8))
                        local share = previous and previous.shares and previous.shares[previousIndex]
                        for nextIndex, proof in ipairs(session.slots[key].shares or {}) do
                            if
                                share
                                and proof.slot == share.slot
                                and proof.sourceIndex == share.sourceIndex
                                and proof.quantity == share.quantity
                                and sameSource(proof.source, share.source)
                            then
                                entry.id = gainID .. ":share:" .. nextIndex
                                break
                            end
                        end
                    end
                end
                if newSlots[key] and previous and previous.shares and #previous.shares == 1 then
                    for _, entry in ipairs(record.gains) do
                        if entry.id == gainID and entry.source and not entry.corrections then
                            -- Keep already proven units separate from later ambiguous shares.
                            entry.id = gainID .. ":share:1"
                        end
                    end
                end
                attributeLoot(session, key, record)
                records[key] = record
                award(session, key, records, at)
                if not validRecord(key, records[key]) then
                    return false
                end
            end
        end
        local evidence = evidenceState()
        if not evidence then
            return false
        end
        for index = #evidence.unresolved, 1, -1 do
            local entry = evidence.unresolved[index]
            if
                entry.kind == "lootReceipt"
                and entry.reason == "unmatched"
                and entry.character == session.character
                and entry.realm == session.realm
                and entry.at >= session.openedAt
                and entry.at <= at
                and keys[entry.detail.key]
                and session.receipts[entry.detail.key]
            then
                table.remove(evidence.unresolved, index)
            end
        end
        saveFields({ loot = loot, records = records, evidence = evidence })
        for key in pairs(keys) do
            if records[key] then
                valid[key] = copyRecord(records[key])
            end
        end
        return true
    end

    ---@param receipt AzerothLedgerLootClaim
    ---@param at integer
    ---@param actor AzerothLedgerActor
    function store.lootReceipt(_self, receipt, at, actor)
        local session = type(receipt) == "table" and type(actor) == "table" and receiptSession(receipt.key, at, actor)
            or nil
        if
            not readable
            or type(receipt) ~= "table"
            or type(receipt.key) ~= "string"
            or not isInteger(receipt.quantity)
            or receipt.quantity < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        local handled, preferred = lootRewardSession(receipt.key, at, actor)
        if handled then
            return true
        end
        session = preferred or session
        local pendingLoot = copyValue(kernel.raw().loot)
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

    function store.lootClose(_self, at)
        local session = activeSession(at)
        if not readable or not session then
            return false
        end
        if not session.closedAt then
            session.closedAt = at
            saveFields({})
        end
        return true
    end

    return { activeSession = activeSession, award = award }
end

addon.StoreLoot = StoreLoot
