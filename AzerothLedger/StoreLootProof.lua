local _, addon = ...

-- Late loot source proof: slot links read again after a window opened can
-- name the corpse or container behind gains the session already measured.

local V = addon.SchemaValidate
local copyValue, validLootSource, copyRecord = V.copyValue, V.validLootSource, V.copyRecord
local sameSource, canEnrichLootSource = V.sameSource, V.canEnrichLootSource
local Session = addon.StoreLootSession
local attributeLoot, lootSlots, competingLoot = Session.attributeLoot, Session.lootSlots, Session.competingLoot

local StoreLootProof = {}

-- Returns the lootSourceProof command's run function over the loot store's state.
function StoreLootProof.install(deps)
    local valid, saveFields, validRecord, lootState = deps.valid, deps.saveFields, deps.validRecord, deps.lootState
    local activeSession, award, evidenceState = deps.activeSession, deps.award, deps.evidenceState
    local reserveCandidate = deps.reserveCandidate

    ---@param window {slots: AzerothLedgerLootSlot[]} The window's slots read again later
    ---@param at integer
    ---@param actor AzerothLedgerActor
    local function lootSourceProof(window, at, actor)
        local slots = window.slots
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
        local loot = copyValue(lootState())
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

    return lootSourceProof
end

addon.StoreLootProof = StoreLootProof
