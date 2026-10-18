local load = assert(loadfile("tests/support/addon.lua"))()
local addon = {}
local link = "|Hitem:80::::::::|h[Soft Fur-lined Shoes]|h"
local otherLink = "|Hitem:81::::::::|h[Other Reward]|h"
local frame = { registered = {} }
local clock = 1000
local inBags = false

function frame:RegisterEvent(event)
    self.registered[event] = true
end

function frame:SetScript(name, handler)
    if name == "OnEvent" then
        self.onEvent = handler
    end
end

CreateFrame = function()
    return frame
end
GetBuildInfo = function()
    return "1.60.1", 70009, "date", 16001
end
GetLocale = function()
    return "enUS"
end
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
SlashCmdList = {}

load.addon("Main", addon)

local function event(name, ...)
    if frame.registered[name] then
        frame.onEvent(frame, name, ...)
    end
end

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
print("quest_event_spec: passed")
