local _, addon = ...
addon.Sessions = addon.Sessions or {}

-- Quest reward offers, delayed quest loot, and turn-ins. Offered rewards are
-- stored as previews; a choice group ties the choosable rewards of one offer.
local QuestSession = {}

local function questID(api, offer)
    if offer and offer.questID then
        return offer.questID
    end
    if type(api.GetQuestID) == "function" then
        local ok, id = pcall(api.GetQuestID)
        if ok then
            return id
        end
    end
end

---@param runtime ALRuntime
function QuestSession.new(runtime)
    local api = runtime.api
    local offers = 0

    local function preview(receipts, context, choiceGroup)
        local changed = false
        for _, receipt in ipairs(receipts) do
            receipt.preview = true
            receipt.choiceGroup = choiceGroup
            changed = runtime.store():rewardReceipt(receipt, context.at, context) or changed
        end
        return changed
    end

    local function offered()
        runtime.inventory:check("possessions")
        local offer = addon.Reward.offer(api)
        local context = runtime.player()
        if not context then
            return
        end
        local id = questID(api, offer)
        if id then
            runtime.store():questPrepared(id, context.at, context)
        end
        if not offer then
            return
        end
        offers = offers + 1
        local choiceGroup = table.concat({ context.character, context.realm, offer.questID, context.at, offers }, ":")
        local changed = preview(offer.choices, context, choiceGroup)
        changed = preview(offer.fixed, context, nil) or changed
        if changed then
            runtime.refresh(context.character, context.realm)
        end
    end

    return {
        events = {
            QUEST_COMPLETE = offered,
            QUEST_LOOT_RECEIVED = function(...)
                runtime.reward(addon.Reward.quest(api, ...))
            end,
            QUEST_TURNED_IN = function(id)
                local context = runtime.player()
                if context and runtime.store():questTurnedIn(id, context.at, context) then
                    runtime.inventory:check("possessions")
                end
            end,
        },
    }
end

addon.Sessions.Quest = QuestSession
