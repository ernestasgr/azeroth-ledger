local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")
local link = "|Hitem:2672::::::::|h[Meat]|h"
local key = "2672:0"
local actor = { character = "Ada", realm = "Realm", level = 12, place = "Forest" }

local function fixture()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local function scan(at, quantity)
        WoWUnit.IsTrue(store:scan({
            character = actor.character,
            realm = actor.realm,
            area = "bags",
            seenAt = at,
            complete = true,
            items = quantity > 0 and { { itemID = 2672, link = link, quantity = quantity } } or {},
        }))
    end
    local function open(at, source)
        return store:lootOpen({
            character = actor.character,
            realm = actor.realm,
            level = actor.level,
            place = actor.place,
            at = at,
            slots = { { key = key, quantity = 1, source = source } },
        })
    end
    scan(1000, 5)
    return store, scan, open, function()
        return saved
    end
end

function tests.ExpiredLootEvidenceCannotBecomeAGain(_self)
    local store, scan, open = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    scan(1070, 6)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.IsTrue(not store:lootReceipt({ key = key, quantity = 1 }, 1070, actor))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual("expired", store:unresolved()[1].reason)
end

function tests.LaterSourceProofMovesTheSameUnitsOnce(_self)
    local store, scan, open = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 1011, actor))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    scan(1012, 6)
    local record = store:find(key)
    WoWUnit.AreEqual(1, record.totalGained)
    WoWUnit.AreEqual(nil, record.gains[1].source)
    local proof = {
        id = "slot-proof",
        key = key,
        gainID = record.gains[1].id,
        quantity = 1,
        fromMethod = "Looted",
        method = "Looted",
        source = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" },
        link = link,
    }
    WoWUnit.IsTrue(store:correctGain(proof))
    record = store:find(key)
    WoWUnit.AreEqual(1, record.totalGained)
    WoWUnit.AreEqual(6, record.firstSeenUnits + record.totalGained)
    WoWUnit.AreEqual("Boar", record.gains[1].source.name)
    WoWUnit.AreEqual(1, #record.gains)
    WoWUnit.IsTrue(not store:correctGain(proof))
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    proof.id = "bad-quantity"
    proof.quantity = 2
    WoWUnit.IsTrue(not store:correctGain(proof))
    WoWUnit.AreEqual("Boar", store:find(key).gains[1].source.name)
    proof.quantity = 1
    proof.link = "|Hitem:100::::::::|h[Sword]|h"
    WoWUnit.IsTrue(not store:correctGain(proof))
    WoWUnit.AreEqual(6, store:find(key).firstSeenUnits + store:find(key).totalGained)
end

function tests.UnreadableVariantsWaitForIdentifiableData(_self)
    local store = addon.Schema.open(nil, function() end)
    local api = {
        UnitName = function()
            return "Ada"
        end,
        GetRealmName = function()
            return "Realm"
        end,
        GetServerTime = function()
            return 1000
        end,
        C_Container = {
            GetContainerNumSlots = function(bag)
                return bag == 0 and 1 or 0
            end,
            GetContainerItemInfo = function()
                return { itemID = 2672, stackCount = 2 }
            end,
        },
    }
    WoWUnit.AreEqual(nil, addon.Item.key("|Hitem:2672|h[Meat]|h", 2672))
    WoWUnit.IsTrue(store:scan(addon.Scan.capture(api, "bags", false)))
    WoWUnit.AreEqual(0, #store:list())
    WoWUnit.AreEqual(1, #store:unresolved())
    WoWUnit.AreEqual(2, store:unresolved()[1].detail.quantity)
    WoWUnit.IsTrue(store:scan(addon.Scan.capture(api, "bags", false)))
    WoWUnit.AreEqual(1, #store:unresolved())
    api.C_Container.GetContainerItemInfo = function()
        return { itemID = 2672, hyperlink = link, stackCount = 2 }
    end
    WoWUnit.IsTrue(store:scan(addon.Scan.capture(api, "bags", false)))
    WoWUnit.AreEqual(0, #store:unresolved())
    WoWUnit.AreEqual(2, store:find(key).firstSeenUnits)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.IsTrue(store:scan(addon.Scan.capture(api, "bags", false)))
    WoWUnit.AreEqual(2, store:find(key).firstSeenUnits)
end

function tests.CandidateOverflowRetainsDetailsAndWarnsAtAccountLimit(_self)
    local store, _, open = fixture()
    WoWUnit.IsTrue(open(1010))
    for _ = 1, 255 do
        WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 1011, actor))
        WoWUnit.AreEqual(0, store:find(key).totalGained)
    end
    for _ = 1, 2001 do
        WoWUnit.IsTrue(not store:lootReceipt({ key = key, quantity = 1 }, 1012, actor))
        WoWUnit.AreEqual(0, store:find(key).totalGained)
    end
    WoWUnit.AreEqual(2000, #store:unresolved())
    local summary = store:evidenceSummary()
    WoWUnit.AreEqual(1, summary.discarded)
    WoWUnit.AreEqual(1012, summary.firstDiscarded)
    WoWUnit.AreEqual(1012, summary.lastDiscarded)
    local warning = false
    for _, lineText in ipairs(addon.Collection.lines(store, "Ada", "Realm")) do
        if lineText:find("WARNING", 1, true) and lineText:find("discarded", 1, true) then
            warning = true
        end
    end
    WoWUnit.IsTrue(warning)
    -- The cap is per character, while the unresolved limit is account-wide.
    WoWUnit.IsTrue(
        store:scan({ character = "Ben", realm = "Realm", area = "bags", seenAt = 1012, complete = true, items = {} })
    )
    WoWUnit.IsTrue(store:lootOpen({
        character = "Ben",
        realm = "Realm",
        at = 1012,
        level = 12,
        place = "Forest",
        slots = { { key = key, quantity = 1 } },
    }))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
end

function tests.ReloadEndsUnmatchedCorrelation(_self)
    local store, _, open, saved = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 1011, actor))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    local restored = addon.Schema.open(saved(), function() end)
    WoWUnit.AreEqual("reload", restored:unresolved()[1].reason)
    WoWUnit.IsTrue(restored:scan({
        character = "Ada",
        realm = "Realm",
        area = "bags",
        seenAt = 1012,
        complete = true,
        items = { { itemID = 2672, link = link, quantity = 6 } },
    }))
    WoWUnit.AreEqual(0, restored:find(key).totalGained)
    WoWUnit.IsTrue(not restored:lootReceipt({ key = key, quantity = 1 }, 1013, actor))
    WoWUnit.AreEqual(0, restored:find(key).totalGained)
end

function tests.CompetingSourcesAllocateOnlyProvenShares(_self)
    local store, scan = fixture()
    local first = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    local second = { kind = "container", guid = "GameObject-0-1-2-3-6-7", name = "Chest" }
    WoWUnit.IsTrue(store:lootOpen({
        character = "Ada",
        realm = "Realm",
        at = 1010,
        level = 12,
        place = "Forest",
        slots = {
            { key = key, quantity = 1, source = first },
            { key = key, quantity = 2, source = second },
        },
    }))
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 3 }, 1011, actor))
    scan(1012, 6)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    WoWUnit.AreEqual(nil, store:find(key).gains[1].source)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Unknown)
    scan(1013, 8)
    WoWUnit.AreEqual(3, store:find(key).totalGained)
    WoWUnit.AreEqual(8, store:breakdown(key).recorded)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Boar)
    WoWUnit.AreEqual(2, store:breakdown(key).sources.Chest)
    WoWUnit.AreEqual(nil, store:breakdown(key).sources.Unknown)
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 3 }, 1014, actor))
    WoWUnit.AreEqual(3, store:find(key).totalGained)
    WoWUnit.AreEqual(2, #store:find(key).gains)
end

function tests.DelayedSlotProofAndMetadataEnrichWithoutNewUnits(_self)
    local store, scan, open, saved = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 1011, actor))
    scan(1012, 6)
    local before = store:find(key)
    WoWUnit.AreEqual(1, before.totalGained)
    local source = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    WoWUnit.IsTrue(store:lootSourceProof({ { key = key, quantity = 1, source = source } }, 1013, actor))
    WoWUnit.AreEqual(1, #store:find(key).gains)
    WoWUnit.AreEqual(6, store:breakdown(key).recorded)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Boar)
    WoWUnit.IsTrue(not store:lootSourceProof({ { key = key, quantity = 1, source = source } }, 1014, actor))
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
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 1011, actor))
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
