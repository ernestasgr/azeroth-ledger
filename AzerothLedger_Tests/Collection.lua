local _, companion = ...
local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

-- Counts, search, browsing filters, item metadata and preferences.
local fixtures = companion.collection
local meat, bear, wolf = fixtures.meat, fixtures.bear, fixtures.wolf
local fixture, metadata = fixtures.fixture, fixtures.metadata

function tests.CharacterTotalsSeparateInitialStockAndGainsFromAccountHistory(_self)
    local store, scan, writes = fixture()
    local key = addon.Item.key(meat, 2672)
    scan("Ben", "B", "bags", 1003, { { itemID = 2672, link = meat, quantity = 10 } })
    local actor = { character = "Ada", realm = "A", level = 12, place = "Forest" }
    WoWUnit.IsTrue(
        store:command(
            "lootOpen",
            { slots = { { key = key, quantity = 2 } } },
            1010,
            { character = "Ada", realm = "A", level = 12, place = "Forest" }
        )
    )
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 2 }, 1011, actor))
    scan("Ada", "A", "bags", 1012, { { itemID = 2672, link = meat, quantity = 402 } })
    local before = writes()
    local filter = { character = "Ben", realm = "B", search = "Meat" }
    local detail = addon.Collection.inspect(store, key, "Ada", "A", filter)
    WoWUnit.AreEqual(10, detail.characterOverall)
    WoWUnit.AreEqual(412, detail.allCharactersOverall)
    WoWUnit.AreEqual(10, detail.characterCurrent)
    WoWUnit.AreEqual(412, detail.allCharactersCurrent)
    WoWUnit.AreEqual(0, detail.breakdown.gained)
    WoWUnit.AreEqual(nil, detail.breakdown.recorded)
    WoWUnit.AreEqual(nil, detail.breakdown.initial)
    WoWUnit.AreEqual(nil, detail.breakdown.methods.Looted)
    WoWUnit.AreEqual(1003, detail.firstSeen)
    WoWUnit.AreEqual(nil, detail.firstGained)
    WoWUnit.AreEqual("Seen in storage", detail.evidence)
    WoWUnit.AreEqual(10, addon.Collection.query(store, "Ada", "A", filter).rows[1].characterOverall)
    WoWUnit.AreEqual(402, store:breakdown(key).recorded)
    WoWUnit.AreEqual(nil, addon.Collection.inspect(store, key, "Ada", "A", { realm = "B" }).characterCurrent)
    WoWUnit.AreEqual(before, writes())
end

function tests.FirstGainOnAnotherCharacterIsNotAlsoInitialStock(_self)
    for _, delayed in ipairs({ false, true }) do
        local store, scan = fixture("Ben", "B")
        local key = addon.Item.key(meat, 2672)
        scan("Ben", "B", "bags", 1003, {})
        local actor = { character = "Ben", realm = "B", level = 12, place = "Forest" }
        WoWUnit.IsTrue(
            store:command(
                "lootOpen",
                { slots = { { key = key, quantity = 1 } } },
                1010,
                { character = "Ben", realm = "B", level = 12, place = "Forest" }
            )
        )
        if not delayed then
            WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
        end
        scan("Ben", "B", "bags", 1012, { { itemID = 2672, link = meat, quantity = 1 } })
        if delayed then
            WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1013, actor))
        end
        local detail = addon.Collection.inspect(store, key, "Ada", "A", { character = "Ben", realm = "B" })
        WoWUnit.AreEqual(nil, detail.characterOverall)
        WoWUnit.AreEqual(nil, detail.allCharactersOverall)
        WoWUnit.AreEqual(1, detail.characterCurrent)
        WoWUnit.AreEqual(401, detail.allCharactersCurrent)
        WoWUnit.AreEqual(nil, detail.breakdown.recorded)
        WoWUnit.AreEqual(nil, detail.breakdown.methods.Seen)
        WoWUnit.AreEqual(1, detail.breakdown.gained)
        WoWUnit.AreEqual(401, store:breakdown(key).recorded)
    end
end

