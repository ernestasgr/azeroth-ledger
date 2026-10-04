local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

local meat = "|Hitem:2672::::::::|h[Meat]|h"
local bear = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h"
local enchanted = "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h"
local wolf = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h"

function tests.IconAndCheckboxContentCannotBeCoveredByTheirBackings(_self)
    ---@type fun(frameType: string): table
    local createFrame = CreateFrame
    local parent = createFrame("Frame")
    local icon = addon.BookWidgets.icon(parent, 0, 0, 32)
    local backing
    for _, region in ipairs({ parent:GetRegions() }) do
        if region ~= icon then
            backing = region
        end
    end
    local layers = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
    local function order(region)
        local layer, subLevel = region:GetDrawLayer()
        return layers[layer] * 16 + subLevel
    end
    WoWUnit.IsTrue(backing ~= nil and order(icon) > order(backing))
    local checkbox = addon.BookWidgets.checkbox({ api = _G, controls = {} }, parent, "Test", 0, 0, 120, function() end)
    local inner, outer
    for _, region in ipairs({ checkbox:GetRegions() }) do
        if region:GetWidth() == 13 then
            inner = region
        elseif region:GetWidth() == 15 then
            outer = region
        end
    end
    WoWUnit.IsTrue(inner ~= nil and outer ~= nil and order(inner) > order(outer))
    parent:Hide()
end

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
    WoWUnit.IsTrue(detail:find("Checked units: 1", 1, true) ~= nil)
end

local function metadata(record)
    return { category = record.itemID == 100 and "Weapons" or "Materials" }
end

