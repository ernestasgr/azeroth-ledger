local _, addon = ...

-- The saved reward state: quest preparations and reward sessions, the
-- receipts that open them, and when a choosable reward is proven chosen.

local V = addon.SchemaValidate
local isInteger, isName, validPlaceKind = V.isInteger, V.isName, V.validPlaceKind
local validGainActor = V.validGainActor
local validRewardContext = V.validRewardContext
local Evidence = addon.StoreEvidence

local StoreRewardState = {}

-- Obtained is an item the client says it handed you with no quest or recipe:
-- an NPC gift, or an item created by using another item.
local rewardMethods = { Quest = true, Crafted = true, Obtained = true }

local function validRewardSession(session)
    return type(session) == "table"
        and isInteger(session.id)
        and session.id > 0
        and type(session.key) == "string"
        and rewardMethods[session.method]
        and validRewardContext(session.context, session.method)
        and (session.method ~= "Obtained" or session.context == nil)
        and isName(session.character)
        and isName(session.realm)
        and isInteger(session.level)
        and type(session.place) == "string"
        and isInteger(session.at)
        and isInteger(session.baseline)
        and session.baseline >= 0
        and isInteger(session.baselineGained)
        and session.baselineGained >= 0
        and isInteger(session.quantity)
        and session.quantity > 0
        and isInteger(session.awarded)
        and session.awarded >= 0
        and session.awarded <= session.quantity
        and type(session.discovery) == "boolean"
        and type(session.confirmed) == "boolean"
        and (session.choiceGroup == nil or (type(session.choiceGroup) == "string" and session.choiceGroup ~= ""))
        and (session.specific == nil or type(session.specific) == "boolean")
        and (session.ambiguous == nil or type(session.ambiguous) == "boolean")
        and (
            session.questPreparationID == nil
            or (isInteger(session.questPreparationID) and session.questPreparationID > 0)
        )
end

-- A turn-in preparation lasts 60 seconds. An accept preparation waits up to
-- ten minutes for QUEST_ACCEPTED, then 60 seconds for the handed-over items.
local function preparationLive(preparation, at)
    if preparation.stage == "accept" then
        if isInteger(preparation.acceptedAt) then
            return at >= preparation.acceptedAt and at - preparation.acceptedAt < 60
        end
        return at >= preparation.at and at - preparation.at < 600
    end
    return at >= preparation.at and at - preparation.at < 60
end

local function validRewardState(rewards)
    if
        type(rewards) ~= "table"
        or not isInteger(rewards.nextID)
        or type(rewards.sessions) ~= "table"
        or (rewards.preparations ~= nil and type(rewards.preparations) ~= "table")
    then
        return false
    end
    for _, session in ipairs(rewards.sessions) do
        if not validRewardSession(session) then
            return false
        end
    end
    for _, preparation in ipairs(rewards.preparations or {}) do
        if
            type(preparation) ~= "table"
            or not isInteger(preparation.id)
            or preparation.id < 1
            or not isInteger(preparation.questID)
            or preparation.questID < 1
            or not isName(preparation.character)
            or not isName(preparation.realm)
            or not isInteger(preparation.at)
            or type(preparation.confirmed) ~= "boolean"
            or type(preparation.baseline) ~= "table"
            or (preparation.stage ~= nil and preparation.stage ~= "accept")
            or (preparation.acceptedAt ~= nil and not isInteger(preparation.acceptedAt))
            or (preparation.level ~= nil and not isInteger(preparation.level))
            or (preparation.place ~= nil and type(preparation.place) ~= "string")
            or not validPlaceKind(preparation.placeKind)
            or (preparation.name ~= nil and not isName(preparation.name))
        then
            return false
        end
        for key, item in pairs(preparation.baseline) do
            if
                type(key) ~= "string"
                or type(item) ~= "table"
                or not isInteger(item.quantity)
                or item.quantity < 0
                or not isInteger(item.gained)
                or item.gained < 0
                or (item.discovery ~= nil and type(item.discovery) ~= "boolean")
            then
                return false
            end
        end
    end
    return true
end

local function choiceIsProven(session, sessions, grouped)
    if not session.choiceGroup then
        return true
    end
    local specific
    local increased
    local specificCount = 0
    local increasedCount = 0
    for _, candidate in ipairs(sessions) do
        if candidate.choiceGroup == session.choiceGroup then
            if candidate.awarded > 0 and candidate ~= session then
                return false
            end
            if candidate.specific then
                specific = candidate
                specificCount = specificCount + 1
            end
            local group = grouped[candidate.key]
            if group and group.quantity > candidate.baseline then
                increased = candidate
                increasedCount = increasedCount + 1
            end
        end
    end
    if specificCount > 0 then
        return specificCount == 1 and specific == session
    end
    if increasedCount > 1 then
        session.ambiguous = true
    end
    return increasedCount == 1 and increased == session and not session.ambiguous
