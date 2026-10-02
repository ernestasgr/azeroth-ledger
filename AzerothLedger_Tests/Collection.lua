local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

local meat = "|Hitem:2672::::::::|h[Meat]|h"
local bear = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h"
local enchanted = "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h"
local wolf = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h"

local function fixture()
    local writes = 0
    local store = addon.Schema.open(nil, function()
        writes = writes + 1
    end)
    local function scan(character, realm, area, at, items, complete)
        WoWUnit.IsTrue(store:scan({
            character = character,
            realm = realm,
            area = area,
            seenAt = at,
            complete = complete ~= false,
            items = items,
        }))
    end
    scan("Ada", "A", "bags", 1000, { { itemID = 2672, link = meat, quantity = 400 } })
    scan("Ada", "A", "equipped", 1000, { { itemID = 100, link = bear, quantity = 1 } })
    scan("Ben", "B", "bags", 1001, {
        { itemID = 100, link = enchanted, quantity = 1 },
        { itemID = 100, link = wolf, quantity = 1 },
    })
    return store, scan, function()
        return writes
    end
end

function tests.FoundOnceIsAccountWideAndRefundRemovesItWithoutAnotherDiscovery(_self)
    local store = addon.Schema.open(nil, function() end)
    local bread = "|Hitem:4540::::::::|h[Bread]|h"
    local key = addon.Item.key(bread, 4540)
    local actor = { character = "Ada", realm = "A", level = 12, place = "Forest", placeKind = "zone" }
    local function scan(character, area, at, quantity)
        WoWUnit.IsTrue(store:scan({
            character = character,
            realm = "A",
            area = area,
            seenAt = at,
            complete = true,
            items = quantity > 0 and { { itemID = 4540, link = bread, quantity = quantity } } or {},
        }))
    end
    scan("Ada", "bags", 1000, 0)
    local function vendor(kind, at)
        WoWUnit.IsTrue(
            store:vendorAction({ kind = kind, key = key, itemID = 4540, link = bread, quantity = 1 }, at, actor)
        )
    end
    vendor("purchase", 1001)
    scan("Ada", "bags", 1002, 1)
    scan("Ben", "bags", 1003, 1)
    local filter = { foundOnce = true, character = "Ben", realm = "A" }
    local result = addon.Collection.query(store, "Ada", "A", filter)
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual("Unknown", result.rows[1].ownership)
    result = addon.Collection.query(store, "Ada", "A", { historical = true, character = "Ben", realm = "A" })
    WoWUnit.AreEqual(0, #result.rows)
    vendor("refund", 1004)
    scan("Ada", "bags", 1005, 0)
    WoWUnit.AreEqual(0, #addon.Collection.query(store, "Ada", "A", filter).rows)
    WoWUnit.AreEqual(1, addon.Collection.query(store, "Ada", "A", {}).discoveryCount)
    for _, area in ipairs({ "bags", "bank", "equipped" }) do
        scan("Ada", area, 1006, 0)
    end
    result = addon.Collection.query(store, "Ada", "A", { historical = true, character = "Ada", realm = "A" })
    WoWUnit.AreEqual(1, #result.rows)
    local detail = table.concat(addon.Collection.details(store, key, "Ada", "A", filter), "\n")
    WoWUnit.IsTrue(detail:find("offline; current ownership Unknown", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("checked", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("Recorded units: 0", 1, true) ~= nil)
end

local function metadata(record)
    return { category = record.itemID == 100 and "Weapons" or "Materials" }
end

function tests.SearchCountsDiscoveriesRatherThanStockAndKeepsVariants(_self)
    local store, _, writes = fixture()
    local before = writes()
    local result = addon.Collection.query(store, "Ada", "A", {}, metadata)
    WoWUnit.AreEqual(3, result.discoveryCount)
    WoWUnit.AreEqual(3, #result.rows)
    result = addon.Collection.query(store, "Ada", "A", { search = "sWoRd", category = "Weapons" }, metadata)
    WoWUnit.AreEqual(2, #result.rows)
    WoWUnit.AreEqual(2, #result.rows[1].record.links)
    result = addon.Collection.query(store, "Ada", "A", { character = "Ada", realm = "A" }, metadata)
    WoWUnit.AreEqual(2, #result.rows)
    WoWUnit.AreEqual(3, result.discoveryCount)
    WoWUnit.AreEqual(before, writes())
end

function tests.RecordedPlacesRequireGainEvidenceAndTimelineSurvivesPruning(_self)
    local store, scan = fixture()
    local key = addon.Item.key(meat, 2672)
    local actor = { character = "Ada", realm = "A", level = 12, place = "Deadmines", placeKind = "dungeon" }
    WoWUnit.AreEqual(0, #addon.Collection.query(store, "Ada", "A", {}, metadata).places)
    WoWUnit.IsTrue(store:lootOpen({
        character = actor.character,
        realm = actor.realm,
        level = actor.level,
        at = 1010,
        place = actor.place,
        placeKind = actor.placeKind,
        slots = { { key = key, quantity = 2 } },
    }))
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 2 }, 1011, actor))
    scan("Ada", "A", "bags", 1012, { { itemID = 2672, link = meat, quantity = 402 } })
    local result = addon.Collection.query(store, "Ada", "A", { place = "Deadmines", placeKind = "dungeon" }, metadata)
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual("dungeon", result.places[1].kind)
    local detail = table.concat(addon.Collection.details(store, key, "Ada", "A"), "\n")
    WoWUnit.IsTrue(detail:find("Recorded units: 402", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("Method total: Seen 400", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("Source total: Unknown 2", 1, true) ~= nil)
    WoWUnit.IsTrue(store:pruneJournal(0))
    result = addon.Collection.query(store, "Ada", "A", { view = "Discoveries" }, metadata)
    WoWUnit.AreEqual(3, #result.rows)
    WoWUnit.AreEqual(1001, result.rows[1].discoveredAt)
    WoWUnit.AreEqual(1000, result.rows[3].discoveredAt)
    WoWUnit.AreEqual(402, store:breakdown(key).recorded)
end

function tests.MetadataUsesNumericClassesAndLeavesUnreadableItemsLoading(_self)
    local categories = { [2] = "Weapons", [4] = "Armour", [9] = "Recipes", [7] = "Materials", [0] = "Consumables" }
    for classID, expected in pairs(categories) do
        local api = {
            C_Item = {
                GetItemInfo = function()
                    return "Name", meat, 1, nil, nil, nil, nil, nil, nil, nil, nil, classID
                end,
            },
        }
        WoWUnit.AreEqual(expected, addon.Client.itemMetadata(api, { links = { meat } }).category)
    end
    WoWUnit.AreEqual(
        "Junk",
        addon.Client.itemMetadata({
            C_Item = {
                GetItemInfo = function()
                    return "Name", meat, 0, nil, nil, nil, nil, nil, nil, nil, nil, 4
                end,
            },
        }, { links = { meat } }).category
    )
    WoWUnit.IsTrue(addon.Client.itemMetadata({}, { links = { meat } }).loading)
    WoWUnit.IsTrue(addon.Client.itemMetadata({
        C_Item = {
            GetItemInfo = function()
                error("unreadable")
            end,
        },
    }, { links = { meat } }).loading)
    local place, kind = addon.Client.place({
        GetRealZoneText = function()
            return "Deadmines"
        end,
        IsInInstance = function()
            return true, "party"
        end,
    })
    WoWUnit.AreEqual("Deadmines", place)
    WoWUnit.AreEqual("dungeon", kind)
end