function tests.GalleryKeepsVariantsAndSavedLinksWithinCharacterScopeWithoutWriting(_self)
    local store, _, writes = fixture()
    local before = writes()
    local function gearMetadata(record)
        return { category = record.itemID == 100 and "Weapons" or "Materials", gear = record.itemID == 100 }
    end
    local filter = { view = "Gallery", character = "Ben", realm = "B" }
    local result = addon.Collection.query(store, "Ada", "A", filter, gearMetadata)
    WoWUnit.AreEqual(2, #result.rows)
    WoWUnit.AreEqual(addon.Item.key(bear, 100), result.rows[1].key)
    WoWUnit.AreEqual(2, #result.rows[1].record.links)
    WoWUnit.AreEqual(enchanted, result.rows[1].record.links[2])
    WoWUnit.AreEqual(addon.Item.key(wolf, 100), result.rows[2].key)
    WoWUnit.AreEqual(
        0,
        #addon.Collection.query(store, "Ada", "A", { view = "Gallery", realm = "Missing" }, gearMetadata).rows
    )
    WoWUnit.AreEqual(2, #addon.Collection.query(store, "Ada", "A", { view = "Gallery" }, gearMetadata).rows)
    WoWUnit.AreEqual(3, #addon.Collection.query(store, "Ada", "A", { view = "Gallery" }, function()
        return { category = "Unknown", loading = true }
    end).rows)
    WoWUnit.AreEqual(before, writes())
end

function tests.PreviewUsesTheExactRetainedLinkAndSafelyReportsUnavailableItems(_self)
    local shown
    local ready, wearable = true, true
    local previewResult = "opened"
    local api = {
        C_Item = {
            GetItemInfo = function()
                return ready and "Sword" or nil
            end,
            IsDressableItemByID = function()
                return wearable
            end,
        },
        DressUpItemLink = function(link)
            if previewResult == "error" then
                error("native preview failed")
            elseif previewResult == "rejected" then
                return false
            end
            shown = link
            return true
        end,
    }
    WoWUnit.AreEqual("ready", addon.Client.previewStatus(api, enchanted))
    WoWUnit.AreEqual(nil, shown)
    WoWUnit.AreEqual("opened", addon.Client.previewItem(api, enchanted))
    WoWUnit.AreEqual(enchanted, shown)
    shown = nil
    wearable = false
    WoWUnit.AreEqual("not-wearable", addon.Client.previewItem(api, meat))
    WoWUnit.AreEqual(nil, shown)
    ready = false
    WoWUnit.AreEqual("loading", addon.Client.previewItem(api, bear))
    WoWUnit.AreEqual(nil, shown)
    ready, wearable = true, true
    local nativePreview = api.DressUpItemLink
    api.DressUpItemLink = nil
    WoWUnit.AreEqual("unavailable", addon.Client.previewItem(api, bear))
    api.DressUpItemLink = nativePreview
    previewResult = "error"
    WoWUnit.AreEqual("unavailable", addon.Client.previewItem(api, bear))
    previewResult = "rejected"
    WoWUnit.AreEqual("unavailable", addon.Client.previewItem(api, bear))
    api.C_Item.IsDressableItemByID = function()
        error("unreadable")
    end
    WoWUnit.AreEqual("unavailable", addon.Client.previewItem(api, bear))
    WoWUnit.AreEqual("unavailable", addon.Client.previewItem(api, nil))
end

function tests.GallerySelectionResetsLinksBetweenVariantsAndClearsEmptyScopes(_self)
    local store, _, writes = fixture()
    local before = writes()
    local function gearMetadata(record)
        return { category = record.itemID == 100 and "Weapons" or "Materials", gear = record.itemID == 100 }
    end
    local result = addon.Collection.query(store, "Ada", "A", { view = "Gallery" }, gearMetadata)
    local bearKey, wolfKey = addon.Item.key(bear, 100), addon.Item.key(wolf, 100)
    local selection = addon.Collection.gallerySelection(result, bearKey, enchanted)
    WoWUnit.AreEqual(bearKey, selection.key)
    WoWUnit.AreEqual(enchanted, selection.link)
    WoWUnit.AreEqual(2, selection.index)
    local refreshed = addon.Collection.gallerySelection(result, selection.key, selection.link)
    WoWUnit.AreEqual(enchanted, refreshed.link)
    selection = addon.Collection.gallerySelection(result, wolfKey, enchanted)
    WoWUnit.AreEqual(wolfKey, selection.key)
    WoWUnit.AreEqual(wolf, selection.link)
    WoWUnit.AreEqual(1, selection.index)
    result =
        addon.Collection.query(store, "Ada", "A", { view = "Gallery", character = "Ada", realm = "A" }, gearMetadata)
    selection = addon.Collection.gallerySelection(result, wolfKey, wolf)
    WoWUnit.AreEqual(bearKey, selection.key)
    WoWUnit.AreEqual(bear, selection.link)
    result = addon.Collection.query(store, "Ada", "A", { view = "Gallery", realm = "Missing" }, gearMetadata)
    WoWUnit.AreEqual(nil, addon.Collection.gallerySelection(result, selection.key, selection.link))
    WoWUnit.AreEqual(before, writes())
end

function tests.ViewerContextLinksCollapseWithoutLosingEnchants(_self)
    local store, scan, writes = fixture()
    local viewerLink = "|cff1eff00|Hitem:100:0:0:0:0:0:42:8:20:7:0:0:1:111|h[Sword]|h|r"
    scan("Ada", "A", "bags", 1002, { { itemID = 100, link = viewerLink, quantity = 1 } })
    local before = writes()
    local model = addon.Collection.inspect(store, addon.Item.key(bear, 100), "Ada", "A")
    WoWUnit.AreEqual(2, #model.links)
    WoWUnit.AreEqual(3, #model.record.links)
    WoWUnit.AreEqual(2, model.links[1].count)
    WoWUnit.AreEqual(before, writes())
end

function tests.CharacterTotalsSeparateInitialStockAndGainsFromAccountHistory(_self)
    local store, scan, writes = fixture()
    local key = addon.Item.key(meat, 2672)
    scan("Ben", "B", "bags", 1003, { { itemID = 2672, link = meat, quantity = 10 } })
    local actor = { character = "Ada", realm = "A", level = 12, place = "Forest" }
    WoWUnit.IsTrue(store:lootOpen({
        character = "Ada",
        realm = "A",
        level = 12,
        at = 1010,
        place = "Forest",
        slots = { { key = key, quantity = 2 } },
    }))
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 2 }, 1011, actor))
    scan("Ada", "A", "bags", 1012, { { itemID = 2672, link = meat, quantity = 402 } })
    local before = writes()
    local filter = { character = "Ben", realm = "B", search = "Meat" }
    local detail = addon.Collection.inspect(store, key, "Ada", "A", filter)
    WoWUnit.AreEqual(10, detail.checkedUnits)
    WoWUnit.AreEqual(0, detail.breakdown.gained)
    WoWUnit.AreEqual(10, detail.firstChecked)
    WoWUnit.AreEqual(nil, detail.breakdown.recorded)
    WoWUnit.AreEqual(nil, detail.breakdown.initial)
    WoWUnit.AreEqual(nil, detail.breakdown.methods.Looted)
    WoWUnit.AreEqual(1003, detail.firstSeen)
    WoWUnit.AreEqual(nil, detail.firstGained)
    WoWUnit.AreEqual("Seen in storage", detail.evidence)
    WoWUnit.AreEqual(10, addon.Collection.query(store, "Ada", "A", filter).rows[1].checkedUnits)
    WoWUnit.AreEqual(402, store:breakdown(key).recorded)
    WoWUnit.AreEqual(10, addon.Collection.inspect(store, key, "Ada", "A", { realm = "B" }).checkedUnits)
    WoWUnit.AreEqual(before, writes())
end

function tests.FirstGainOnAnotherCharacterIsNotAlsoInitialStock(_self)
    for _, delayed in ipairs({ false, true }) do
        local store, scan = fixture()
        local key = addon.Item.key(meat, 2672)
        scan("Ben", "B", "bags", 1003, {})
        local actor = { character = "Ben", realm = "B", level = 12, place = "Forest" }
        WoWUnit.IsTrue(store:lootOpen({
            character = "Ben",
            realm = "B",
            level = 12,
            at = 1010,
            place = "Forest",
            slots = { { key = key, quantity = 1 } },
        }))
        if not delayed then
            WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 1011, actor))
        end
        scan("Ben", "B", "bags", 1012, { { itemID = 2672, link = meat, quantity = 1 } })
        if delayed then
            WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 1013, actor))
        end
        local detail = addon.Collection.inspect(store, key, "Ada", "A", { character = "Ben", realm = "B" })
        WoWUnit.AreEqual(1, detail.checkedUnits)
        WoWUnit.AreEqual(1, detail.firstChecked)
        WoWUnit.AreEqual(nil, detail.breakdown.recorded)
        WoWUnit.AreEqual(nil, detail.breakdown.methods.Seen)
        WoWUnit.AreEqual(1, detail.breakdown.gained)
        WoWUnit.AreEqual(401, store:breakdown(key).recorded)
    end
end

function tests.ScopedChecksDoNotAddTheSameUnitsAcrossDifferentDates(_self)
    local store, scan = fixture()
    scan("Ben", "B", "bank", 1004, { { itemID = 2672, link = meat, quantity = 10 } })
    scan("Ben", "B", "bags", 1005, { { itemID = 2672, link = meat, quantity = 10 } })
    local detail = addon.Collection.inspect(store, addon.Item.key(meat, 2672), "Ada", "A", {
        character = "Ben",
        realm = "B",
    })
    WoWUnit.AreEqual(10, detail.checkedUnits)
    WoWUnit.AreEqual(1005, detail.checkedAt)
    WoWUnit.AreEqual(2, detail.uncheckedAreas)
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
    WoWUnit.AreEqual(10, detail.checkedUnits)
    WoWUnit.AreEqual(2, detail.uncheckedAreas)
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
