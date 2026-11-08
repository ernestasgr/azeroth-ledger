-- The bag update after a loot runs inside one frame, so its cost must follow
-- what changed, not how much unresolved evidence and Journal history the save
-- holds. In-client it measured 21 ms on average with 252 unresolved entries,
-- 250 vendor Journal rows and 43 carried items.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70862 })
local addon = {}
date = os.date

local fixture = assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))()
local clock = 5000
local raw = fixture(300)
raw.vendor.journal = { unpack(raw.vendor.journal, 1, 250) }
local unresolved = {}
for index = 1, 252 do
    unresolved[index] = {
        id = index,
        kind = "lootReceipt",
        reason = "unmatched",
        at = 1000 + index,
        character = "Fixture",
        realm = "Test",
        detail = { key = "10300:0", itemID = 10300, quantity = 1, kind = "loot" },
    }
end
raw.evidence = { nextID = 253, unresolved = unresolved, discarded = 0 }
local soldLink = "|Hitem:10299::::::::|h[Item 00299]|h"
raw.vendor.actions[1] = {
    id = 2001,
    kind = "sale",
    status = "confirmed",
    area = "bags",
    key = "10299:0",
    itemID = 10299,
    link = soldLink,
    quantity = 1,
    at = 4900,
    character = "Fixture",
    realm = "Test",
    level = 60,
    place = "Test zone",
    baseline = 1,
    baselineGained = 2,
    receiptQuantity = 0,
}
raw.vendor.nextID = 2002
AzerothLedgerDB = raw

local bags = {}
for index = 1, 43 do
    local itemID = 10000 + index
    bags[index] = {
        itemID = itemID,
        hyperlink = "|Hitem:" .. itemID .. "::::::::|h[Item " .. string.format("%05d", index) .. "]|h",
        stackCount = 1,
    }
end
local corpse

UnitName = function(unit)
    return unit == "player" and "Fixture" or nil
end
rawset(_G, "UnitGUID", function()
    return nil
end)
GetServerTime = function()
    return clock
end
GetRealmName = function()
    return "Test"
end
UnitLevel = function()
    return 60
end
GetRealZoneText = function()
    return "Test zone"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(container)
        return container == 0 and #bags or 0
    end,
    GetContainerItemInfo = function(container, slot)
        return container == 0 and bags[slot] or nil
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
rawset(_G, "GetNumLootItems", function()
    return 1
end)
rawset(_G, "GetLootSlotLink", function()
    return bags[1].hyperlink
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Item 00001", 1
end)
rawset(_G, "GetLootSourceInfo", function()
    return corpse, 1
end)

client.boot(addon, load)
local event = client.event

local function instructions(action)
    local count = 0
    debug.sethook(function()
        count = count + 100
    end, "", 100)
    action()
    debug.sethook()
    return count
end

local noopCost, bagCost
-- Corpses looted three seconds apart keep ten loot sessions live at once.
for index = 1, 10 do
    clock = clock + 3
    corpse = "Creature-0-6846-0-1-475-00000000" .. string.format("%02X", index)
    event("LOOT_READY", true)
    event("LOOT_OPENED", true, false)
    event("CHAT_MSG_LOOT", "You receive loot: " .. bags[1].hyperlink)
    event("LOOT_CLOSED")
    bags[1].stackCount = bags[1].stackCount + 1
    noopCost = instructions(function()
        event("BAG_UPDATE", 0)
    end)
    bagCost = instructions(function()
        event("BAG_UPDATE_DELAYED")
    end)
end
print("bag update instructions", bagCost, "no-op event instructions", noopCost)

local record = addon.store:find("10001:0")
local looted = 0
for _, gain in ipairs(record.gains) do
    if gain.method == "Looted" and gain.source and gain.source.guid:match("^Creature%-0%-6846") then
        looted = looted + gain.quantity
    end
end
assert(looted == 10, "every looted item must still be gained once with its corpse: " .. looted)
assert(#addon.store:unresolved() == 252, "a clean bag update must leave unresolved evidence as it found it")
assert(noopCost < 5000, "an event that changes nothing must not re-read the saved data: " .. noopCost)
assert(bagCost < 300000, "a bag update must cost what changed, not the size of the save: " .. bagCost)

-- Copies of a session share its pre-loot counts, so a save that fails partway
-- must not leave a later item's count in the session still on disk.
local failSave = false
local atomicRaw = fixture(3)
local atomic = addon.Schema.open(atomicRaw, function(value)
    if failSave then
        error("test save failure")
    end
    atomicRaw = value
end)
assert(atomic:setCharacter("Fixture", "Test"))
local kept = { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 1 }
local arriving = { itemID = 10002, link = "|Hitem:10002::::::::|h[Item 00002]|h", quantity = 1 }
local function checkBags(at, items)
    return atomic:scan({
        character = "Fixture",
        realm = "Test",
        area = "bags",
        seenAt = at,
        complete = true,
        items = items,
    })
end
assert(checkBags(1100, { kept }))
assert(
    atomic:command(
        "lootOpen",
        { slots = { { key = "10001:0", quantity = 1 } } },
        1101,
        { character = "Fixture", realm = "Test", level = 60, place = "Test zone" }
    )
)
failSave = true
assert(not pcall(checkBags, 1102, { kept, arriving }))
failSave = false
assert(
    atomicRaw.loot.sessions[1].baselineGains["10002:0"] == nil,
    "a failed save must leave the open loot session's pre-loot counts unchanged"
)
print("loot_bag_update_cost_spec: passed")
