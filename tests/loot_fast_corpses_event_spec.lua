-- Fast looting opens the next corpse before the last item reaches the bags.
-- A loot line already proves that window's item was taken, so the next corpse
-- showing the same item is not competing with it.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70790 })
local addon = {}
local clock = 1000
local candle = { id = 755, link = "|cnIQ1:|Hitem:755::::::::12:1482:::::::::|h[Melted Candle]|h|r" }
local firstCorpse = "Creature-0-6846-0-1-475-00000000A1"
local secondCorpse = "Creature-0-6846-0-1-475-00000000B2"
local bags = {}
local corpse

UnitName = function(unit)
    return unit == "player" and "Mara" or nil
end
rawset(_G, "UnitGUID", function()
    return nil
end)
GetServerTime = function()
    return clock
end
GetRealmName = function()
    return "CAMWOW EU5 Realm 10 RP"
end
UnitLevel = function()
    return 12
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
    return candle.link
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Melted Candle", 1
end)
rawset(_G, "GetLootSourceInfo", function()
    return corpse, 1
end)

load.addon("Main", addon)
local event = client.event
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")

local function take(guid, at)
    corpse, clock = guid, at
    event("LOOT_READY", true)
    event("LOOT_OPENED", true, false)
    event("LOOT_CLOSED")
    event("CHAT_MSG_LOOT", "You receive loot: " .. candle.link)
end

-- Both candles are taken before the bags report either of them.
take(firstCorpse, 1010)
take(secondCorpse, 1011)
clock = 1012
bags = { { item = candle, count = 2 } }
event("BAG_UPDATE_DELAYED")

local record = addon.store:find("755:0")
assert(record and record.totalGained == 2, "both candles must be gained exactly once")
local first, second = record.gains[1], record.gains[2]
assert(first.source and first.source.guid == firstCorpse, "the first corpse lost its source to the next corpse")
assert(second.source and second.source.guid == secondCorpse, "the next corpse lost its source to a taken item")
assert(addon.StoreRecordCheck.validRecord("755:0", record), "the record was rejected")
print("loot_fast_corpses_event_spec: passed")
