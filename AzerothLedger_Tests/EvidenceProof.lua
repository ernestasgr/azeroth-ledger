local _, companion = ...
local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

-- Later proof for loot evidence: delayed slots, corrections, proven shares and adapters.
local evidence = companion.evidence
local link, key, actor, fixture = evidence.link, evidence.key, evidence.actor, evidence.fixture

function tests.DelayedSlotProofAndMetadataEnrichWithoutNewUnits(_self)
    local store, scan, open, saved = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
    scan(1012, 6)
    local before = store:find(key)
    WoWUnit.AreEqual(1, before.totalGained)
    local source = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    WoWUnit.IsTrue(
        store:command("lootSourceProof", { slots = { { key = key, quantity = 1, source = source } } }, 1013, actor)
    )
    WoWUnit.AreEqual(1, #store:find(key).gains)
    WoWUnit.AreEqual(6, store:breakdown(key).recorded)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Boar)
    WoWUnit.IsTrue(
        not store:command("lootSourceProof", { slots = { { key = key, quantity = 1, source = source } } }, 1014, actor)
    )
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    local metadata = {
        id = "metadata",
        key = key,
        gainID = before.gains[1].id,
        quantity = 1,
        fromMethod = "Looted",
        method = "Looted",
        fromSource = source,
        source = source,
        link = "|cff00ff00|Hitem:2672::::::::|h[Fresh Meat]|h|r",
    }
    WoWUnit.IsTrue(store:correctGain(metadata))
    WoWUnit.AreEqual(2, #store:find(key).links)
    WoWUnit.AreEqual(6, store:breakdown(key).recorded)
    WoWUnit.IsTrue(not store:correctGain(metadata))
    local restored = addon.Schema.open(saved(), function() end)
    WoWUnit.IsTrue(not restored:correctGain(metadata))
    WoWUnit.AreEqual(6, restored:breakdown(key).recorded)
    WoWUnit.AreEqual(1, restored:breakdown(key).methods.Looted)
    WoWUnit.AreEqual(5, restored:breakdown(key).methods.Seen)
end

function tests.CorrectionsMoveMethodsAndRejectStaleOrUnderflowingProof(_self)
    local store, scan, open = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
    scan(1012, 6)
    local proof = {
        id = "method-proof",
        key = key,
        gainID = store:find(key).gains[1].id,
        quantity = 1,
        fromMethod = "Looted",
        method = "Quest",
        context = { kind = "quest", id = 42, name = "A Reward" },
    }
    WoWUnit.IsTrue(store:correctGain(proof))
    WoWUnit.AreEqual(6, store:breakdown(key).recorded)
    WoWUnit.AreEqual(nil, store:breakdown(key).methods.Looted)
    WoWUnit.AreEqual(1, store:breakdown(key).methods.Quest)
    WoWUnit.AreEqual(1, store:breakdown(key).sources["A Reward"])
    proof.id = "stale-proof"
    WoWUnit.IsTrue(not store:correctGain(proof))
    WoWUnit.AreEqual(6, store:breakdown(key).recorded)
    proof.fromMethod = "Quest"
    proof.method = "Looted"
    proof.context = nil
    proof.quantity = 2
    WoWUnit.IsTrue(not store:correctGain(proof))
    WoWUnit.AreEqual(1, store:breakdown(key).methods.Quest)
    WoWUnit.AreEqual(6, store:breakdown(key).recorded)
end

function tests.ProvenShareCanCoexistWithUnknownAndImproveLater(_self)
    local store, scan = fixture()
    local first = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    local second = { kind = "container", guid = "GameObject-0-1-2-3-6-7", name = "Chest" }
    WoWUnit.IsTrue(store:command("lootOpen", {
        slots = {
            { key = key, quantity = 1, source = first },
            { key = key, quantity = 2 },
        },
    }, 1010, { character = "Ada", realm = "Realm", level = 12, place = "Forest" }))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 3 }, 1011, actor))
    scan(1012, 8)
    WoWUnit.AreEqual(8, store:breakdown(key).recorded)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Boar)
    WoWUnit.AreEqual(2, store:breakdown(key).sources.Unknown)
    WoWUnit.IsTrue(store:command("lootSourceProof", {
        slots = {
            { key = key, quantity = 1, source = first },
            { key = key, quantity = 2, source = second },
        },
    }, 1013, actor))
    WoWUnit.AreEqual(8, store:breakdown(key).recorded)
    WoWUnit.AreEqual(2, store:breakdown(key).sources.Chest)
    WoWUnit.AreEqual(nil, store:breakdown(key).sources.Unknown)
    WoWUnit.IsTrue(not store:command("lootSourceProof", {
        slots = {
            { key = key, quantity = 1, source = first },
            { key = key, quantity = 2, source = second },
        },
    }, 1014, actor))
    WoWUnit.AreEqual(2, #store:find(key).gains)
    WoWUnit.AreEqual(3, store:find(key).totalGained)
end

function tests.LootAdapterPreservesEverySourcePair(_self)
    local store, scan = fixture()
    local sourceMode = "complete"
    local api = {
        GetNumLootItems = function()
            return 1
        end,
        GetLootSlotLink = function()
            return link
        end,
        GetLootSlotInfo = function()
            return nil, nil, 3
        end,
        GetLootSourceInfo = function()
            if sourceMode == "mismatch" then
                return "Creature-0-1-2-3-4-5", 1, "GameObject-0-1-2-3-6-7", 1
            elseif sourceMode == "same-source" then
                return "Creature-0-1-2-3-4-5", 1
            end
            return "Creature-0-1-2-3-4-5", 1, "GameObject-0-1-2-3-6-7", 2
        end,
    }
    local slots = addon.Loot.open(api)
    WoWUnit.AreEqual(2, #slots)
    WoWUnit.IsTrue(
        store:command(
            "lootOpen",
            { slots = slots },
            1010,
            { character = "Ada", realm = "Realm", level = 12, place = "Forest" }
        )
    )
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 3 }, 1011, actor))
    scan(1012, 8)
    WoWUnit.AreEqual(1, store:breakdown(key).sources["Mob #4"])
    WoWUnit.AreEqual(2, store:breakdown(key).sources["Container #6"])
    api.UnitGUID = function()
        return "Creature-0-1-2-3-4-5"
    end
    api.UnitName = function()
        return "Boar"
    end
    WoWUnit.IsTrue(store:command("lootSourceProof", { slots = addon.Loot.open(api) }, 1013, actor))
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Boar)
    WoWUnit.AreEqual(8, store:breakdown(key).recorded)
    WoWUnit.IsTrue(not store:command("lootSourceProof", { slots = addon.Loot.open(api) }, 1014, actor))
    WoWUnit.AreEqual(2, #store:find(key).gains)
    sourceMode = "mismatch"
    local mismatched = addon.Loot.open(api)
    WoWUnit.AreEqual(1, #mismatched)
    WoWUnit.AreEqual(nil, mismatched[1].source)
    WoWUnit.AreEqual(3, mismatched[1].quantity)
    sourceMode = "same-source"
    local sameSourceStack = addon.Loot.open(api)
    WoWUnit.AreEqual(1, #sameSourceStack)
    WoWUnit.AreEqual(3, sameSourceStack[1].quantity)
    WoWUnit.AreEqual("Creature-0-1-2-3-4-5", sameSourceStack[1].source.guid)
end

function tests.LaterUnreadableContainerNameKeepsTheObservedName(_self)
    local store, scan = fixture()
    local guid = "GameObject-0-6783-1-14-171938-0000422303"
    WoWUnit.IsTrue(store:command("lootOpen", {
        slots = {
            { key = key, quantity = 1, source = { kind = "container", guid = guid, name = "Cactus Apple" } },
        },
    }, 1010, { character = "Ada", realm = "Realm", level = 12, place = "Forest" }))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
    scan(1012, 6)
    WoWUnit.IsTrue(not store:command(
        "lootSourceProof",
        { slots = {
            { key = key, quantity = 1, source = { kind = "container", guid = guid } },
        } },
        1013,
        actor
    ))
    WoWUnit.AreEqual("Cactus Apple", store:find(key).gains[1].source.name)
    WoWUnit.AreEqual(1, store:breakdown(key).sources["Cactus Apple"])
    WoWUnit.AreEqual(1, store:find(key).totalGained)
end

function tests.MalformedScanCannotExpireOrChangeEvidence(_self)
    local store, _, open = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(not store:scan({
        character = "Ada",
        realm = "Realm",
        area = "bags",
        seenAt = 1070,
        complete = true,
        items = { { itemID = 0, quantity = 1 } },
    }))
    WoWUnit.AreEqual(0, #store:unresolved())
    WoWUnit.IsTrue(not store:command("lootReceipt", { key = key, quantity = 0 }, 1070, actor))
    WoWUnit.AreEqual(0, #store:unresolved())
    WoWUnit.IsTrue(
        not store:command("lootSourceProof", { slots = { { key = key, quantity = 1, source = {} } } }, 1070, actor)
    )
    WoWUnit.AreEqual(0, #store:unresolved())
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
end
