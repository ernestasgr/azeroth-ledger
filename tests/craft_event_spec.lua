local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
-- Synthetic crafting events in the order the Forever capability probe traces them:
-- the cast begins with the recipe, the result names the item, then bags update.
local bolt = "|Hitem:2996::::::::|h[Bolt of Linen Cloth]|h"
local clock, bolts = 1000, 0

GetServerTime = function()
    return clock
end
UnitName = function()
    return "Ada"
end
GetRealmName = function()
    return "Realm"
end
UnitLevel = function()
    return 8
end
GetRealZoneText = function()
    return "Elwynn Forest"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and 1 or 0
    end,
    GetContainerItemInfo = function(bag)
        return bag == 0 and bolts > 0 and { itemID = 2996, hyperlink = bolt, stackCount = bolts } or nil
    end,
}
rawset(_G, "C_TradeSkillUI", {
    GetRecipeInfo = function(recipeID)
        return recipeID == 2963 and { name = "Bolt of Linen Cloth" } or nil
    end,
})

local addon = client.boot({}, load)
local key = assert(addon.Item.key(bolt, 2996))

clock = 1010
client.event("TRADE_SKILL_CRAFT_BEGIN", 2963)
clock = 1012
client.event("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 2996, hyperlink = bolt, quantity = 1 })
client.event("UPDATE_TRADESKILL_CAST_STOPPED")
clock, bolts = 1013, 1
client.event("BAG_UPDATE_DELAYED")

local record = addon.store:find(key)
assert(record and record.totalGained == 1, "a crafted item must count in Total gained")
local gain = record.gains[1]
assert(gain.method == "Crafted", "a crafted item must be credited as Crafted")
assert(gain.character == "Ada" and gain.place == "Elwynn Forest", "a craft is credited where the crafter made it")
assert(
    gain.context and gain.context.kind == "recipe" and gain.context.name == "Bolt of Linen Cloth",
    "a crafted item must name the recipe that made it"
)

-- A second cast after the first stopped must not inherit its recipe.
clock = 1020
client.event("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 2996, hyperlink = bolt, quantity = 1 })
clock, bolts = 1021, 2
client.event("BAG_UPDATE_DELAYED")
record = addon.store:find(key)
assert(record.totalGained == 2, "every crafted unit must count once")
assert(
    record.gains[2].method == "Crafted" and not record.gains[2].context,
    "a craft after the cast stopped must not name the earlier recipe"
)

-- Units credited to the recipe across a record's gains.
local function named(entry)
    local units = 0
    for _, each in ipairs(entry.gains) do
        if each.context and each.context.name == "Bolt of Linen Cloth" then
            units = units + each.quantity
        end
    end
    return units
end

-- The last cast of a queued batch stops before its result arrives, in the
-- order the Forever client traced it.
clock = 1030
client.event("TRADE_SKILL_CRAFT_BEGIN", 2963)
client.event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", 2963)
client.event("UPDATE_TRADESKILL_CAST_STOPPED")
client.event("CHAT_MSG_LOOT", "You create: " .. bolt .. ".")
client.event("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 2996, hyperlink = bolt, quantity = 1 })
clock, bolts = 1031, 3
client.event("BAG_UPDATE_DELAYED")
record = addon.store:find(key)
assert(record.totalGained == 3, "the last craft of a batch must count once")
assert(named(record) == 2, "the last craft of a batch must name its recipe")

-- Its result consumed the recipe, so a later result names none.
clock = 1040
client.event("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 2996, hyperlink = bolt, quantity = 1 })
clock, bolts = 1041, 4
client.event("BAG_UPDATE_DELAYED")
record = addon.store:find(key)
assert(record.totalGained == 4 and named(record) == 2, "a stopped batch's recipe must not outlive its last result")

print("craft_event_spec: passed")
