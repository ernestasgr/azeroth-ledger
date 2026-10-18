local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
local addon = {}
local link = "|Hitem:11475::::::::|h[Wine-stained Cloak]|h"
local clock = 1000
local inBags = false
local equipped = false
local linkReady = false

GetServerTime = function()
    return clock
end
UnitName = function()
    return "Nora"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 12
end
GetRealZoneText = function()
    return "Elwynn Forest"
end
GetInventoryItemLink = function(_, slot)
    return equipped and slot == 15 and link or nil
end
C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and 1 or 0
    end,
    GetContainerItemInfo = function(bag)
        if bag == 0 and inBags then
            return { itemID = 11475, hyperlink = link, stackCount = 1 }
        end
    end,
}
local questAPI = {
    C_QuestLog = {
        GetTitleForQuestID = function()
            return "A Cloak Reward"
        end,
    },
    GetQuestID = function()
        return 42
    end,
    GetNumQuestChoices = function()
        return 1
    end,
    GetNumQuestRewards = function()
        return 0
    end,
    GetQuestItemLink = function()
        return linkReady and link or nil
    end,
    GetQuestItemInfo = function()
        return "Wine-stained Cloak", nil, 1
    end,
}
for name, implementation in pairs(questAPI) do
    rawset(_G, name, implementation)
end

load.addon("Main", addon)

local event = client.event

event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")
clock = 1010
event("QUEST_COMPLETE")
clock = 1011
event("QUEST_TURNED_IN", 42)
clock = 1012
inBags = true
event("BAG_UPDATE_DELAYED")
clock = 1013
inBags = false
equipped = true
event("PLAYER_EQUIPMENT_CHANGED", 15)
clock = 1014
linkReady = true
event("QUEST_LOOT_RECEIVED", 42, link, 1)
clock = 1015
event("BAG_UPDATE_DELAYED")

local record = addon.store:find(addon.Item.key(link, 11475))
assert(record and record.totalGained == 1, "Wine-stained Cloak remained Seen with Total gained 0")
assert(record.gains[1].method == "Quest")
assert(record.firstSeenUnits == 0 and addon.store:breakdown(record.key).recorded == 1)
print("quest_delayed_event_spec: passed")
