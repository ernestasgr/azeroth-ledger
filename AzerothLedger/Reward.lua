local _, addon = ...

local Reward = {}

---@class AzerothLedgerRewardApi
---@field C_QuestLog? {GetTitleForQuestID?: fun(questID: integer): string?}
---@field C_TradeSkillUI? {GetRecipeInfo?: fun(recipeID: integer): {name?: string}?}

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
    reward.context = { kind = "quest", id = questID }
    local questLog = api.C_QuestLog
    if type(questLog) == "table" and type(questLog.GetTitleForQuestID) == "function" then
        local ok, title = pcall(questLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" then
            reward.context.name = title
        end
    end
    return reward
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