end

-- The reward window can link a choice with a preview-only bonus ID. A
-- received Quest item takes the place of its preview in the offer.
local function replacePreview(sessions, received)
    local itemID = received.key:match("^(%d+):")
    for index = #sessions, 1, -1 do
        local existing = sessions[index]
        if
            existing.method == "Quest"
            and not existing.specific
            and existing.awarded == 0
            and existing.key ~= received.key
            and existing.key:match("^(%d+):") == itemID
            and existing.character == received.character
            and existing.realm == received.realm
            and existing.context
            and received.context
            and existing.context.id == received.context.id
            and existing.questPreparationID == received.questPreparationID
        then
            received.choiceGroup = received.choiceGroup or existing.choiceGroup
            table.remove(sessions, index)
        end
    end
end

-- Once one choice is received, the offer's other choices were declined.
local function chosenGroups(sessions)
    local chosen = {}
    for _, session in ipairs(sessions) do
        if session.choiceGroup and session.awarded > 0 then
            chosen[session.choiceGroup] = true
        end
    end
    return chosen
end

local function validRewardReceipt(receipt, actor)
    return Evidence.validReceipt(receipt)
        and validGainActor(actor)
        and rewardMethods[receipt.method]
        and validRewardContext(receipt.context, receipt.method)
        and (receipt.method ~= "Obtained" or receipt.context == nil)
        and (receipt.preview == nil or type(receipt.preview) == "boolean")
        and (
            receipt.choiceGroup == nil
            or (isName(receipt.choiceGroup) and receipt.method == "Quest" and receipt.preview == true)
        )
end

-- Opens a confirmed Quest session for each item that rose above an
-- accepted offer's baseline, appending it to pending.sessions. A rise that
-- another channel already counted, such as loot, is not the quest's.
---@param pending AzerothLedgerRewardState
---@param at integer
---@param character string
---@param realm string
---@param quantity fun(key: string): integer
---@param keys table<string, true>
---@param record fun(key: string): AzerothLedgerRecord? The check's current record
local function openAccepted(pending, at, character, realm, quantity, keys, record)
    for _, preparation in ipairs(pending.preparations or {}) do
        if
            preparation.stage == "accept"
            and preparation.confirmed
            and preparation.character == character
            and preparation.realm == realm
            and preparationLive(preparation, at)
        then
            for key in pairs(keys) do
                local before = preparation.baseline[key]
                local current = record(key)
                local baselineGained = before and before.gained or (current and current.totalGained or 0)
                local session
                for _, existing in ipairs(pending.sessions) do
                    if existing.questPreparationID == preparation.id and existing.key == key then
                        session = existing
                    end
                end
                local awarded = session and session.awarded or 0
                local otherGains = current and math.max(0, current.totalGained - baselineGained - awarded) or 0
                local increase = quantity(key) - (before and before.quantity or 0) - otherGains
                if session then
                    session.quantity = math.max(session.quantity, increase)
                elseif increase > 0 then
                    pending.nextID = pending.nextID + 1
                    pending.sessions[#pending.sessions + 1] = {
                        id = pending.nextID,
                        key = key,
                        method = "Quest",
                        context = { kind = "quest", id = preparation.questID, name = preparation.name },
                        character = character,
                        realm = realm,
                        level = preparation.level,
                        place = preparation.place,
                        placeKind = preparation.placeKind,
                        at = preparation.acceptedAt,
                        baseline = before and before.quantity or 0,
                        baselineGained = baselineGained,
                        quantity = increase,
                        awarded = 0,
                        discovery = not before or before.discovery == true,
                        confirmed = true,
                        specific = true,
                        questPreparationID = preparation.id,
                    }
                end
            end
        end
    end
end

StoreRewardState.validRewardSession = validRewardSession
StoreRewardState.preparationLive = preparationLive
StoreRewardState.validRewardState = validRewardState
StoreRewardState.choiceIsProven = choiceIsProven
StoreRewardState.validRewardReceipt = validRewardReceipt
StoreRewardState.openAccepted = openAccepted
StoreRewardState.replacePreview = replacePreview
StoreRewardState.chosenGroups = chosenGroups

addon.StoreRewardState = StoreRewardState
