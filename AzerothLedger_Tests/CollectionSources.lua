local _, companion = ...
local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

-- Recorded Sources: spawns, containers, corrections and Source search.
local fixtures = companion.collection
local meat, bear, enchanted = fixtures.meat, fixtures.bear, fixtures.enchanted

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
    WoWUnit.IsTrue(store:setCharacter("Ada", "A"))
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
    WoWUnit.IsTrue(store:setCharacter("Ada", "A"))
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
    WoWUnit.AreEqual("Container #171938", addon.LastSeen.sourceText(addon.Loot.open(api)[1].source))
end

function tests.InteractKeyContainerKeepsItsName(_self)
    local guid = "GameObject-0-6783-1-14-171938-0000422303"
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
            return unit == "softinteract" and guid or nil
        end,
        UnitName = function(unit)
            return unit == "softinteract" and "Cactus Apple" or nil
        end,
    }
    WoWUnit.AreEqual("Cactus Apple", addon.Loot.open(api)[1].source.name)
end
