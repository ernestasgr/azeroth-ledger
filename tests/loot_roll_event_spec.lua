local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
-- Group loot: a roll you win stands in for the loot window you may never have
-- opened. LOOT_ITEM_ROLL_WON names the item; the loot chat line may come
-- before or after it.
local cloak = "|cnIQ2:|Hitem:6449::::::::25:1491:::::::::|h[Glowing Lizardscale Cloak]|h|r"
local ring = "|cnIQ2:|Hitem:6448::::::::25:1491:::::::::|h[Tail Spike]|h|r"
local gem = "|cnIQ2:|Hitem:1210::::::::25:1491:::::::::|h[Shadowgem]|h|r"
local held = {}
local slots = { cloak, ring, gem }
local clock = 1000

GetServerTime = function()
    return clock
end
UnitName = function()
    return "Trise"
end
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

print("loot_roll_event_spec: passed")