function tests.CurrentCountsAddLatestKnownAreasCheckedOnDifferentDates(_self)
    local store, scan = fixture()
    scan("Ben", "B", "bank", 1004, { { itemID = 2672, link = meat, quantity = 10 } })
    scan("Ben", "B", "bags", 1005, { { itemID = 2672, link = meat, quantity = 10 } })
    local detail = addon.Collection.inspect(store, addon.Item.key(meat, 2672), "Ada", "A", {
        character = "Ben",
        realm = "B",
    })
    WoWUnit.AreEqual(20, detail.characterCurrent)
    WoWUnit.AreEqual(420, detail.allCharactersCurrent)
    WoWUnit.AreEqual(10, detail.checks[2].quantity)
    WoWUnit.AreEqual(1004, detail.checks[2].at)
end

function tests.RealmChecksIncludeUnseenCharactersWithUncheckedStorage(_self)
    local store, scan = fixture()
    scan("Ada", "A", "bags", 1005, { { itemID = 2672, link = meat, quantity = 10 } })
    scan("Ada", "A", "bank", 1005, {})
    scan("Ada", "A", "equipped", 1005, {})
    scan("New", "A", "bags", 1005, {})
    local detail = addon.Collection.inspect(store, addon.Item.key(meat, 2672), "Ada", "A", { realm = "A" })
    WoWUnit.AreEqual(10, detail.characterCurrent)
    WoWUnit.AreEqual(10, detail.allCharactersCurrent)
    WoWUnit.AreEqual(6, #detail.checks)
end

function tests.SearchCountsDiscoveriesRatherThanStockAndKeepsVariants(_self)
    local store, _, writes = fixture()
    local before = writes()
    local result = addon.Collection.query(store, "Ada", "A", {}, metadata)
    WoWUnit.AreEqual(3, result.discoveryCount)
    WoWUnit.AreEqual(3, #result.rows)
    WoWUnit.AreEqual(1, result.categories.Materials)
    WoWUnit.AreEqual(2, result.categories.Weapons)
    result = addon.Collection.query(store, "Ada", "A", { search = "sWoRd", category = "Weapons" }, metadata)
    WoWUnit.AreEqual(2, #result.rows)
    WoWUnit.AreEqual(2, #result.rows[1].record.links)
    result = addon.Collection.query(store, "Ada", "A", { character = "Ada", realm = "A" }, metadata)
    WoWUnit.AreEqual(2, #result.rows)
    WoWUnit.AreEqual(3, result.discoveryCount)
    local details = addon.Collection.inspect(store, addon.Item.key(meat, 2672), "Ada", "A")
    WoWUnit.AreEqual(400, details.breakdown.recorded)
    WoWUnit.AreEqual("Present", details.ownership)
    WoWUnit.AreEqual(400, details.checks[1].quantity)
    WoWUnit.AreEqual(nil, details.checks[2].quantity)
    WoWUnit.AreEqual("Seen in storage", details.evidence)
    WoWUnit.AreEqual(before, writes())
end

function tests.RecordedPlacesRequireGainEvidenceAndTimelineSurvivesPruning(_self)
    local store, scan = fixture()
    local key = addon.Item.key(meat, 2672)
    local actor = { character = "Ada", realm = "A", level = 12, place = "Deadmines", placeKind = "dungeon" }
    WoWUnit.AreEqual(0, #addon.Collection.query(store, "Ada", "A", {}, metadata).places)
    WoWUnit.IsTrue(store:command("lootOpen", { slots = { { key = key, quantity = 2 } } }, 1010, {
        character = actor.character,
        realm = actor.realm,
        level = actor.level,
        place = actor.place,
        placeKind = actor.placeKind,
    }))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 2 }, 1011, actor))
    scan("Ada", "A", "bags", 1012, { { itemID = 2672, link = meat, quantity = 402 } })
    local result = addon.Collection.query(store, "Ada", "A", { place = "Deadmines", placeKind = "dungeon" }, metadata)
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual("dungeon", result.places[1].kind)
    local detail = addon.Collection.inspect(store, key, "Ada", "A")
    WoWUnit.AreEqual(402, detail.characterOverall)
    WoWUnit.AreEqual(402, detail.allCharactersOverall)
    WoWUnit.AreEqual(402, detail.characterCurrent)
    WoWUnit.AreEqual(402, detail.allCharactersCurrent)
    WoWUnit.IsTrue(store:setRetention("vendor", 0))
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
function tests.BrowsingFiltersAndSortsUseScopedFactsWithStableTies(_self)
    local store, _, writes = fixture()
    local before = writes()
    local function info(record)
        return {
            category = record.itemID == 100 and "Weapons" or "Materials",
            quality = record.itemID == 100 and 2 or nil,
        }
    end
    local function query(filter)
        return addon.Collection.query(store, "Ada", "A", filter, info).rows
    end
    WoWUnit.AreEqual(1, #query({ ownership = "present", character = "Ada", realm = "A", quality = "unknown" }))
    WoWUnit.AreEqual(0, #query({ ownership = "historical" }))
    WoWUnit.AreEqual(2, #query({ ownership = "unknown", character = "Ben", realm = "B", quality = 2 }))
    WoWUnit.AreEqual(3, #query({ method = "Seen" }))
    WoWUnit.AreEqual(0, #query({ method = "Looted" }))
    local rows = query({ sort = "discovered" })
    WoWUnit.AreEqual(addon.Item.key(wolf, 100), rows[1].key)
    rows = query({ sort = "quantity" })
    WoWUnit.AreEqual(addon.Item.key(meat, 2672), rows[1].key)
    rows = query({ sort = "gained" }) -- no confirmed dates: name, then intrinsic key
    WoWUnit.AreEqual(addon.Item.key(meat, 2672), rows[1].key)
    WoWUnit.AreEqual(addon.Item.key(bear, 100), rows[2].key)
    WoWUnit.AreEqual(addon.Item.key(wolf, 100), rows[3].key)
    rows = query({ character = "Ben", realm = "B", sort = "quantity" })
    WoWUnit.AreEqual(nil, rows[1].recorded)
    WoWUnit.AreEqual(1, rows[1].characterCurrent)
    WoWUnit.AreEqual(before, writes())
end

function tests.LatestGainAndMethodFiltersFollowTheSelectedCharacter(_self)
    local store, scan = fixture()
    local key = addon.Item.key(wolf, 100)
    WoWUnit.IsTrue(
        store:command(
            "vendorAction",
            { kind = "purchase", key = key, itemID = 100, link = wolf, quantity = 2 },
            2000,
            { character = "Ada", realm = "A", level = 12, place = "Forest" }
        )
    )
    scan("Ada", "A", "bags", 2001, {
        { itemID = 2672, link = meat, quantity = 400 },
        { itemID = 100, link = wolf, quantity = 2 },
    })
    local result = addon.Collection.query(store, "Ada", "A", { sort = "gained" }, metadata)
    WoWUnit.AreEqual(key, result.rows[1].key)
    WoWUnit.AreEqual(2000, result.rows[1].lastGained)
    result = addon.Collection.query(store, "Ada", "A", { character = "Ben", realm = "B", method = "Vendor" }, metadata)
    WoWUnit.AreEqual(0, #result.rows)
    result = addon.Collection.query(store, "Ada", "A", { character = "Ada", realm = "A", method = "Vendor" }, metadata)
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual(key, result.rows[1].key)
end

function tests.AppearancePreferencesPersistAndKeepCollectionFacts(_self)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    WoWUnit.IsTrue(store:scan({
        character = "Ada",
        realm = "A",
        area = "bags",
        complete = true,
        seenAt = 1000,
        items = { { itemID = 2672, link = meat, quantity = 3 } },
    }))
    WoWUnit.IsTrue(store:setDisplay("gold", { 0.2, 0.4, 0.8, 1 }))
    WoWUnit.IsTrue(store:setDisplay("reducedMotion", true))
    WoWUnit.IsTrue(store:setDisplay("backgroundOpacity", 0.6))
    local restored = addon.Schema.open(saved, function() end)
    WoWUnit.AreEqual(0.2, restored:display().gold[1])
    WoWUnit.AreEqual(true, restored:display().reducedMotion)
    WoWUnit.AreEqual(0.6, restored:display().backgroundOpacity)
    WoWUnit.AreEqual(3, restored:describe("2672:0").firstSeenUnits)
    WoWUnit.AreEqual(0, restored:describe("2672:0").totalGained)
    WoWUnit.AreEqual(false, restored:setDisplay("backgroundOpacity", 0 / 0))
    WoWUnit.AreEqual(false, restored:setDisplay("gold", { 1, 0, 0, 0 }))
end
