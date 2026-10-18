local _, companion = ...
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
    WoWUnit.IsTrue(store:setCharacter("Ada", "Realm"))
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
        return store:command(
            "lootOpen",
            { slots = { { key = key, quantity = 1, source = source } } },
            at,
            { character = actor.character, realm = actor.realm, level = actor.level, place = actor.place }
        )
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
    WoWUnit.IsTrue(not store:command("lootReceipt", { key = key, quantity = 1 }, 1070, actor))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual("expired", store:unresolved()[1].reason)
end

function tests.BookEvidenceShowsActiveAndEndedMatchesWithoutGains(_self)
    local store, _, open, saved = fixture()
    WoWUnit.IsTrue(open(1010))
    local revision = store:revision()
    local result = addon.Collection.evidenceQuery(store, { search = "Meat", character = "Ada", realm = "Realm" })
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual("Still checking", result.rows[1].status)
    WoWUnit.AreEqual(revision, store:revision())
    WoWUnit.IsTrue(store:expireEvidence(1070))
    result = addon.Collection.evidenceQuery(store, {})
    WoWUnit.AreEqual(1, #result.rows)
    WoWUnit.AreEqual("Timed out", result.rows[1].status)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual(0, #addon.Collection.evidenceQuery(store, { search = "Sword" }).rows)
    WoWUnit.IsTrue(open(1080))
    local restored = addon.Schema.open(saved(), function() end)
    result = addon.Collection.evidenceQuery(restored, {})
    WoWUnit.AreEqual("Login interrupted", result.rows[1].status)
    WoWUnit.AreEqual(0, restored:find(key).totalGained)
end

function tests.CompletedLootDoesNotHideTheNextSource(_self)
    local store, scan, open = fixture()
    local first = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    local second = { kind = "mob", guid = "Creature-0-1-2-3-5-6", name = "Wolf" }
    WoWUnit.IsTrue(open(1010, first))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
    scan(1012, 6)
    WoWUnit.IsTrue(store:command("lootClose", nil, 1012, actor))
    WoWUnit.IsTrue(open(1020, second))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1021, actor))
    scan(1022, 7)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Boar)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Wolf)
    WoWUnit.AreEqual(nil, store:breakdown(key).sources.Unknown)
    WoWUnit.AreEqual(2, store:find(key).totalGained)
end

function tests.SameCorpseSlotsKeepTheSourceOfPartialLoot(_self)
    local store, scan = fixture()
    local source = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    WoWUnit.IsTrue(store:command("lootOpen", {
        slots = {
            { key = key, quantity = 2, source = source },
            { key = key, quantity = 2, source = source },
        },
    }, 1010, { character = actor.character, realm = actor.realm, level = actor.level, place = actor.place }))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 2 }, 1011, actor))
    scan(1012, 7)
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    WoWUnit.AreEqual(2, store:breakdown(key).sources.Boar)
    WoWUnit.AreEqual(nil, store:breakdown(key).sources.Unknown)
end

function tests.UnsettledLootStillCompetesForTheNextSource(_self)
    local store, scan, open = fixture()
    WoWUnit.IsTrue(open(1010, { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }))
    WoWUnit.IsTrue(store:command("lootClose", nil, 1011, actor))
    WoWUnit.IsTrue(open(1020, { kind = "mob", guid = "Creature-0-1-2-3-5-6", name = "Wolf" }))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1021, actor))
    scan(1022, 6)
    WoWUnit.AreEqual(1, store:breakdown(key).sources.Unknown)
    WoWUnit.AreEqual(nil, store:breakdown(key).sources.Wolf)
end

