-- Replays opening a Treat Bag from the bags in a Forever trace (build
-- 1.60.1.70450): the loot source is the opened item, not a creature or object.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70450 })
local addon = {}
local clock = 1000
local bag = { id = 20393, link = "|cnIQ1:|Hitem:20393::::::::6:1490:::::::::|h[Treat Bag]|h|r" }
local wand = { id = 20409, link = "|cnIQ1:|Hitem:20409::::::::6:1490:::::::::|h[Hallowed Wand - Ghost]|h|r" }
local bagGUID = "Item-4618-0-40000A1B2C3D4E5F"
local bags = { { item = bag, count = 1 } }
local opened = true

GetServerTime = function()
    return clock
end
UnitName = function()
    return "Kimberdra"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 6
end
GetRealZoneText = function()
    return "Elwynn Forest"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(container)
        return container == 0 and 2 or 0
    end,
    GetContainerItemInfo = function(container, slot)
        local entry = container == 0 and bags[slot]
        return entry and { itemID = entry.item.id, hyperlink = entry.item.link, stackCount = entry.count } or nil
    end,
}
C_Item = {
    GetItemLinkByGUID = function(guid)
        return opened and guid == bagGUID and bag.link or nil
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
rawset(_G, "GetNumLootItems", function()
    return 1
end)
rawset(_G, "GetLootSlotLink", function()
    return wand.link
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Hallowed Wand - Ghost", 1
end)
rawset(_G, "GetLootSourceInfo", function()
    return bagGUID, 1
end)
rawset(_G, "UnitGUID", function()
    return nil
end)

load.addon("Main", addon)
local event = client.event
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")

-- The bag is used up as the window closes; the wand lands a second later.
clock = 1505
event("LOOT_READY", false)
event("LOOT_OPENED", false, false)
event("LOOT_CLOSED")
event("LOOT_CLOSED")
event("CHAT_MSG_LOOT", "You receive loot: " .. wand.link)
bags = {}
event("BAG_UPDATE_DELAYED")
clock = 1506
bags = { { item = wand, count = 1 } }
event("BAG_UPDATE_DELAYED")

local record = assert(addon.store:find("20409:0"), "the wand from the Treat Bag was not recorded")
assert(record.totalGained == 1, "the wand from the Treat Bag was not counted")
local gain = record.gains[1]
assert(gain.method == "Looted", "the wand from the Treat Bag was not Looted")
assert(gain.source, "the Treat Bag was not kept as the wand's source")
assert(gain.source.kind == "item" and gain.source.guid == bagGUID, "the source was not the opened item")
assert(gain.source.itemID == 20393 and gain.source.name == "Treat Bag", "the opened item was not named")
local Wording = addon.LastSeen
assert(Wording.gainSourceText(gain) == "Treat Bag", "the source did not read as the opened item")
local key, neutral = Wording.sourceIdentity(gain)
assert(key == "item:20393" and neutral == "Item #20393", "Treat Bags opened from different stacks were not one source")

-- An opened item the client can no longer describe is still a known source.
clock, opened = 1600, false
bags = { { item = wand, count = 1 }, { item = bag, count = 1 } }
event("BAG_UPDATE_DELAYED")
event("LOOT_READY", false)
event("CHAT_MSG_LOOT", "You receive loot: " .. wand.link)
event("LOOT_CLOSED")
bags = { { item = wand, count = 2 } }
event("BAG_UPDATE_DELAYED")
record = addon.store:find("20409:0")
assert(record.totalGained == 2, "the second wand was not counted")
local unnamed = record.gains[2]
assert(unnamed.source and unnamed.source.kind == "item" and unnamed.source.itemID == nil, "the unnamed bag was lost")
assert(Wording.gainSourceText(unnamed) == "Unnamed item", "an unnamed opened item did not read as one")

assert(addon.StoreRecordCheck.validRecord("20409:0", record), "a save with an opened-item source was rejected")
print("loot_opened_item_event_spec: passed")
