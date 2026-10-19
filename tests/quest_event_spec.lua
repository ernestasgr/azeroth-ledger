local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
local addon = {}
local link = "|Hitem:80::::::::|h[Soft Fur-lined Shoes]|h"
local otherLink = "|Hitem:81::::::::|h[Other Reward]|h"
local clock = 1000
local inBags = false

GetServerTime = function()
    return clock
end
UnitName = function(_unit)
    return "Ada"
end
GetRealmName = function()
    return "Realm"
end
UnitLevel = function(_unit)
    return 12
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
        return bag == 0 and inBags and { itemID = 80, hyperlink = link, stackCount = 1 } or nil
    end,
}
_G.C_QuestLog = {
    GetTitleForQuestID = function()
        return "A Quest"
    end,
}
_G.GetQuestID = function()
    return 42
end
_G.GetNumQuestRewards = function()
    return 0
end
_G.GetNumQuestChoices = function()
    return 2
end
_G.GetQuestItemLink = function(kind, index)
    if kind ~= "choice" then
        return nil
    end
    return index == 1 and link or otherLink
end
_G.GetQuestItemInfo = function(kind)
    return kind == "choice" and "Reward" or nil, nil, 1
end

load.addon("Main", addon)

local event = client.event

event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")
clock = 1010
event("QUEST_COMPLETE")
event("QUEST_TURNED_IN", 42)
clock = 1011
inBags = true
event("BAG_UPDATE_DELAYED")

local record = addon.store:find(addon.Item.key(link, 80))
assert(record and record.totalGained == 1, "Soft Fur-lined Shoes remained Seen with Total gained 0")
assert(record.gains[1].method == "Quest")
assert(#addon.store:unresolved() == 0)

-- The reward window's links carry a preview bonus ID the received item does
-- not. Receiving one choice settles the whole offer: nothing is left to review.
local shoes = "|cnIQ1:|Hitem:80::::::::2:1490::11:::::::|h[Soft Fur-lined Shoes]|h|r"
local previews = {
    "|cnIQ1:|Hitem:6070::::::::2:1490::11:1:3524::::::|h[Wolfskin Bracers]|h|r",
    "|cnIQ1:|Hitem:80::::::::2:1490::11:1:3524::::::|h[Soft Fur-lined Shoes]|h|r",
}
assert(addon.Item.key(previews[2], 80) == "80:0:3524")
rawset(_G, "GetQuestID", function()
    return 33
end)
rawset(_G, "GetQuestItemLink", function(kind, index)
    return kind == "choice" and previews[index] or nil
end)
inBags = false
link = shoes
clock = 1100
event("BAG_UPDATE_DELAYED")
local before = addon.store:find("80:0").totalGained
event("QUEST_COMPLETE")
clock = 1104
event("QUEST_LOOT_RECEIVED", 33, shoes, 1)
event("QUEST_TURNED_IN", 33)
inBags = true
event("BAG_UPDATE_DELAYED")
event("QUEST_FINISHED")
assert(addon.store:find("80:0").totalGained == before + 1, "the chosen reward was not counted")
clock = 1800
event("BAG_UPDATE_DELAYED")
assert(#addon.store:unresolved() == 0, "a received choice reward left its offer to review")

print("quest_event_spec: passed")
