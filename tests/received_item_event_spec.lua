local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
-- Items the client hands over or makes outside the loot window, with the chat
-- lines Forever prints: "You receive item:" and "You create:".
local water = "|cnIQ1:|Hitem:5350::::::::5:1491:::::::::|h[Conjured Water]|h|r"
local bolt = "|cnIQ1:|Hitem:2996::::::::5:1491:::::::::|h[Bolt of Linen Cloth]|h|r"
local gift = "|cnIQ1:|Hitem:2723::::::::5:1491:::::::::|h[Bottle of Dalaran Noir]|h|r"
local letter = "|cnIQ1:|Hitem:2589::::::::5:1491:::::::::|h[Linen Cloth]|h|r"
local held = {}
local slots = { water, bolt, gift, letter }
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
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."

local addon = client.boot({}, load)
local event = client.event

local function gained(link)
    local record = addon.store:find(link:match("item:(%d+)") .. ":0")
    return record and record.totalGained or 0, record
end

local function land(link, units)
    held[link] = (held[link] or 0) + units
    event("BAG_UPDATE", 0)
    event("BAG_UPDATE_DELAYED")
end

-- A conjuring spell is not a recipe, so its chat line is the only receipt.
clock = 1010
event("CHAT_MSG_LOOT", "You create: " .. water .. "x2.")
land(water, 2)
local total, record = gained(water)
assert(total == 2, "conjured items are a confirmed gain")
assert(record.gains[1].method == "Crafted" and not record.gains[1].context, "a conjured item has no recipe")

-- A recipe prints the same line before its craft result; it counts once.
clock = 1020
event("TRADE_SKILL_CRAFT_BEGIN", 2963)
event("CHAT_MSG_LOOT", "You create: " .. bolt .. ".")
event("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 2996, hyperlink = bolt, quantity = 1 })
land(bolt, 1)
event("TRADE_SKILL_CLOSE")
assert(gained(bolt) == 1, "a crafted item counts once")
assert(addon.store:find("2996:0").gains[1].context.id == 2963, "the craft result names the recipe")

-- Mail prints "You receive item:" too; the mailbox owns that take.
clock = 1030
event("MAIL_SHOW")
event("CHAT_MSG_LOOT", "You receive item: " .. letter .. "x5.")
land(letter, 5)
event("MAIL_CLOSED")
assert(gained(letter) == 0, "an open mailbox explains an item handed over")

-- So does a quest that just closed.
clock = 1040
event("QUEST_COMPLETE")
event("QUEST_FINISHED")
clock = 1043
event("CHAT_MSG_LOOT", "You receive item: " .. gift .. ".")
land(gift, 1)
assert(gained(gift) == 0, "a quest window explains an item handed over")

-- Outside any window an item handed over came from an NPC or another item.
clock = 1100
event("CHAT_MSG_LOOT", "You receive item: " .. gift .. ".")
land(gift, 1)
total, record = gained(gift)
assert(total == 1, "an item handed over outside a window is a confirmed gain")
assert(record.gains[#record.gains].method == "Obtained", "an item handed over is Obtained")

print("received_item_event_spec: passed")
