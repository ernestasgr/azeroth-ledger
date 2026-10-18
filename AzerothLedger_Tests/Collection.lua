local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

local meat = "|Hitem:2672::::::::|h[Meat]|h"
local bear = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h"
local enchanted = "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h"
local wolf = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h"

function tests.RecordedSourceBrowsingGroupsMobSpawnsAndKeepsScopeAndEvidence(_self)
    local saved
    local seed = addon.Schema.open(nil, function(value)
        saved = value
    end)
    WoWUnit.IsTrue(seed:scan({
        character = "Ada",
        realm = "A",
        area = "bags",
        complete = true,
        seenAt = 1000,
        items = { { itemID = 2672, link = meat, quantity = 2 } },
    }))
    local record = saved.records["2672:0"]
    record.totalGained = 6
    record.firstGained, record.lastGained = 1001, 1003
    record.characters[2] = { name = "Ben", realm = "B", firstSeen = 1002, lastSeen = 1002, firstSeenUnits = 0 }
    record.gains = {
        {
            id = "one",
            at = 1001,
            quantity = 2,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Looted",
            source = { kind = "mob", guid = "Creature-0-1-2-3-4-001", name = "Boar" },
        },
        {
            id = "two",
            at = 1002,
            quantity = 3,
            character = "Ben",
            realm = "B",
            level = 1,
            place = "Forest",
            method = "Looted",
            source = { kind = "mob", guid = "Creature-0-9-8-7-4-002" },
        },
        {
            id = "three",
            at = 1003,
            quantity = 1,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Looted",
            source = { kind = "mob", guid = "Creature-0-1-2-3-5-003", name = "Boar" },
        },
    }
    local writes = 0
    local store = addon.Schema.open(saved, function()
        writes = writes + 1
    end)
    WoWUnit.AreEqual("healthy", store:diagnostic().kind)
    local result = addon.Collection.query(store, "Ada", "A", { source = "mob:4" })
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual(5, result.rows[1].sourceQuantity)
    WoWUnit.AreEqual("Boar (mob #4)", result.sources[1].label)
    WoWUnit.AreEqual(5, store:breakdown("2672:0").sources["Boar (mob #4)"])
    WoWUnit.AreEqual(1, store:breakdown("2672:0").sources["Boar (mob #5)"])
    result = addon.Collection.query(store, "Ada", "A", { source = "mob:4", realm = "B" })
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual(3, result.rows[1].sourceQuantity)
    WoWUnit.AreEqual("Mob #4", result.sources[1].label)
    WoWUnit.AreEqual(0, #addon.Collection.query(store, "Ada", "A", { source = "mob:4", character = "Nobody" }).rows)
    WoWUnit.AreEqual(1, #addon.Collection.query(store, "Ada", "A", { search = "Boar" }).rows)
    WoWUnit.AreEqual("Creature-0-9-8-7-4-002", store:find("2672:0").gains[2].source.guid)
    WoWUnit.AreEqual(0, writes)
end

function tests.SourceKindsUnknownsAndCorrectionsReconcileAfterJournalPruning(_self)
    local saved
    local seed = addon.Schema.open(nil, function(value)
        saved = value
    end)
    WoWUnit.IsTrue(seed:scan({
        character = "Ada",
        realm = "A",
        area = "bags",
        complete = true,
        seenAt = 1000,
        items = { { itemID = 2672, link = meat, quantity = 2 } },
    }))
    local record = saved.records["2672:0"]
    record.totalGained, record.firstGained, record.lastGained = 15, 1001, 1006
    record.gains = {
        {
            id = "quest",
            at = 1001,
            quantity = 1,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Quest",
            context = { kind = "quest", id = 10, name = "Same name" },
        },
        {
            id = "recipe",
            at = 1002,
            quantity = 2,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Crafted",
            context = { kind = "recipe", id = 10, name = "Same name" },
        },
        {
            id = "player",
            at = 1003,
            quantity = 3,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Obtained",
            channel = "trade",
            source = { kind = "player", name = "Eve", realm = "B" },
        },
        {
            id = "unknown",
            at = 1004,
            quantity = 4,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Obtained",
        },
        {
            id = "spawn",
            at = 1005,
            quantity = 2,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Looted",
            source = { kind = "mob", guid = "unparseable" },
        },
        {
            id = "other-spawn",
            at = 1006,
            quantity = 3,
            character = "Ada",
            realm = "A",
            level = 1,
            place = "Forest",
            method = "Looted",
            source = { kind = "mob", guid = "another-unparseable" },
        },
    }
    local store = addon.Schema.open(saved, function(value)
        saved = value
    end)
    WoWUnit.AreEqual("healthy", store:diagnostic().kind)
    for _, example in ipairs({
        { "quest:10", 1 },
        { "recipe:10", 2 },
        { "player:Eve-B", 3 },
        { "unknown", 4 },
        { "mob:unparseable", 2 },
        { "mob:another-unparseable", 3 },
    }) do
        local result = addon.Collection.query(store, "Ada", "A", { source = example[1] })
        WoWUnit.AreEqual(1, #result.rows)
        WoWUnit.AreEqual(example[2], result.rows[1].sourceQuantity)
    end
    local breakdown = store:breakdown("2672:0")
    WoWUnit.AreEqual(1, breakdown.sources["Same name (quest #10)"])
    WoWUnit.AreEqual(2, breakdown.sources["Same name (recipe #10)"])
    WoWUnit.AreEqual(2, breakdown.sources["Initial stock"])
    WoWUnit.AreEqual(4, breakdown.sources.Unknown)
    local sum = 0
    for _, quantity in pairs(breakdown.sources) do
        sum = sum + quantity
    end
    WoWUnit.AreEqual(17, sum)
    WoWUnit.IsTrue(store:setRetention("gains", 0))
    WoWUnit.IsTrue(store:correctGain({
        id = "source-proof",
        key = "2672:0",
        gainID = "unknown",
        quantity = 2,
        fromMethod = "Obtained",
        method = "Quest",
        context = { kind = "quest", id = 11 },
    }))
    WoWUnit.AreEqual(15, store:find("2672:0").totalGained)
    WoWUnit.AreEqual(2, addon.Collection.query(store, "Ada", "A", { source = "unknown" }).rows[1].sourceQuantity)
    WoWUnit.AreEqual(2, addon.Collection.query(store, "Ada", "A", { source = "quest:11" }).rows[1].sourceQuantity)
    store = addon.Schema.open(saved, function() end)
    WoWUnit.AreEqual(2, addon.Collection.query(store, "Ada", "A", { source = "quest:11" }).rows[1].sourceQuantity)
    WoWUnit.AreEqual(0, #store:journal())
end

function tests.SourceNameSearchIncludesOtherItemsWithTheSameProvenIdentity(_self)
    local saved
    local seed = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local bread = "|Hitem:4540::::::::|h[Bread]|h"
    WoWUnit.IsTrue(seed:scan({
        character = "Ada",
        realm = "A",
        area = "bags",
        complete = true,
        seenAt = 1000,
        items = { { itemID = 2672, link = meat, quantity = 1 }, { itemID = 4540, link = bread, quantity = 1 } },
    }))
    for index, key in ipairs({ "2672:0", "4540:0" }) do
        local record = saved.records[key]
        record.totalGained, record.firstGained, record.lastGained = index, 1001, 1001
        record.gains = {
            {
                id = "quest-" .. index,
                at = 1001,
                quantity = index,
                character = "Ada",
                realm = "A",
                level = 1,
                place = "Forest",
                method = "Quest",
                context = { kind = "quest", id = 10, name = index == 1 and "Proven quest" or nil },
            },
        }
    end
    local store = addon.Schema.open(saved, function()
        error("Search wrote source facts")
    end)
    WoWUnit.AreEqual("healthy", store:diagnostic().kind)
    WoWUnit.AreEqual(2, #addon.Collection.query(store, "Ada", "A", { search = "Proven quest" }).rows)
end

function tests.LootEquippedBeforeCheckingKeepsSourceSharesAndOneDiscovery(_self)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local key = addon.Item.key(bear, 100)
    local actor = { character = "Ada", realm = "A", level = 12, place = "Durotar" }
    local function scan(area, at, items)
        WoWUnit.IsTrue(store:scan({
            character = actor.character,
            realm = actor.realm,
            area = area,
            seenAt = at,
            complete = true,
            items = items,
        }))
    end
    scan("bags", 1000, {})
    scan("equipped", 1000, {})
    local first = { kind = "mob", guid = "Creature-0-1-1-1-1-001", name = "First mob" }
    local second = { kind = "mob", guid = "Creature-0-1-1-1-2-002", name = "Second mob" }
    WoWUnit.IsTrue(store:command("lootOpen", {
        slots = {
            { key = key, quantity = 1, source = first },
            { key = key, quantity = 1, source = second },
        },
    }, 1001, { character = actor.character, realm = actor.realm, level = actor.level, place = actor.place }))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 2 }, 1002, actor))
    scan("bags", 1003, {})
    scan("equipped", 1003, {
        { itemID = 100, link = bear, quantity = 1 },
        { itemID = 100, link = enchanted, quantity = 1 },
    })
    local breakdown = store:breakdown(key)
    WoWUnit.AreEqual(0, breakdown.initial)
    WoWUnit.AreEqual(2, breakdown.gained)
    WoWUnit.AreEqual(2, breakdown.recorded)
    WoWUnit.AreEqual(2, breakdown.methods.Looted)
    WoWUnit.AreEqual(1, breakdown.sources["First mob"])
    WoWUnit.AreEqual(1, breakdown.sources["Second mob"])
    WoWUnit.AreEqual(1, #store:takeDiscoveries())
    WoWUnit.AreEqual(2, #store:find(key).links)
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 2 }, 1004, actor))
    scan("bags", 1005, { { itemID = 100, link = bear, quantity = 2 } })
    scan("equipped", 1005, {})
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    store = addon.Schema.open(saved, function() end)
    WoWUnit.AreEqual("healthy", store:diagnostic().kind)
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
end

function tests.ContainerSpawnsShareOneSourceTotalWithoutLosingTheirGUIDs(_self)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local link = "|Hitem:11583::::::::|h[Cactus Apple]|h"
    local key = addon.Item.key(link, 11583)
    local slots = {}
    for index, spawn in ipairs({ "0000422303", "0000422406", "0000422422", "000042245A", "0000C22422" }) do
        slots[index] = {
            key = key,
            quantity = 1,
            slot = index,
            source = { kind = "container", guid = "GameObject-0-6783-1-14-171938-" .. spawn },
        }
    end
    WoWUnit.IsTrue(store:scan({
        character = "Ada",
        realm = "A",
        area = "bags",
        seenAt = 1000,
        complete = true,
        items = {},
    }))
    WoWUnit.IsTrue(
        store:command(
            "lootOpen",
            { slots = slots },
            1001,
            { character = "Ada", realm = "A", level = 1, place = "Durotar" }
        )
    )
    WoWUnit.IsTrue(
        store:command(
            "lootReceipt",
            { key = key, itemID = 11583, link = link, quantity = 5 },
            1002,
            { character = "Ada", realm = "A" }
        )
    )
    WoWUnit.IsTrue(store:scan({
        character = "Ada",
        realm = "A",
        area = "bags",
        seenAt = 1003,
        complete = true,
        items = { { itemID = 11583, link = link, quantity = 5 } },
    }))
    store = addon.Schema.open(saved, function() end)
    local rows = 0
    for _, quantity in pairs(store:breakdown(key, { character = "Ada", realm = "A" }).sources) do
        if quantity > 0 then
            rows = rows + 1
        end
    end
    WoWUnit.AreEqual(1, rows)
    WoWUnit.AreEqual(5, store:breakdown(key).sources["Container #171938"])
    local gains = store:find(key).gains
    WoWUnit.AreEqual(5, #gains)
    for index, gain in ipairs(gains) do
        WoWUnit.AreEqual(slots[index].source.guid, gain.source.guid)
    end
    -- An observed name on one spawn also labels unnamed spawns of this type.
    saved.records[key].gains[1].source.name = "Cactus Apple"
    store = addon.Schema.open(saved, function() end)
    WoWUnit.AreEqual(5, store:breakdown(key).sources["Cactus Apple"])
    WoWUnit.AreEqual(5, store:breakdown(key, { character = "Ada", realm = "A" }).sources["Cactus Apple"])
    WoWUnit.AreEqual(0, store:breakdown(key, { character = "Ben", realm = "A" }).gained)
    WoWUnit.AreEqual(nil, next(store:breakdown(key, { realm = "B" }).sources))
    -- Equal names do not merge different container types.
    saved.records[key].gains[5].source.guid = "GameObject-0-6783-1-14-171939-0000C22422"
    saved.records[key].gains[5].source.name = "Cactus Apple"
    store = addon.Schema.open(saved, function() end)
    WoWUnit.AreEqual(4, store:breakdown(key).sources["Cactus Apple (container #171938)"])
    WoWUnit.AreEqual(1, store:breakdown(key).sources["Cactus Apple (container #171939)"])
    -- Conflicting names fall back to the proven type instead of choosing one.
    saved.records[key].gains[2].source.name = "Another name"
    store = addon.Schema.open(saved, function() end)
    WoWUnit.AreEqual(4, store:breakdown(key).sources["Container #171938"])
    WoWUnit.AreEqual(1, store:breakdown(key).sources["Cactus Apple"])
    WoWUnit.AreEqual(5, store:find(key).totalGained)
end

function tests.ContainerNamesRequireTheExactLootedGUID(_self)
    local guid = "GameObject-0-6783-1-14-171938-0000422303"
    local other = "GameObject-0-6783-1-14-171938-0000422406"
    local cursorGUID, npcMatches, readable = guid, false, true
    local api = {
        GetNumLootItems = function()
            return 1
        end,
        GetLootSlotLink = function()
            return meat
        end,
        GetLootSourceInfo = function()
            return guid, 1
        end,
        UnitGUID = function(unit)
            return npcMatches and unit == "npc" and guid or other
        end,
        UnitName = function(unit)
            return npcMatches and unit == "npc" and "Cactus Apple" or "Nearby container"
        end,
        Enum = { TooltipDataType = { Object = 4 } },
        C_TooltipInfo = {
            GetWorldCursor = function()
                assert(readable, "Unreadable tooltip")
                return { type = 4, guid = cursorGUID, lines = { { leftText = "Cactus Apple" } } }
            end,
        },
    }
    WoWUnit.AreEqual("Cactus Apple", addon.Loot.open(api)[1].source.name)
    cursorGUID = other
    WoWUnit.AreEqual(nil, addon.Loot.open(api)[1].source.name)
    npcMatches = true
    WoWUnit.AreEqual("Cactus Apple", addon.Loot.open(api)[1].source.name)
    npcMatches, readable = false, false
    WoWUnit.AreEqual(nil, addon.Loot.open(api)[1].source.name)
    WoWUnit.AreEqual("Container #171938", addon.Schema.sourceText(addon.Loot.open(api)[1].source))
end

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

function tests.IncompleteStorageRemainsUnknownAfterRefund(_self)
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
    local detail = table.concat(addon.Collection.details(store, key, "Ada", "A", filter), "\n")
    WoWUnit.IsTrue(detail:find("offline; status Unknown", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("checked", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("latest check 1", 1, true) ~= nil)
end

local function metadata(record)
    return { category = record.itemID == 100 and "Weapons" or "Materials" }
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
    local text = table.concat(addon.Collection.details(store, "2672:0", "Ben", "A", filter), "\n")
    WoWUnit.IsTrue(text:find("Ada-A • Bank: last found 5 on " .. date("%Y-%m-%d %H:%M", 4000), 1, true) ~= nil)
    WoWUnit.IsTrue(text:find("offline; status Unknown", 1, true) ~= nil)
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
        local store, scan = fixture()
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
    local detail = table.concat(addon.Collection.details(store, key, "Ada", "A"), "\n")
    WoWUnit.IsTrue(detail:find("Character overall: 402", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("All characters overall: 402", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("Character current: 402", 1, true) ~= nil)
    WoWUnit.IsTrue(detail:find("All characters current: 402", 1, true) ~= nil)
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
