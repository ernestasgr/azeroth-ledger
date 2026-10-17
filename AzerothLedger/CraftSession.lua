local _, addon = ...
addon.Sessions = addon.Sessions or {}

-- Crafted items. The recipe begun by the current cast names the crafted result.
local CraftSession = {}

---@param runtime ALRuntime
function CraftSession.new(runtime)
    local recipeID

    local function stopped()
        recipeID = nil
    end

    return {
        events = {
            TRADE_SKILL_CRAFT_BEGIN = function(id)
                recipeID = id
            end,
            TRADE_SKILL_ITEM_CRAFTED_RESULT = function(result)
                runtime.reward(addon.Reward.craft(runtime.api, result, recipeID))
            end,
            UPDATE_TRADESKILL_CAST_STOPPED = stopped,
            TRADE_SKILL_CLOSE = stopped,
        },
    }
end

addon.Sessions.Craft = CraftSession
