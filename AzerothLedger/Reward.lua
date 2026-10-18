local _, addon = ...

-- The quest and craft reward channel. Quest offers and accepts, reward offers,
-- delayed quest loot, and turn-ins: offered rewards are stored as previews, and
-- a choice group ties the choosable rewards of one offer. Items a quest giver
-- hands over on accept are measured against the possessions checked when the
-- quest was offered. The recipe begun by the current cast names a crafted result.
local Reward = {}

---@class AzerothLedgerRewardApi
---@field C_QuestLog? {GetTitleForQuestID?: fun(questID: integer): string?}
---@field C_TradeSkillUI? {GetRecipeInfo?: fun(recipeID: integer): {name?: string}?}
---@field GetQuestID? fun(): integer?
---@field GetNumQuestChoices? fun(): integer?
---@field GetNumQuestRewards? fun(): integer?
---@field GetQuestItemLink? fun(kind: string, index: integer): string?
---@field GetQuestItemInfo? fun(kind: string, index: integer): string?, any, integer?

---@class AzerothLedgerCraftResult
---@field itemID integer
---@field hyperlink string
---@field quantity integer

local function item(link, itemID, quantity)
    if type(link) ~= "string" or type(itemID) ~= "number" or type(quantity) ~= "number" then
        return nil
    end
    if quantity < 1 or quantity ~= math.floor(quantity) then
        return nil
    end
    local key = addon.Item.key(link, itemID)
    return key and { key = key, quantity = quantity } or nil
end

