local addon = {}
assert(loadfile("AzerothLedger/Item.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Work.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Schema.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Loot.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Collection.lua"))("AzerothLedger", addon)
date = os.date

local function equal(expected, actual)
    assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
end

local saved
local store = addon.Schema.open(nil, function(value)
    saved = value
end)

local plain = "|cff00ff00|Hitem:2672::::::::|h[Meat]|h|r"
local enchanted = "|cff00ff00|Hitem:2672:123:456::::::|h[Meat]|h|r"
local bear = "|cffa335ee|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h|r"
local bearGemmed = "|cffa335ee|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h|r"
local wolf = "|cffa335ee|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h|r"

local function scan(character, realm, area, seenAt, complete, items)
    assert(store:scan({
        character = character,
        realm = realm,
        area = area,
        seenAt = seenAt,
        complete = complete,
        items = items,
    }))
end

scan("Ada", "Realm A", "bags", 1000, true, { { itemID = 2672, link = plain, quantity = 400 } })
equal(1, #store:list())
local meat = store:list()[1]
equal(400, meat.firstSeenUnits)
equal(0, meat.totalGained)
equal(nil, meat.firstGained)
equal(nil, meat.lastGained)
equal(1000, meat.firstSeen)
equal(400, meat.observations[1].quantity)
scan("Ada", "Realm A", "bags", 1000, true, { { itemID = 2672, link = plain, quantity = 400 } })
equal(1, #store:list()[1].observations)
scan("Ada", "Realm A", "bank", 1100, false, {})
equal(false, store:area("Ada", "Realm A", "bank").complete)
equal(1, #store:list()[1].observations)
scan("Ada", "Realm A", "bags", 1200, true, { { itemID = 2672, link = enchanted, quantity = 399 } })
meat = store:list()[1]
equal(2, #meat.links)
equal(1200, meat.lastSeen)
equal(2, #meat.observations)

scan("Ada", "Realm A", "equipped", 1300, true, { { itemID = 100, link = bear, quantity = 1 } })
scan("Ben", "Realm B", "equipped", 1400, true, {
    { itemID = 100, link = bearGemmed, quantity = 1 },
    { itemID = 100, link = wolf, quantity = 1 },
})
equal(3, #store:list())
local variants = {}
for _, record in ipairs(store:list()) do
    if record.itemID == 100 then
        variants[#variants + 1] = record
    end
end
equal(2, #variants)
local shared = variants[1].firstSeen == 1300 and variants[1] or variants[2]
equal(2, #shared.links)
equal(2, #shared.characters)
equal(1, shared.firstSeenUnits)
equal(0, shared.totalGained)

local restored = addon.Schema.open(saved, function(value)
    saved = value
end)
equal(3, #restored:list())
equal(2, #restored:find(shared.key).characters)
equal(false, restored:area("Ada", "Realm A", "bank").complete)

print("collection_spec: passed")

local ownership = addon.Schema.open(nil, function() end)
local function check(character, area, at, complete, quantity)
    local items = quantity > 0 and { { itemID = 2672, link = plain, quantity = quantity } } or {}
    assert(ownership:scan({
        character = character,
        realm = "Realm A",
        area = area,
        seenAt = at,
        complete = complete,
        items = items,
    }))
end
local function visible(character, expected)
    local lines = addon.Collection.lines(ownership, "Ada", "Realm A", character, "Realm A")
    local joined = table.concat(lines, "\n")
    assert(joined:find(expected, 1, true), joined)
end
local function status(character, expected)
    visible(character, "Ownership: " .. expected)
end
check("Ada", "bags", 6000, true, 1)
check("Ada", "bank", 6000, true, 0)
check("Ada", "equipped", 6000, true, 0)
status("Ada", "Present")
check("Ada", "bags", 6010, true, 0)
check("Ada", "bank", 6010, true, 1)
status("Ada", "Present")
check("Ada", "bank", 6020, true, 0)
check("Ada", "equipped", 6020, true, 1)
status("Ada", "Present")
check("Ada", "equipped", 6030, true, 0)
check("Ada", "bags", 6030, true, 1)
status("Ada", "Present")
assert(ownership:list()[1].totalGained == 0)
assert(#ownership:list() == 1)
check("Ada", "bags", 6040, true, 0)
status("Ada", "Unknown")
check("Ada", "bank", 6040, true, 0)
check("Ada", "equipped", 6040, true, 0)
status("Ada", "Historical only")
visible("Ada", "Latest area check 0")
check("Ada", "bank", 6050, false, 0)
status("Ada", "Unknown")
visible("Ada", "Latest area check Unknown")
check("Ada", "bank", 6060, false, 2)
status("Ada", "Present")
visible("Ada", "Latest area check 2")
check("Ada", "bank", 6070, false, 0)
status("Ada", "Unknown")

print("ownership_spec: passed")

local lootSaved
local lootStore = addon.Schema.open(nil, function(value)
    lootSaved = value
end)
local lootLink = "|Hitem:4865::::::::|h[Ruined Pelt]|h"
local lootKey = addon.Item.key(lootLink, 4865)
local receiptAPI = {
    LOOT_ITEM_SELF = "You receive loot: %s.",
    LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
}
local receipt = addon.Loot.receipt(receiptAPI, "You receive loot: " .. lootLink .. "x2.")
equal(2, receipt.quantity)
equal(nil, addon.Loot.receipt(receiptAPI, "Someone receives loot: " .. lootLink .. "."))
local slots = addon.Loot.open({
    GetNumLootItems = function()
        return 1
    end,
    GetLootSlotLink = function()
        return lootLink
    end,
    GetLootSourceInfo = function()
        return "Creature-0-0-0-0-42-1", 2
    end,
    UnitGUID = function()
        return "Creature-0-0-0-0-42-1"
    end,
    UnitName = function()
        return "Forest Wolf"
    end,
})
equal("Forest Wolf", slots[1].source.name)
local ambiguousSlots = addon.Loot.open({
    GetNumLootItems = function()
        return 1
    end,
    GetLootSlotLink = function()
        return lootLink
    end,
    GetLootSlotInfo = function()
        return nil, nil, 3
    end,
    GetLootSourceInfo = function()
        return "Creature-0-0-0-0-42-1", 1, "Creature-0-0-0-0-43-1", 1
    end,
})
equal(nil, ambiguousSlots[1].source)
assert(
    lootStore:scan({ character = "Ada", realm = "Realm", area = "bags", seenAt = 2000, complete = true, items = {} })
)
assert(lootStore:lootOpen({
    character = "Ada",
    realm = "Realm",
    at = 2010,
    level = 12,
    place = "Elwynn Forest",
    slots = { { key = lootKey } },
}))
assert(lootStore:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 2011,
    complete = true,
    items = { { itemID = 4865, link = lootLink, quantity = 2 } },
}))
equal(0, lootStore:find(lootKey).totalGained)
assert(lootStore:lootReceipt(receipt, 2012, { character = "Ada", realm = "Realm" }))
local lootRecord = lootStore:find(lootKey)
equal(0, lootRecord.firstSeenUnits)
equal(0, lootRecord.characters[1].firstSeenUnits)
equal(2, lootRecord.totalGained)
equal(2, lootRecord.firstSeenUnits + lootRecord.totalGained)
equal(2011, lootRecord.firstSeen)
equal(2012, lootRecord.firstGained)
local foundUnknownSource = false
for _, line in ipairs(addon.Collection.lines(lootStore, "Ada", "Realm")) do
    if line:find("source Unknown", 1, true) then
        foundUnknownSource = true
    end
end
assert(foundUnknownSource)
equal(nil, lootRecord.gains[1].source)
equal("Elwynn Forest", lootRecord.gains[1].place)
local restoredLoot = addon.Schema.open(lootSaved, function(value)
    lootSaved = value
end)
assert(not restoredLoot:lootReceipt(receipt, 2013, { character = "Ada", realm = "Realm" }))
assert(restoredLoot:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 2014,
    complete = true,
    items = { { itemID = 4865, link = lootLink, quantity = 2 } },
}))
equal(2, restoredLoot:find(lootKey).totalGained)
equal(1, #restoredLoot:find(lootKey).gains)

local partial = addon.Schema.open(nil, function() end)
assert(partial:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 3000,
    complete = true,
    items = { { itemID = 4865, link = lootLink, quantity = 5 } },
}))
assert(partial:lootOpen({
    character = "Ada",
    realm = "Realm",
    at = 3010,
    level = 12,
    place = "Elwynn Forest",
    slots = { { key = lootKey } },
}))
local one = addon.Loot.receipt(receiptAPI, "You receive loot: " .. lootLink .. ".")
assert(partial:lootReceipt(one, 3011, { character = "Ada", realm = "Realm" }))
assert(partial:lootReceipt(one, 3011, { character = "Ada", realm = "Realm" }))
assert(partial:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 3012,
    complete = true,
    items = { { itemID = 4865, link = lootLink, quantity = 6 } },
}))
equal(1, partial:find(lootKey).totalGained)
equal(5, partial:find(lootKey).firstSeenUnits)
equal(6, partial:find(lootKey).firstSeenUnits + partial:find(lootKey).totalGained)

local delayed = addon.Schema.open(nil, function() end)
local function delayedBags(at, units)
    assert(delayed:scan({
        character = "Ada",
        realm = "Realm",
        area = "bags",
        seenAt = at,
        complete = true,
        items = { { itemID = 4865, link = lootLink, quantity = units } },
    }))
end
delayedBags(4000, 5)
assert(delayed:lootOpen({
    character = "Ada",
    realm = "Realm",
    at = 4010,
    level = 12,
    place = "Elwynn Forest",
    slots = { { key = lootKey, quantity = 1 } },
}))
delayedBags(4150, 6)
assert(not delayed:lootClose(4151))
assert(not delayed:lootClose(4152))
assert(delayed:lootOpen({
    character = "Ada",
    realm = "Realm",
    at = 4153,
    level = 12,
    place = "Elwynn Forest",
    slots = { { key = lootKey, quantity = 1 } },
}))
assert(not delayed:lootReceipt(one, 4154, { character = "Ben", realm = "Realm" }))
assert(delayed:lootReceipt(one, 4154, { character = "Ada", realm = "Realm" }))
equal(0, delayed:find(lootKey).totalGained)
delayedBags(4155, 6)
assert(delayed:lootReceipt(one, 4156, { character = "Ada", realm = "Realm" }))
equal(0, delayed:find(lootKey).totalGained)
equal(0, #delayed:find(lootKey).gains)

local twoWindow = addon.Schema.open(nil, function() end)
local function twoWindowBags(at, units)
    assert(twoWindow:scan({
        character = "Ada",
        realm = "Realm",
        area = "bags",
        seenAt = at,
        complete = true,
        items = { { itemID = 4865, link = lootLink, quantity = units } },
    }))
end
twoWindowBags(5000, 5)
assert(twoWindow:lootOpen({
    character = "Ada",
    realm = "Realm",
    at = 5010,
    level = 12,
    place = "Elwynn Forest",
    slots = { { key = lootKey, quantity = 1 } },
}))
twoWindowBags(5011, 7)
assert(twoWindow:lootReceipt(one, 5012, { character = "Ada", realm = "Realm" }))
equal(1, twoWindow:find(lootKey).totalGained)
assert(twoWindow:lootClose(5013))
assert(twoWindow:lootOpen({
    character = "Ada",
    realm = "Realm",
    at = 5014,
    level = 12,
    place = "Elwynn Forest",
    slots = { { key = lootKey, quantity = 1 } },
}))
twoWindowBags(5015, 8)
assert(twoWindow:lootReceipt(one, 5016, { character = "Ada", realm = "Realm" }))
equal(2, twoWindow:find(lootKey).totalGained)
equal(2, #twoWindow:find(lootKey).gains)

print("loot_collection_spec: passed")
