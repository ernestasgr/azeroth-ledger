local _, addon = ...

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

addon.Reward = Reward