function tests.CompletedLootDoesNotHideALaterReadableSlot(_self)
    local store, scan, open = fixture()
    local source = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    WoWUnit.IsTrue(open(1010, source))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
    scan(1012, 6)
    WoWUnit.IsTrue(store:command("lootClose", nil, 1012, actor))
    WoWUnit.IsTrue(
        store:command(
            "lootOpen",
            { slots = {} },
            1020,
            { character = actor.character, realm = actor.realm, level = actor.level, place = actor.place }
        )
    )
    WoWUnit.IsTrue(
        store:command("lootSourceProof", { slots = { { key = key, quantity = 1, source = source } } }, 1021, actor)
    )
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1022, actor))
    scan(1023, 7)
    WoWUnit.AreEqual(2, store:breakdown(key).sources.Boar)
    WoWUnit.AreEqual(nil, store:breakdown(key).sources.Unknown)
end

function tests.LaterSourceProofMovesTheSameUnitsOnce(_self)
    local store, scan, open = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
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
    local store, _, open, saved = fixture()
    WoWUnit.IsTrue(open(1010))
    for _ = 1, 255 do
        WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
        WoWUnit.AreEqual(0, store:find(key).totalGained)
    end
    for _ = 1, 2001 do
        WoWUnit.IsTrue(not store:command("lootReceipt", { key = key, quantity = 1 }, 1012, actor))
        WoWUnit.AreEqual(0, store:find(key).totalGained)
    end
    WoWUnit.AreEqual(2000, #store:unresolved())
    local summary = store:evidenceSummary()
    WoWUnit.AreEqual(1, summary.discarded)
    WoWUnit.AreEqual(1012, summary.firstDiscarded)
    WoWUnit.AreEqual(1012, summary.lastDiscarded)
    local review = addon.Collection.evidenceQuery(store, {})
    WoWUnit.AreEqual(1, review.discarded)
    WoWUnit.IsTrue(
        addon.BookRender.warning(store):find("1 item changes need review; details discarded", 1, true) ~= nil
    )
    -- The cap is per character, while the unresolved limit is account-wide:
    -- once Ben logs in, Ada's overflow does not limit him.
    store = addon.Schema.open(saved(), function() end)
    WoWUnit.IsTrue(store:setCharacter("Ben", "Realm"))
    WoWUnit.AreEqual(2000, #store:unresolved())
    WoWUnit.IsTrue(
        store:scan({ character = "Ben", realm = "Realm", area = "bags", seenAt = 1012, complete = true, items = {} })
    )
    WoWUnit.IsTrue(
        store:command(
            "lootOpen",
            { slots = { { key = key, quantity = 1 } } },
            1012,
            { character = "Ben", realm = "Realm", level = 12, place = "Forest" }
        )
    )
    WoWUnit.AreEqual(0, store:find(key).totalGained)
end

function tests.ReloadEndsUnmatchedCorrelation(_self)
    local store, _, open, saved = fixture()
    WoWUnit.IsTrue(open(1010))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1011, actor))
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    local restored = addon.Schema.open(saved(), function() end)
    WoWUnit.IsTrue(restored:setCharacter("Ada", "Realm"))
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
    WoWUnit.IsTrue(not restored:command("lootReceipt", { key = key, quantity = 1 }, 1013, actor))
    WoWUnit.AreEqual(0, restored:find(key).totalGained)
end

function tests.CompetingSourcesAllocateOnlyProvenShares(_self)
    local store, scan = fixture()
    local first = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Boar" }
    local second = { kind = "container", guid = "GameObject-0-1-2-3-6-7", name = "Chest" }
    WoWUnit.IsTrue(store:command("lootOpen", {
        slots = {
            { key = key, quantity = 1, source = first },
            { key = key, quantity = 2, source = second },
        },
    }, 1010, { character = "Ada", realm = "Realm", level = 12, place = "Forest" }))
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 3 }, 1011, actor))
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
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 3 }, 1014, actor))
    WoWUnit.AreEqual(3, store:find(key).totalGained)
    WoWUnit.AreEqual(2, #store:find(key).gains)
end

companion.evidence = { link = link, key = key, actor = actor, fixture = fixture }
