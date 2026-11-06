local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
-- Group loot: a roll you win stands in for the loot window you may never have
-- opened. LOOT_ITEM_ROLL_WON names the item; the loot chat line may come
-- before or after it.
local cloak = "|cnIQ2:|Hitem:6449::::::::25:1491:::::::::|h[Glowing Lizardscale Cloak]|h|r"
local ring = "|cnIQ2:|Hitem:6448::::::::25:1491:::::::::|h[Tail Spike]|h|r"
local gem = "|cnIQ2:|Hitem:1210::::::::25:1491:::::::::|h[Shadowgem]|h|r"
local boots = "|cnIQ2:|Hitem:6482::::::::25:1491:::::::::|h[Firewalker Boots]|h|r"
local staff = "|cnIQ2:|Hitem:6505::::::::25:1491:::::::::|h[Crescent Staff]|h|r"
local held = {}
local slots = { cloak, ring, gem, boots, staff }
local corpse = "Creature-0-4170-43-1-3671-000012AB34"
local otherCorpse = "Creature-0-4170-43-1-3669-000012AB99"
local window, targetGUID = {}, nil
local clock = 1000

GetServerTime = function()
    return clock
end
UnitName = function(unit)
    return unit == "target" and targetGUID and "Lady Anacondra" or "Trise"
end
rawset(_G, "UnitGUID", function(unit)
    return unit == "target" and targetGUID or nil
end)
rawset(_G, "GetNumLootItems", function()
    return #window
end)
rawset(_G, "GetLootSlotLink", function(slot)
    return window[slot] and window[slot].link
end)
rawset(_G, "GetLootSlotInfo", function(slot)
    return nil, window[slot] and window[slot].link:match("%[(.-)%]"), 1
end)
rawset(_G, "GetLootSourceInfo", function(slot)
    return window[slot].guid, 1
end)
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 22
end
GetRealZoneText = function()
    return "Wailing Caverns"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and #slots or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local link = bag == 0 and slots[slot] or nil
        if not link or not held[link] or held[link] < 1 then
            return nil
        end
        return { itemID = tonumber(link:match("item:(%d+)")), hyperlink = link, stackCount = held[link] }
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."

local addon = client.boot({}, load)
local event = client.event

local function gained(link)
    local record = addon.store:find(link:match("item:(%d+)") .. ":0")
    return record and record.totalGained or 0, record
end

local function land(link)
    held[link] = (held[link] or 0) + 1
    event("BAG_UPDATE", 0)
    event("BAG_UPDATE_DELAYED")
end

clock = 1010
event("LOOT_ITEM_ROLL_WON", cloak, 1, 1, 87, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. cloak .. ".")
land(cloak)
local total, record = gained(cloak)
assert(total == 1, "a roll you won is confirmed loot")
assert(record.gains[1].method == "Looted", "a roll you won is Looted")

clock = 1100
event("CHAT_MSG_LOOT", "You receive loot: " .. ring .. ".")
event("LOOT_ITEM_ROLL_WON", ring, 1, 2, 54, false)
land(ring)
assert(gained(ring) == 1, "the roll may be reported after its loot line")

-- With no window and no roll, a loot line alone still proves nothing.
clock = 1200
event("CHAT_MSG_LOOT", "You receive loot: " .. gem .. ".")
land(gem)
assert(gained(gem) == 0, "a loot line with no window or roll stays unconfirmed")

-- A roll you won keeps the source of the loot window that showed the item.
local function lootWindow(guid, link)
    window, targetGUID = { { link = link, guid = guid } }, guid
    event("LOOT_READY", false)
    event("LOOT_OPENED", false)
    event("LOOT_CLOSED")
    window, targetGUID = {}, nil
end

clock = 1300
lootWindow(corpse, boots)
clock = 1340
event("LOOT_ITEM_ROLL_WON", boots, 1, 1, 91, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. boots .. ".")
land(boots)
local bootsTotal, bootsRecord = gained(boots)
assert(bootsTotal == 1, "a roll after its loot window is confirmed loot")
local from = bootsRecord.gains[1].source
assert(from and from.kind == "mob" and from.guid == corpse, "a roll you won keeps its loot window's source")
assert(from.name == "Lady Anacondra", "a roll you won keeps its loot window's source name")

-- Two corpses showing the same item cannot say which one the roll was for.
clock = 1400
lootWindow(corpse, staff)
lootWindow(otherCorpse, staff)
clock = 1420
event("LOOT_ITEM_ROLL_WON", staff, 1, 1, 77, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. staff .. ".")
land(staff)
local staffTotal, staffRecord = gained(staff)
assert(staffTotal == 1, "an ambiguous roll is still confirmed loot")
assert(staffRecord.gains[1].source == nil, "a roll seen in two windows has no single source")

print("loot_roll_event_spec: passed")
