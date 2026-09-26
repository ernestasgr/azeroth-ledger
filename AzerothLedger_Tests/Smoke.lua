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
