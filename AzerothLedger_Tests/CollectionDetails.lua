local _, companion = ...
local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

-- Item details: storage checks, the gallery, previews and saved links.
local fixtures = companion.collection
local meat, bear, enchanted, wolf = fixtures.meat, fixtures.bear, fixtures.enchanted, fixtures.wolf
local fixture = fixtures.fixture

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

function tests.IncompleteStorageRemainsUnknownAfterRefund(_self)
    local store = addon.Schema.open(nil, function() end)
    WoWUnit.IsTrue(store:setCharacter("Ada", "A"))
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
            store:command(
                "vendorAction",
                { kind = kind, key = key, itemID = 4540, link = bread, quantity = 1 },
                at,
                actor
            )
        )
    end
    vendor("purchase", 1001)
    scan("Ada", "bags", 1002, 1)
    scan("Ben", "bags", 1003, 1)
    local filter = { character = "Ben", realm = "A" }
    local result = addon.Collection.query(store, "Ada", "A", filter)
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual("Unknown", result.rows[1].ownership)
    result = addon.Collection.query(store, "Ada", "A", { ownership = "historical", character = "Ben", realm = "A" })
    WoWUnit.AreEqual(0, #result.rows)
    vendor("refund", 1004)
    scan("Ada", "bags", 1005, 0)
    WoWUnit.AreEqual(0, store:breakdown(key).gained)
    WoWUnit.AreEqual(1, #addon.Collection.query(store, "Ada", "A", filter).rows)
    WoWUnit.AreEqual(1, addon.Collection.query(store, "Ada", "A", {}).discoveryCount)
    for _, area in ipairs({ "bags", "bank", "equipped" }) do
        scan("Ada", area, 1006, 0)
    end
    result = addon.Collection.query(store, "Ada", "A", { ownership = "historical", character = "Ada", realm = "A" })
    WoWUnit.AreEqual(1, #result.rows)
    local bags = addon.Collection.inspect(store, key, "Ada", "A", filter).checks[1]
    WoWUnit.AreEqual("Ben", bags.character)
    WoWUnit.AreEqual(false, bags.online)
    WoWUnit.AreEqual(1003, bags.at)
    WoWUnit.AreEqual(1, bags.quantity)
end

function tests.DatedBankStockSurvivesClosureAndContributesToCurrentCount(_self)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local function scan(area, at, complete, quantity)
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "A",
            area = area,
            seenAt = at,
            complete = complete,
            items = quantity > 0 and { { itemID = 2672, link = meat, quantity = quantity } } or {},
        }))
    end
    scan("bags", 4000, true, 0)
    scan("equipped", 4000, true, 0)
    scan("bank", 4000, true, 5)
    scan("bank", 4001, false, 0)
    local filter = { character = "Ada", realm = "A" }
    local detail = addon.Collection.inspect(store, "2672:0", "Ada", "A", filter)
    WoWUnit.AreEqual("unknown", detail.ownershipState)
    WoWUnit.AreEqual(5, detail.characterCurrent)
    WoWUnit.AreEqual(nil, detail.checks[2].quantity)
    WoWUnit.AreEqual(4001, detail.checks[2].at)
    WoWUnit.AreEqual(5, detail.checks[2].observedQuantity)
    WoWUnit.AreEqual(4000, detail.checks[2].observedAt)
    local offlineBank = addon.Collection.inspect(store, "2672:0", "Ben", "A", filter).checks[2]
    WoWUnit.AreEqual(false, offlineBank.online)
    WoWUnit.AreEqual(5, offlineBank.observedQuantity)
    WoWUnit.AreEqual(4000, offlineBank.observedAt)
    scan("bank", 4002, true, 2)
    detail = addon.Collection.inspect(store, "2672:0", "Ada", "A", filter)
    WoWUnit.AreEqual(2, detail.checks[2].observedQuantity)
    WoWUnit.AreEqual(4002, detail.checks[2].observedAt)
    scan("bank", 4003, true, 0)
    scan("bank", 4004, true, 0)
    scan("bank", 4005, false, 0)
    store = addon.Schema.open(saved, function() end)
    detail = addon.Collection.inspect(store, "2672:0", "Ada", "A", filter)
    WoWUnit.AreEqual(0, detail.checks[2].observedQuantity)
    WoWUnit.AreEqual(4004, detail.checks[2].observedAt)
    WoWUnit.AreEqual("unknown", detail.ownershipState)
    for _, area in ipairs({ "bags", "bank", "equipped" }) do
        scan(area, 4006, true, 0)
    end
    detail = addon.Collection.inspect(store, "2672:0", "Ada", "A", filter)
    WoWUnit.AreEqual("historical", detail.ownershipState)
    WoWUnit.AreEqual(0, detail.characterCurrent)
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
