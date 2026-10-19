local _, addon = ...

-- Loot session state the loot store shares: validation, liveness, slot
-- shapes, and how a measured gain divides among its sources.

local V = addon.SchemaValidate
local isInteger, isName, copyValue, validLootSource = V.isInteger, V.isName, V.copyValue, V.validLootSource
local sameSource = V.sameSource

local StoreLootSession = {}

local function validLootState(state)
    if type(state) ~= "table" or not isInteger(state.nextID) or state.nextID < 0 or type(state.sessions) ~= "table" then
        return false
    end
    for _, session in ipairs(state.sessions) do
        if
            type(session) ~= "table"
            or not isInteger(session.id)
            or not isInteger(session.openedAt)
            or session.openedAt < 0
            or not isName(session.character)
            or not isName(session.realm)
            or not isInteger(session.level)
            or type(session.place) ~= "string"
            or type(session.slots) ~= "table"
            or type(session.receipts) ~= "table"
            or type(session.discoveries) ~= "table"
            or (session.baselineEquipmentUncertain ~= nil and type(session.baselineEquipmentUncertain) ~= "boolean")
            or (session.closedAt ~= nil and not isInteger(session.closedAt))
            or (session.endedAt ~= nil and not isInteger(session.endedAt))
        then
            return false
        end
        for _, name in ipairs({ "credits", "awarded", "baselineQuantities", "baselineGains" }) do
            if type(session[name]) ~= "table" then
                return false
            end
            for key, quantity in pairs(session[name]) do
                if type(key) ~= "string" or not isInteger(quantity) or quantity < 0 then
                    return false
                end
            end
        end
        if session.baselinePossessions ~= nil then
            if type(session.baselinePossessions) ~= "table" then
                return false
            end
            for key, quantity in pairs(session.baselinePossessions) do
                if type(key) ~= "string" or not isInteger(quantity) or quantity < 0 then
                    return false
                end
            end
        end
        for key, slot in pairs(session.slots) do
            if
                type(key) ~= "string"
                or type(slot) ~= "table"
                or not validLootSource(slot.source)
                or (slot.limit ~= nil and (not isInteger(slot.limit) or slot.limit < 1))
            then
                return false
            end
            if slot.shares ~= nil then
                if type(slot.shares) ~= "table" then
                    return false
                end
                for _, share in ipairs(slot.shares) do
                    if
                        type(share) ~= "table"
                        or not validLootSource(share.source)
                        or (share.quantity ~= nil and (not isInteger(share.quantity) or share.quantity < 1))
                    then
                        return false
                    end
                end
            end
        end
        for key, receipt in pairs(session.receipts) do
            if
                type(key) ~= "string"
                or type(receipt) ~= "table"
                or not isInteger(receipt.at)
                or not isInteger(receipt.quantity)
                or receipt.quantity < 1
            then
                return false
            end
        end
    end
    return true
end

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

-- What a loot slot may still award (its limit, receipt or measured credit,
-- whichever is largest) and its receipt, when the slot is not fully awarded.
-- A slot with nothing measured yet counts as unsettled with quantity zero.
local function unsettledSlot(session, key, slot)
    local receipt = session.receipts and session.receipts[key]
    local credit = session.credits and session.credits[key] or 0
    local quantity = math.max(slot.limit or 0, receipt and receipt.quantity or 0, credit)
    if quantity == 0 or quantity > (session.awarded[key] or 0) then
        return quantity, receipt
    end
    return nil
end

local function competingLoot(session, key, actor)
    local slot = session.slots[key]
    return session.character == actor.character
        and session.realm == actor.realm
        and slot ~= nil
        and (not slot.limit or (session.awarded[key] or 0) < slot.limit)
end

StoreLootSession.validLootState = validLootState
StoreLootSession.sessionIsLive = sessionIsLive
StoreLootSession.attributeLoot = attributeLoot
StoreLootSession.lootSlots = lootSlots
StoreLootSession.unsettledSlot = unsettledSlot
StoreLootSession.competingLoot = competingLoot

addon.StoreLootSession = StoreLootSession
