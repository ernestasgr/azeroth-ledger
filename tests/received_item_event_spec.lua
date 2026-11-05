local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
-- Items the client hands over or makes outside the loot window, with the chat
-- lines Forever prints: "You receive item:" and "You create:".
local water = "|cnIQ1:|Hitem:5350::::::::5:1491:::::::::|h[Conjured Water]|h|r"
local bolt = "|cnIQ1:|Hitem:2996::::::::5:1491:::::::::|h[Bolt of Linen Cloth]|h|r"
local gift = "|cnIQ1:|Hitem:2723::::::::5:1491:::::::::|h[Bottle of Dalaran Noir]|h|r"
local letter = "|cnIQ1:|Hitem:2589::::::::5:1491:::::::::|h[Linen Cloth]|h|r"
local muffin = "|cnIQ1:|Hitem:5349::::::::5:1491:::::::::|h[Conjured Muffin]|h|r"
local scroll = "|cnIQ1:|Hitem:1181::::::::5:1491:::::::::|h[Scroll of Spirit]|h|r"
local held = {}
local slots = { water, bolt, gift, letter, muffin, scroll }
local spells = { [587] = "Conjure Food", [1229001] = "Comprehend Scroll" }
C_Spell = {
    GetSpellName = function(id)
        return spells[id]
    end,
}
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
assert(not record.gains[#record.gains].context, "an item handed over with no cast names no spell")

-- The spell you just cast made the item: a conjured stack or a scroll.
clock = 1200
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 587)
event("CHAT_MSG_LOOT", "You create: " .. muffin .. "x2.")
land(muffin, 2)
total, record = gained(muffin)
local context = record and record.gains[1].context
assert(total == 2 and record.gains[1].method == "Crafted", "a conjured item is Crafted")
assert(context and context.kind == "spell" and context.id == 587, "a conjured item names its spell")
assert(context.name == "Conjure Food", "the conjuring spell is named")

clock = 1300
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 1229001)
clock = 1301
event("CHAT_MSG_LOOT", "You receive item: " .. scroll .. ".")
land(scroll, 1)
total, record = gained(scroll)
context = record and record.gains[1].context
assert(total == 1 and record.gains[1].method == "Obtained", "a scroll from a spell is Obtained")
assert(context and context.kind == "spell" and context.name == "Comprehend Scroll", "a scroll names its spell")

-- A purchase never casts, so a scroll made beside an open merchant is the spell's.
local evocation = "|cnIQ1:|Hitem:213564::::::::11:1482:::::::::|h[Scroll of Minor Evocation]|h|r"
slots[#slots + 1] = evocation
clock = 1350
event("MERCHANT_SHOW")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 1296017)
spells[1296017] = "Comprehend Scroll"
event("CHAT_MSG_LOOT", "You receive item: " .. evocation .. ".")
land(evocation, 1)
event("MERCHANT_CLOSED")
total, record = gained(evocation)
context = record and record.gains[1] and record.gains[1].context
assert(total == 1, "a scroll made beside an open merchant is a confirmed gain")
assert(context and context.name == "Comprehend Scroll", "a scroll made beside an open merchant names its spell")

-- A cast long before the item, or by someone else, did not make it.
clock = 1400
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 1229001)
event("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-4", 587)
clock = 1460
event("CHAT_MSG_LOOT", "You receive item: " .. gift .. ".")
land(gift, 1)
record = select(2, gained(gift))
assert(not record.gains[#record.gains].context, "an old cast does not name an item handed over later")

-- The spell context survives a save and reload.
assert(addon.store:diagnostic().kind == "healthy", "a spell context left the save unhealthy")

print("received_item_event_spec: passed")
