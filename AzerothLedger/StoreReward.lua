local _, addon = ...

-- Quest preparation and turn-in, quest accept, quest reward and craft receipts.

local V = addon.SchemaValidate
local isInteger, isName, validPlaceKind = V.isInteger, V.isName, V.validPlaceKind
local validRewardContext, validRewardSession = V.validRewardContext, V.validRewardSession
local preparationLive = V.preparationLive

local StoreReward = {}

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

-- Returns the reward sessions and award a possessions scan settles.
function StoreReward.install(store, kernel)
    local valid, readable, saveFields, editGainRoot = kernel.valid, kernel.readable, kernel.save, kernel.editGainRoot
    local heldKeys, bagQuantity, possessionsQuantity = kernel.heldKeys, kernel.bagQuantity, kernel.possessionsQuantity

    local function rewardSessions(at, pending)
        local result = {}
        local rewards = pending or kernel.raw().rewards
        local sessions = type(rewards) == "table" and rewards.sessions or nil
        for _, session in ipairs(type(sessions) == "table" and sessions or {}) do
            if validRewardSession(session) and at >= session.at and at - session.at < 60 then
                result[#result + 1] = session
            end
        end
        return result
    end

    local function questPreparations(at)
        local result = {}
        local rewards = kernel.raw().rewards
        local preparations = type(rewards) == "table" and rewards.preparations or nil
        for _, preparation in ipairs(type(preparations) == "table" and preparations or {}) do
            if preparationLive(preparation, at) then
                result[#result + 1] = preparation
            end
        end
        return result
    end

    local function questPreparation(questID, at, actor, stage)
        local preparations = questPreparations(at)
        for index = #preparations, 1, -1 do
            local preparation = preparations[index]
            if
                preparation.questID == questID
                and preparation.character == actor.character
                and preparation.realm == actor.realm
                and preparation.stage == stage
            then
                return preparation
            end
        end
        return nil
    end

    local function prepare(questID, at, actor, stage)
        if
            not readable
            or not isInteger(questID)
            or questID < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        local area = store:area(actor.character, actor.realm, "bags")
        local equippedArea = store:area(actor.character, actor.realm, "equipped")
        if
            not area
            or not area.complete
            or area.seenAt > at
            or not equippedArea
            or not equippedArea.complete
            or equippedArea.seenAt ~= area.seenAt
        then
            return false
        end
        local existing = questPreparation(questID, at, actor, stage)
        if existing and not existing.confirmed then
            return false
        end
        local rewards = type(kernel.raw().rewards) == "table" and kernel.raw().rewards or nil
        local nextID = (rewards and isInteger(rewards.nextID) and rewards.nextID or 0) + 1
        local baseline = {}
        local possessions = {}
        for _, storageArea in ipairs({ "bags", "equipped" }) do
            for key in pairs(heldKeys(actor.character, actor.realm, storageArea)) do
                possessions[key] = true
            end
        end
        for key in pairs(possessions) do
            local record = valid[key]
            baseline[key] = {
                quantity = possessionsQuantity(record, actor.character, actor.realm),
                gained = record.totalGained,
            }
        end
        local preparations = {}
        for _, preparation in ipairs(questPreparations(at)) do
            if
                preparation.questID ~= questID
                or preparation.character ~= actor.character
                or preparation.realm ~= actor.realm
                or preparation.stage ~= stage
            then
                preparations[#preparations + 1] = preparation
            end
        end
        preparations[#preparations + 1] = {
            id = nextID,
            questID = questID,
            character = actor.character,
            realm = actor.realm,
            at = at,
            confirmed = false,
            baseline = baseline,
            stage = stage,
        }
        saveFields({ rewards = { nextID = nextID, sessions = rewardSessions(at), preparations = preparations } })
        return true
    end

    -- Possessions before the reward window opens; QUEST_TURNED_IN confirms them.
    function store.questPrepared(_self, questID, at, actor)
        return prepare(questID, at, actor, nil)
    end

    -- Possessions before a quest is accepted. Quest givers can hand over
    -- items, such as a letter to deliver, that the offer never names.
    function store.questOffered(_self, questID, at, actor)
        return prepare(questID, at, actor, "accept")
    end

    -- QUEST_ACCEPTED confirms the offer. The next paired possessions check
    -- credits each item that rose above the offer baseline to the quest.
    function store.questAccepted(_self, questID, at, actor)
        if
            not readable
            or not isInteger(questID)
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
            or not isInteger(actor.level)
            or type(actor.place) ~= "string"
            or not validPlaceKind(actor.placeKind)
            or (actor.questName ~= nil and not isName(actor.questName))
        then
            return false
        end
        local preparation = questPreparation(questID, at, actor, "accept")
        if not preparation or preparation.confirmed then
            return false
        end
        preparation.confirmed = true
        preparation.acceptedAt = at
        preparation.level = actor.level
        preparation.place = actor.place
        preparation.placeKind = actor.placeKind
        preparation.name = actor.questName
        local rewards = kernel.raw().rewards
        saveFields({
            rewards = { nextID = rewards.nextID, sessions = rewardSessions(at), preparations = questPreparations(at) },
        })
        return true
    end

    ---@param receipt AzerothLedgerRewardReceipt
    ---@param at integer
    ---@param actor AzerothLedgerGainActor
    function store.rewardReceipt(_self, receipt, at, actor)
        if
            not readable
            or type(receipt) ~= "table"
            or type(receipt.key) ~= "string"
            or (receipt.method ~= "Quest" and receipt.method ~= "Crafted")
            or not isInteger(receipt.quantity)
            or receipt.quantity < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
            or not isInteger(actor.level)
            or type(actor.place) ~= "string"
            or not validPlaceKind(actor.placeKind)
            or (receipt.preview ~= nil and type(receipt.preview) ~= "boolean")
            or (receipt.choiceGroup ~= nil and (type(receipt.choiceGroup) ~= "string" or receipt.choiceGroup == ""))
            or (receipt.choiceGroup ~= nil and (receipt.method ~= "Quest" or not receipt.preview))
        then
            return false
        end
        local area = store:area(actor.character, actor.realm, "bags")
        if not area or not area.complete or area.seenAt > at then
            return false
        end
        local context = receipt.context
        if not validRewardContext(context, receipt.method) then
            return false
        end
        local preparation = receipt.method == "Quest" and context and questPreparation(context.id, at, actor, nil)
            or nil
        local sessions = rewardSessions(at)
        local session
        for _, existing in ipairs(sessions) do
            local awaitingReward = not existing.confirmed or existing.awarded < existing.quantity
            if
                existing.key == receipt.key
                and existing.method == receipt.method
                and existing.character == actor.character
                and existing.realm == actor.realm
                and (not receipt.preview or existing.choiceGroup == receipt.choiceGroup)
                and (not preparation or existing.questPreparationID == preparation.id)
                and (receipt.method ~= "Quest" or preparation or awaitingReward)
                and (
                    (not existing.context and not context)
                    or (existing.context and context and existing.context.id == context.id)
                )
            then
                session = existing
                break
            end
        end
        local rewards = type(kernel.raw().rewards) == "table" and kernel.raw().rewards or nil
        local nextID = rewards and rewards.nextID or 0
        if not session then
            nextID = (isInteger(nextID) and nextID or 0) + 1
            local before = preparation and preparation.baseline[receipt.key] or nil
            if preparation and not before and valid[receipt.key] then
                before = { quantity = 0, gained = valid[receipt.key].totalGained }
                preparation.baseline[receipt.key] = before
            end
            session = {
                id = nextID,
                key = receipt.key,
                method = receipt.method,
                context = context,
                character = actor.character,
                realm = actor.realm,
                level = actor.level,
                place = actor.place,
                placeKind = actor.placeKind,
                at = at,
                baseline = preparation and (before and before.quantity or 0)
                    or bagQuantity(valid[receipt.key], actor.character, actor.realm),
                baselineGained = preparation and (before and before.gained or 0)
                    or (valid[receipt.key] and valid[receipt.key].totalGained or 0),
                quantity = 0,
                awarded = 0,
                discovery = preparation and (not before or before.discovery == true) or not valid[receipt.key],
                confirmed = receipt.method == "Crafted" or (preparation and preparation.confirmed) or false,
                choiceGroup = receipt.choiceGroup,
                specific = receipt.method == "Quest" and not receipt.preview or nil,
                questPreparationID = preparation and preparation.id or nil,
            }
            sessions[#sessions + 1] = session
        end
        if receipt.method == "Quest" then
            session.quantity = math.max(session.quantity, receipt.quantity)
            if not receipt.preview then
                session.specific = true
            end
        else
            session.quantity = session.quantity + receipt.quantity
        end
        saveFields({ rewards = { nextID = nextID, sessions = sessions, preparations = questPreparations(at) } })
        return true
    end

    function store.questTurnedIn(_self, questID, at, actor)
        if
            not readable
            or not isInteger(questID)
            or questID < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        if not store:expireEvidence(at) then
            return false
        end
        local changed = false
        local preparation = questPreparation(questID, at, actor, nil)
        if preparation and not preparation.confirmed then
            preparation.confirmed = true
            changed = true
        end
        for _, session in ipairs(rewardSessions(at)) do
            if
                session.method == "Quest"
                and session.context
                and session.context.id == questID
                and session.character == actor.character
                and session.realm == actor.realm
                and not session.confirmed
            then
                session.confirmed = true
                changed = true
            end
        end
        if changed then
            local rewards = kernel.raw().rewards
            saveFields({
                rewards = {
                    nextID = rewards.nextID,
                    sessions = rewardSessions(at),
                    preparations = questPreparations(at),
                },
            })
        end
        return changed
    end

    local function awardReward(session, key, currentQuantity, records)
        local record = records[key] or valid[key]
        if not record or not session.confirmed then
            return
        end
        local otherGains = math.max(0, record.totalGained - session.baselineGained - session.awarded)
        local target = math.min(session.quantity, math.max(0, currentQuantity - session.baseline - otherGains))
        local quantity = target - session.awarded
        if quantity <= 0 then
            return
        end
        local gainID = "reward:" .. session.id .. ":" .. key
        record = editGainRoot(record, gainID)
        local gain
        for _, existing in ipairs(record.gains) do
            if existing.id == gainID then
                gain = existing
                break
            end
        end
        if gain then
            gain.quantity = gain.quantity + quantity
        else
            gain = {
                id = gainID,
                at = session.at,
                quantity = quantity,
                character = session.character,
                realm = session.realm,
                level = session.level,
                place = session.place,
                placeKind = session.placeKind,
                method = session.method,
                context = session.context,
            }
            record.gains[#record.gains + 1] = gain
        end
        record.totalGained = record.totalGained + quantity
        record.firstGained = record.firstGained and math.min(record.firstGained, gain.at) or gain.at
        record.lastGained = record.lastGained and math.max(record.lastGained, gain.at) or gain.at
        if session.discovery then
            record.evidencedDiscovery = true
            record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
            for _, character in ipairs(record.characters) do
                if character.name == session.character and character.realm == session.realm then
                    character.firstSeenUnits = math.max(0, character.firstSeenUnits - quantity)
                    break
                end
            end
        end
        session.awarded = target
        records[key] = record
    end

    -- Opens a confirmed Quest session for each item that rose above an
    -- accepted offer's baseline, appending it to pending.sessions.
    ---@param pending AzerothLedgerRewardState
    ---@param at integer
    ---@param character string
    ---@param realm string
    ---@param quantity fun(key: string): integer
    ---@param keys table<string, true>
    local function openAccepted(pending, at, character, realm, quantity, keys)
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
                    local increase = quantity(key) - (before and before.quantity or 0)
                    local session
                    for _, existing in ipairs(pending.sessions) do
                        if existing.questPreparationID == preparation.id and existing.key == key then
                            session = existing
                        end
                    end
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
                            baselineGained = before and before.gained or (valid[key] and valid[key].totalGained or 0),
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

    return {
        sessions = rewardSessions,
        award = awardReward,
        choiceIsProven = choiceIsProven,
        openAccepted = openAccepted,
    }
end

addon.StoreReward = StoreReward
