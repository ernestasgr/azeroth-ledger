-- Mining, herb gathering and opening are casts at the object; UNIT_SPELLCAST_SENT
-- names its target, so the loot that follows the cast keeps that name.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70450 })
local addon = {}
local clock = 1000
local ore = { id = 2770, link = "|cnIQ1:|Hitem:2770::::::::6:1490:::::::::|h[Copper Ore]|h|r" }
local veinGUID = "GameObject-0-6782-0-2-1731-544C854BB2"
local bags = {}

GetServerTime = function()
    return clock
end
UnitName = function(unit)
    return unit == "target" and "Hogger" or "Kimberdra"
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
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
rawset(_G, "GetNumLootItems", function()
    return 1
end)
rawset(_G, "GetLootSlotLink", function()
    return ore.link
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Copper Ore", 1
end)
rawset(_G, "GetLootSourceInfo", function()
    return veinGUID, 1
end)
rawset(_G, "UnitGUID", function()
    return nil
end)

load.addon("Main", addon)
local event = client.event
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")

local function mine(count)
    event("LOOT_READY", false)
    event("LOOT_OPENED", false, false)
    event("CHAT_MSG_LOOT", "You receive loot: " .. ore.link)
    event("LOOT_CLOSED")
    bags = { { item = ore, count = count } }
    event("BAG_UPDATE_DELAYED")
    return addon.store:find("2770:0").gains[count]
end

-- A finished Mining cast names the vein the loot comes from.
clock = 1500
event("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-3-1-1-1-2575-0001", 2575)
clock = 1502
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-2575-0001", 2575)
local gain = mine(1)
assert(gain.source and gain.source.guid == veinGUID, "the vein was not kept as the ore's source")
assert(gain.source.name == "Copper Vein", "the Mining cast did not name the vein")
assert(addon.LastSeen.gainSourceText(gain) == "Copper Vein", "the source did not read as the vein")

-- A cast that failed proves nothing about the next loot.
clock = 1600
event("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-3-1-1-1-2575-0002", 2575)
event("UNIT_SPELLCAST_FAILED", "player", "Cast-3-1-1-1-2575-0002", 2575)
assert(mine(2).source.name == nil, "a failed cast named the loot")

-- A cast finished long before the loot is not its source.
clock = 1700
event("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-3-1-1-1-2575-0003", 2575)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-2575-0003", 2575)
clock = 1720
assert(mine(3).source.name == nil, "a stale cast named the loot")

-- A spell cast at a unit names that unit, not the object looted after it.
clock = 1800
event("UNIT_SPELLCAST_SENT", "player", "Hogger", "Cast-3-1-1-1-133-0004", 133)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-133-0004", 133)
assert(mine(4).source.name == nil, "a cast at the target named the loot")

-- The name belongs to one loot window only.
clock = 1900
event("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-3-1-1-1-2575-0005", 2575)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-2575-0005", 2575)
assert(mine(5).source.name == "Copper Vein", "the second Mining cast did not name the vein")
assert(mine(6).source.name == nil, "a used cast named a later loot window")

assert(addon.StoreRecordCheck.validRecord("2770:0", addon.store:find("2770:0")), "a cast-named source was rejected")
print("loot_cast_name_event_spec: passed")
