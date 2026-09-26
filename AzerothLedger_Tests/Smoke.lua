local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

local plain = "|Hitem:2672::::::::|h[Meat]|h"
local bear = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h"
local enchanted = "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h"
local wolf = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h"

local function replay()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local clock = 1000
    local character = "Ada"
    local realm = "Realm A"
    local slots = { [0] = { itemID = 2672, hyperlink = plain, stackCount = 400 } }
    local api = {
        UnitName = function()
            return character
        end,
        GetRealmName = function()
            return realm
        end,
        GetServerTime = function()
            return clock
        end,
        C_Container = {
            GetContainerNumSlots = function(bag)
                return bag == 0 and 1 or 0
            end,
            GetContainerItemInfo = function(bag)
                return slots[bag]
            end,
        },
    }
    store:scan(addon.Scan.capture(api, "bags", false))
    store:scan(addon.Scan.capture(api, "bags", false))
    store:scan(addon.Scan.capture(api, "bank", false))
    clock = 1050
    slots[0] = { itemID = 100, hyperlink = bear, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    clock = 1100
    character = "Ben"
    realm = "Realm B"
    slots[0] = { itemID = 100, hyperlink = bear, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    clock = 1200
    slots[0] = { itemID = 100, hyperlink = enchanted, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    clock = 1300
    slots[0] = { itemID = 100, hyperlink = wolf, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    return addon.Schema.open(saved, function(value)
        saved = value
    end)
end

function tests.InitialStockHasNoGain(_self)
    local store = replay()
    local meat = store:find(addon.Item.key(plain, 2672))
    WoWUnit.AreEqual(400, meat.firstSeenUnits)
    WoWUnit.AreEqual(0, meat.totalGained)
    WoWUnit.AreEqual(nil, meat.firstGained)
    WoWUnit.AreEqual(2, #meat.observations)
    WoWUnit.AreEqual(0, meat.observations[2].quantity)
    WoWUnit.IsTrue(not store:area("Ada", "Realm A", "bank").complete)
end

function tests.VariantsAndLinksSurviveRestoration(_self)
    local store = replay()
    WoWUnit.AreEqual(3, #store:list())
    local bearRecord = store:find(addon.Item.key(bear, 100))
    WoWUnit.AreEqual(2, #bearRecord.links)
    WoWUnit.AreEqual(3, #bearRecord.observations)
    WoWUnit.AreEqual(0, bearRecord.observations[3].quantity)
    WoWUnit.AreEqual(2, #bearRecord.characters)
    WoWUnit.AreEqual(1050, bearRecord.firstSeen)
    WoWUnit.AreEqual(1200, bearRecord.lastSeen)
    WoWUnit.AreEqual(1050, bearRecord.characters[1].firstSeen)
    WoWUnit.AreEqual(1100, bearRecord.characters[2].firstSeen)
    WoWUnit.IsTrue(addon.Item.key(bear, 100) ~= addon.Item.key(wolf, 100))
end

function tests.CollectionOpensWithDatedObservations(_self)
    local store = replay()
    local lines = addon.Collection.lines(store, "Ada", "Realm A")
    WoWUnit.IsTrue(lines[2]:find("incomplete", 1, true) ~= nil)
    local frame = addon.Collection.open(_G, store, "Ada", "Realm A")
    WoWUnit.IsTrue(frame and frame:IsShown())
    frame:Hide()
end

local pelt = "|Hitem:4865::::::::|h[Ruined Pelt]|h"
local peltKey = addon.Item.key(pelt, 4865)

local function lootReplay(startingUnits, gainUnits, receiptUnits, duplicates, receiptAfterScan)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local function bags(at, units)
        local items = {}
        if units > 0 then
            items[1] = { itemID = 4865, link = pelt, quantity = units }
        end
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            seenAt = at,
            complete = true,
            items = items,
        }))
    end
    bags(1000, startingUnits)
    WoWUnit.IsTrue(store:lootOpen({
        character = "Ada",
        realm = "Realm",
        at = 1010,
        level = 12,
        place = "Elwynn Forest",
        slots = { { key = peltKey } },
    }))
    local receipt = { key = peltKey, quantity = receiptUnits }
    if receiptAfterScan then
        bags(1011, startingUnits + gainUnits)
        WoWUnit.IsTrue(store:lootClose(1011))
        WoWUnit.IsTrue(store:lootClose(1011))
    end
    for _ = 1, duplicates do
        WoWUnit.IsTrue(store:lootReceipt(receipt, 1012, { character = "Ada", realm = "Realm" }))
    end
    if not receiptAfterScan then
        bags(1013, startingUnits + gainUnits)
    end
    return addon.Schema
        .open(saved, function(value)
            saved = value
        end)
        :find(peltKey)
end

function tests.TwoLootedUnitsAreCountedOnce(_self)
    local record = lootReplay(6, 2, 2, 1, false)
    WoWUnit.AreEqual(6, record.firstSeenUnits)
    WoWUnit.AreEqual(2, record.totalGained)
    WoWUnit.AreEqual(8, record.firstSeenUnits + record.totalGained)
    WoWUnit.AreEqual(1, #record.gains)
    WoWUnit.AreEqual("Looted", record.gains[1].method)
end

function tests.DuplicateLookingReceiptsRespectOneUnitIncrease(_self)
    local record = lootReplay(5, 1, 1, 2, false)
    WoWUnit.AreEqual(1, record.totalGained)
    WoWUnit.AreEqual(1, #record.gains)
end

function tests.LateReceiptAfterRepeatedCloseIsCounted(_self)
    local record = lootReplay(5, 1, 1, 1, true)
    WoWUnit.AreEqual(1, record.totalGained)
end

function tests.UnknownSourceStaysUnknown(_self)
    local record = lootReplay(5, 1, 1, 1, false)
    WoWUnit.AreEqual(nil, record.gains[1].source)
    WoWUnit.AreEqual("Elwynn Forest", record.gains[1].place)
    WoWUnit.AreEqual(12, record.gains[1].level)
end
