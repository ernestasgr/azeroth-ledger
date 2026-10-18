local _, addon = ...

-- Quest preparation and turn-in, quest accept, quest reward and craft receipts.

local V = addon.SchemaValidate
local isInteger, isName = V.isInteger, V.isName
local validGainActor = V.validGainActor
local validRewardContext, copyValue = V.validRewardContext, V.copyValue
local Evidence = addon.StoreEvidence

local StoreReward = {}

local State = addon.StoreRewardState
local validRewardSession, preparationLive = State.validRewardSession, State.preparationLive
local validRewardState, choiceIsProven = State.validRewardState, State.choiceIsProven
local validRewardReceipt = State.validRewardReceipt

---@type AzerothLedgerSlice
StoreReward.slice = {
    name = "rewards",
    validate = validRewardState,
    -- Capture previously unheld items lazily before their first change during
    -- a quest preparation. Late item identification keeps the pre-action totals.
    beforeChange = function(state, key, possessions, before)
        for _, preparation in ipairs(state and state.preparations or {}) do
            if not preparation.baseline[key] then
                preparation.baseline[key] = {
                    quantity = possessions(preparation.character, preparation.realm),
                    gained = before and before.totalGained or 0,
                    discovery = before == nil,
                }
            end
        end
    end,
}

-- Returns the correlation engine and the latest confirmed reward lookup.
function StoreReward.install(store, kernel, slice)
    local valid, readable, saveFields, recordGain = kernel.valid, kernel.readable, kernel.save, kernel.recordGain
    local heldKeys, bagQuantity, possessionsQuantity = kernel.heldKeys, kernel.bagQuantity, kernel.possessionsQuantity
    local checkedPossessions, rewardState = kernel.checkedPossessions, slice.state

    local function healthyState()
        local state = rewardState()
        return state and validRewardState(state) and state or nil
    end

    local function rewardSessions(at, pending)
        local result = {}
        local rewards = pending or rewardState()
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
        local rewards = rewardState()
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
        local rewards = type(rewardState()) == "table" and rewardState() or nil
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
    local function questPrepared(questID, at, actor)
        return prepare(questID, at, actor, nil)
    end

    -- Possessions before a quest is accepted. Quest givers can hand over
    -- items, such as a letter to deliver, that the offer never names.
    local function questOffered(questID, at, actor)
        return prepare(questID, at, actor, "accept")
    end

    -- QUEST_ACCEPTED confirms the offer. The next paired possessions check
    -- credits each item that rose above the offer baseline to the quest.
    local function questAccepted(questID, at, actor)
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
        local rewards = rewardState()
        saveFields({
            rewards = { nextID = rewards.nextID, sessions = rewardSessions(at), preparations = questPreparations(at) },
        })
        return true
    end

    ---@param receipt AzerothLedgerRewardReceipt
    ---@param at integer
    ---@param actor AzerothLedgerGainActor
    local function rewardReceipt(receipt, at, actor)
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
        local rewards = type(rewardState()) == "table" and rewardState() or nil
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
                confirmed = receipt.method ~= "Quest" or (preparation and preparation.confirmed) or false,
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

    local function questTurnedIn(questID, at, actor)
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
            local rewards = rewardState()
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
        record = recordGain(record, {
            id = "reward:" .. session.id .. ":" .. key,
            at = session.at,
            quantity = quantity,
            character = session.character,
            realm = session.realm,
            level = session.level,
            place = session.place,
            placeKind = session.placeKind,
            method = session.method,
            context = session.context,
        }, { discovery = session.discovery })
        session.awarded = target
        records[key] = record
    end

    -- A craft or quest receipt can share the chat channel with loot: the latest
    -- confirmed reward for this item and character within its window.
    local function confirmedReward(key, at, actor)
        local state = rewardState()
        local sessions = type(state) == "table" and state.sessions or nil
        local latest
        for _, reward in ipairs(type(sessions) == "table" and sessions or {}) do
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
        return latest
    end

    local function stale(at)
        local state = healthyState()
        if Evidence.staleEntries(state and state.sessions, at) then
            return true
        end
        for _, entry in ipairs(state and state.preparations or {}) do
            if at >= entry.at and not preparationLive(entry, at) then
                return true
            end
        end
        return false
    end

    local function expire(at, reason, retain)
        local original = healthyState()
        if type(original) ~= "table" then
            return nil, false
        end
        local state = copyValue(original)
        local changed = Evidence.expireEntries(state.sessions, at, reason, nil, function(entry, openedAt)
            if entry.awarded < entry.quantity or not entry.confirmed then
                retain("rewards", reason, openedAt, entry, entry)
            end
        end)
        for index = #(state.preparations or {}), 1, -1 do
            local entry = state.preparations[index]
            if reason == "reload" or (at >= entry.at and not preparationLive(entry, at)) then
                -- Declining an offered quest is ordinary, not evidence.
                if not entry.confirmed and entry.stage ~= "accept" then
                    retain("quest", reason, entry.at, entry, entry)
                end
                table.remove(state.preparations, index)
                changed = true
            end
        end
        return state, changed
    end

    local function visit(emit, pause)
        local state = healthyState()
        if not readable or not state then
            return
        end
        for _, entry in ipairs(state.sessions) do
            if entry.awarded < entry.quantity or not entry.confirmed then
                emit("rewards:" .. entry.id, "rewards", "active", entry.at, entry, entry)
            end
            pause()
        end
        for _, entry in ipairs(state.preparations or {}) do
            if not entry.confirmed then
                emit("quest:" .. entry.questID .. ":" .. entry.at, "quest", "active", entry.at, entry, entry)
            end
            pause()
        end
    end

    -- Settles confirmed rewards against one possessions check.
    ---@param scan AzerothLedgerCheck
    local function check(scan)
        local snapshot = scan.snapshot
        local pending = healthyState() and copyValue(rewardState()) or nil
        local active = (snapshot.area == "bags" or snapshot.area == "equipped")
                and snapshot.complete
                and rewardSessions(snapshot.seenAt, pending)
            or {}
        local measured = snapshot.area == "bags"
            and snapshot.complete
            and type(scan.oldScope) == "table"
            and scan.oldScope.complete
        local handler = {}
        function handler.record(key, group)
            if not measured then
                return
            end
            for _, reward in ipairs(active) do
                if
                    reward.key == key
                    and not reward.questPreparationID
                    and reward.character == snapshot.character
                    and reward.realm == snapshot.realm
                    and choiceIsProven(reward, active, scan.grouped)
                then
                    awardReward(reward, key, group.quantity, scan.records)
                end
            end
        end
        -- The paired equipped check measures the whole possession change.
        function handler.finish()
            if not scan.paired then
                return
            end
            local records, grouped = scan.records, scan.grouped
            if pending then
                local keys = scan.pairedKeys()
                for key in pairs(records) do
                    keys[key] = true
                end
                local opened = #pending.sessions
                local character, realm = snapshot.character, snapshot.realm
                State.openAccepted(pending, snapshot.seenAt, character, realm, function(key)
                    return checkedPossessions(records[key] or valid[key], character, realm, grouped[key])
                end, keys, valid)
                for index = opened + 1, #pending.sessions do
                    active[#active + 1] = pending.sessions[index]
                end
            end
            local quantities = {}
            for _, reward in ipairs(active) do
                if reward.questPreparationID then
                    local record = records[reward.key] or valid[reward.key]
                    local equipped = grouped[reward.key]
                    quantities[reward.key] = {
                        quantity = checkedPossessions(record, snapshot.character, snapshot.realm, equipped),
                    }
                end
            end
            for _, reward in ipairs(active) do
                if
                    reward.questPreparationID
                    and reward.character == snapshot.character
                    and reward.realm == snapshot.realm
                    and choiceIsProven(reward, active, quantities)
                then
                    awardReward(reward, reward.key, quantities[reward.key].quantity, records)
                end
            end
        end
        function handler.commit(fields)
            fields.rewards = pending
        end
        return handler
    end

    local function validQuest(questID)
        return isInteger(questID) and questID > 0
    end

    return {
        engine = { stale = stale, expire = expire, visit = visit, check = check },
        confirmed = confirmedReward,
        ---@type table<string, AzerothLedgerCommand>
        commands = {
            questPrepared = { valid = validQuest, run = questPrepared, cost = 1 },
            questOffered = { valid = validQuest, run = questOffered },
            questAccepted = {
                valid = function(questID, actor)
                    return isInteger(questID)
                        and validGainActor(actor)
                        and (actor.questName == nil or isName(actor.questName))
                end,
                run = questAccepted,
            },
            rewardReceipt = { valid = validRewardReceipt, run = rewardReceipt, cost = 1 },
            questTurnedIn = { valid = validQuest, run = questTurnedIn },
        },
    }
end

addon.StoreReward = StoreReward
