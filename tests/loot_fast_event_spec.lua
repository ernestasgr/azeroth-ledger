-- Replays fast looting from a Forever trace (build 1.60.1.70450): the next
-- corpse opens before the previous corpse's items reach the bags.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70450 })
local addon = {}
local clock = 1000
local items = {
    bleu = { id = 2070, link = "|cnIQ1:|Hitem:2070::::::::4:1490:::::::::|h[Darnassian Bleu]|h|r" },
    belt = { id = 1369, link = "|cnIQ0:|Hitem:1369::::::::4:1490:::::::::|h[Ragged Leather Belt]|h|r" },
    linen = { id = 2589, link = "|cnIQ1:|Hitem:2589::::::::4:1490:::::::::|h[Linen Cloth]|h|r" },
}
local bags = {}
local window = {}
local corpse = "Creature-0-4615-0-4-38-F35E8A3C7C"

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
    return 4
end
GetRealZoneText = function()
    return "Elwynn Forest"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and 4 or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bag == 0 and bags[slot]
        return entry and { itemID = entry.item.id, hyperlink = entry.item.link, stackCount = entry.count } or nil
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
rawset(_G, "GetNumLootItems", function()
    return #window
end)
rawset(_G, "GetLootSlotLink", function(slot)
    return window[slot] and window[slot].link
end)
rawset(_G, "GetLootSlotInfo", function(slot)
    return nil, "Loot item", window[slot] and 1 or 0
end)
rawset(_G, "GetLootSourceInfo", function()
    return corpse, 1
end)
rawset(_G, "UnitGUID", function()
    return corpse
end)

load.addon("Main", addon)
local event = client.event
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")

local function receive(item)
    event("CHAT_MSG_LOOT", "You receive loot: " .. item.link)
end

-- First corpse: the receipts arrive, but the bags have not changed yet.
clock = 1241
window = { items.bleu, items.belt, items.linen }
event("LOOT_READY", false)
event("LOOT_OPENED", false, false)
receive(items.bleu)
receive(items.belt)
event("LOOT_CLOSED")
receive(items.linen)
event("BAG_UPDATE_DELAYED")

-- Second corpse opens; only then do the first corpse's items land.
clock = 1243
corpse = "Creature-0-4615-0-4-38-F35E8A3C7D"
window = { items.linen }
event("LOOT_READY", false)
event("LOOT_OPENED", false, false)
receive(items.linen)
bags = { { item = items.bleu, count = 1 }, { item = items.belt, count = 1 }, { item = items.linen, count = 2 } }
event("BAG_UPDATE_DELAYED")
event("LOOT_CLOSED")

for name, expected in pairs({ bleu = 1, belt = 1, linen = 2 }) do
    local record = addon.store:find(items[name].id .. ":0")
    assert(record and record.totalGained == expected, name .. " was not counted after the next corpse opened")
end

clock = 1400
event("BAG_UPDATE_DELAYED")
assert(#addon.store:unresolved() == 0, "fast looting left gains to review")

print("loot_fast_event_spec: passed")