---@param api AzerothLedgerRewardApi
---@param questID integer
---@return string?
function Reward.questName(api, questID)
    local questLog = api.C_QuestLog
    if type(questLog) == "table" and type(questLog.GetTitleForQuestID) == "function" then
        local ok, title = pcall(questLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" then
            return title
        end
    end
    return nil
end

---@param api AzerothLedgerRewardApi
---@param questID integer
---@param link string
---@param quantity integer
---@return AzerothLedgerRewardReceipt?
function Reward.quest(api, questID, link, quantity)
    if type(questID) ~= "number" or questID < 1 or questID ~= math.floor(questID) then
        return nil
    end
    local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
    local reward = item(link, itemID, quantity)
    if not reward then
        return nil
    end
    reward.method = "Quest"
    reward.context = { kind = "quest", id = questID, name = Reward.questName(api, questID) }
    return reward
end

---@param api AzerothLedgerRewardApi
---@return {questID: integer, choices: AzerothLedgerRewardReceipt[], fixed: AzerothLedgerRewardReceipt[] }?
function Reward.offer(api)
    if
        type(api.GetQuestID) ~= "function"
        or type(api.GetNumQuestChoices) ~= "function"
        or type(api.GetNumQuestRewards) ~= "function"
        or type(api.GetQuestItemLink) ~= "function"
        or type(api.GetQuestItemInfo) ~= "function"
    then
        return nil
    end
    local idOK, questID = pcall(api.GetQuestID)
    if not idOK or type(questID) ~= "number" or questID < 1 or questID ~= math.floor(questID) then
        return nil
    end
    local offer = { questID = questID, choices = {}, fixed = {} }
    for _, group in ipairs({ { kind = "choice", items = offer.choices }, { kind = "reward", items = offer.fixed } }) do
        local countAPI = group.kind == "choice" and api.GetNumQuestChoices or api.GetNumQuestRewards
        if type(countAPI) ~= "function" then
            return nil
        end
        local countOK, count = pcall(countAPI)
        if countOK and type(count) == "number" and count >= 0 and count <= 100 and count == math.floor(count) then
            for index = 1, count do
                local linkOK, link = pcall(api.GetQuestItemLink, group.kind, index)
                local infoOK, _, _, quantity = pcall(api.GetQuestItemInfo, group.kind, index)
                if linkOK and infoOK and type(link) == "string" and type(quantity) == "number" then
                    local receipt = Reward.quest(api, questID, link, quantity)
                    if receipt then
                        group.items[#group.items + 1] = receipt
                    else
                        return nil
                    end
                else
                    return nil
                end
            end
        else
            return nil
        end
    end
    return offer
end

---@param api AzerothLedgerRewardApi
---@param result AzerothLedgerCraftResult
---@param recipeID? integer
---@return AzerothLedgerRewardReceipt?
function Reward.craft(api, result, recipeID)
    if type(result) ~= "table" then
        return nil
    end
    local reward = item(result.hyperlink, result.itemID, result.quantity)
    if not reward then
        return nil
    end
    reward.method = "Crafted"
    if type(recipeID) == "number" and recipeID > 0 and recipeID == math.floor(recipeID) then
        reward.context = { kind = "recipe", id = recipeID }
        local tradeSkill = api.C_TradeSkillUI
        if type(tradeSkill) == "table" and type(tradeSkill.GetRecipeInfo) == "function" then
            local ok, info = pcall(tradeSkill.GetRecipeInfo, recipeID)
            if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
                reward.context.name = info.name
            end
        end
    end
    return reward
end

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

-- The store commands this channel writes through.
---@type ALCommandName[]
Reward.commands = { "rewardReceipt", "questPrepared", "questOffered", "questAccepted", "questTurnedIn" }

---@class ALRewardDependencies
---@field api AzerothLedgerRewardApi
---@field clock fun(): integer?
---@field commands ALCommands Built from `Reward.commands`
---@field check fun(area: string)
---@field refresh fun(character: string, realm: string)
---@field exchangeOpen fun(): boolean Whether a mailbox or trade window explains a received item

-- Seconds after a quest window closes in which a received item is the quest's.
local questQuiet = 5

---@param deps ALRewardDependencies
function Reward.new(deps)
    local api, clock, commands, check, refresh = deps.api, deps.clock, deps.commands, deps.check, deps.refresh
    local offers = 0
    local recipeID
    local questOpen, questAt = false, nil

    -- Quest rewards can go straight into gear, so the gain is checked against
    -- bags and equipped slots together.
    local function receive(receipt)
        if not receipt then
            return
        end
        local accepted, context = commands.rewardReceipt(receipt)
        if accepted and context then
            if receipt.method == "Quest" then
                check("possessions")
            end
            refresh(context.character, context.realm)
        end
    end

    local function preview(receipts, context, choiceGroup)
        local changed = false
        for _, receipt in ipairs(receipts) do
            receipt.preview = true
            receipt.choiceGroup = choiceGroup
            changed = commands.rewardReceipt(receipt, context) or changed
        end
        return changed
    end

    local function offered()
        check("possessions")
        local offer = Reward.offer(api)
        local context = addon.Runtime.player(api, clock)
        if not context then
            return
        end
        local id = questID(api, offer)
        if id then
            commands.questPrepared(id, context)
        end
        if not offer then
            return
        end
        offers = offers + 1
        local choiceGroup = table.concat({ context.character, context.realm, offer.questID, context.at, offers }, ":")
        local changed = preview(offer.choices, context, choiceGroup)
        changed = preview(offer.fixed, context, nil) or changed
        if changed then
            refresh(context.character, context.realm)
        end
    end

    local function detail()
        check("possessions")
        local id = questID(api)
        if id then
            commands.questOffered(id)
        end
    end

    local function accepted(id)
        local context = addon.Runtime.player(api, clock)
        if not context or type(id) ~= "number" then
            return
        end
        context.questName = Reward.questName(api, id)
        if commands.questAccepted(id, context) then
            check("possessions")
        end
    end

    local function stopped()
        recipeID = nil
    end

    local function questWindow(open)
        questOpen, questAt = open, clock()
    end

    local function questBusy()
        local at = clock()
        return questOpen or (questAt ~= nil and at ~= nil and at - questAt <= questQuiet)
    end

    -- A receipt the loot channel could not place. A recipe's item is left to
    -- its craft result; anything else made by you was conjured by a spell. An
    -- item handed over outside a quest, mailbox or trade came from an NPC or
    -- from using another item.
    ---@param parsed AzerothLedgerLootReceipt
    local function received(parsed)
        local receipt
        if parsed.kind == "created" and not recipeID then
            receipt = { key = parsed.key, quantity = parsed.quantity, method = "Crafted" }
        elseif parsed.kind == "pushed" and not questBusy() and not deps.exchangeOpen() then
            receipt = { key = parsed.key, quantity = parsed.quantity, method = "Obtained" }
        end
        receive(receipt)
    end

    return {
        received = received,
        events = {
            QUEST_DETAIL = function()
                questWindow(true)
                detail()
            end,
            QUEST_PROGRESS = function()
                questWindow(true)
            end,
            QUEST_FINISHED = function()
                questWindow(false)
            end,
            QUEST_ACCEPTED = function(id)
                questWindow(questOpen)
                accepted(id)
            end,
            QUEST_COMPLETE = function()
                questWindow(true)
                offered()
            end,
            QUEST_LOOT_RECEIVED = function(...)
                receive(Reward.quest(api, ...))
            end,
            QUEST_TURNED_IN = function(id)
                questWindow(questOpen)
                if commands.questTurnedIn(id) then
                    check("possessions")
                end
            end,
            TRADE_SKILL_CRAFT_BEGIN = function(id)
                recipeID = id
            end,
            TRADE_SKILL_ITEM_CRAFTED_RESULT = function(result)
                receive(Reward.craft(api, result, recipeID))
            end,
            UPDATE_TRADESKILL_CAST_STOPPED = stopped,
            TRADE_SKILL_CLOSE = stopped,
        },
    }
end

addon.Reward = Reward
