local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("Collection")

date = os.date
local fixture = assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))()
local saved = fixture(10000)
local store = addon.Schema.open(saved, function(value)
    saved = value
end)
assert(store:diagnostic().kind == "healthy")
local instructions = 0
debug.sethook(function()
    instructions = instructions + 1000
end, "", 1000)
assert(store:scan({
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 1002,
    complete = true,
    items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 1 } },
}))
debug.sethook()
assert(instructions < 250000, "Normal bag scan traversed the large ledger: " .. instructions .. " instructions")
local removed = store:find("10002:0")
assert(removed.observations[#removed.observations].quantity == 0)
assert(store:find("20000:0").totalGained == 2)
assert(#store:find("20000:0").links == 2)
print("performance_spec: selective scan passed")

local clock, reads = 0, 0
local api = {
    debugprofilestop = function()
        clock = clock + 0.05
        return clock
    end,
}
local query = addon.Collection.startQuery(api, store, "Fixture", "Test", {}, function()
    reads = reads + 1
    return { category = "Materials", icon = 1 }
end)
local result = query:step()
assert(result == nil and reads < 50, "Opening a large Collection must yield before loading every item")
local frames = 1
repeat
    result = query:step()
    frames = frames + 1
until result
assert(frames > 2 and result.discoveryCount == 10000 and #result.rows == 10000)
assert(result.rows[1].name == "Item 00001" and result.rows[10000].name == "Item 10000")
assert(store:setRetention("gains", 0) and store:setRetention("vendor", 0) and store:setRetention("transfers", 0))
assert(#store:journal() == 0)
local restored = addon.Schema.open(saved, function(value)
    saved = value
end)
assert(restored:count() == 10000)
assert(restored:breakdown("20000:0").recorded == 3)
assert(restored:breakdown("20000:0").sources["Mob #10000"] == 2)
assert(#restored:find("20000:0").links == 2)
print("performance_spec: budgeted browsing and permanent facts passed")

load.addon("Book", addon, "Collection")
local native = assert(loadfile("tests/support/native_ui.lua"))().create()
local metadataReads = 0
native.api.debugprofilestop = api.debugprofilestop
native.api.C_Item = {
    GetItemInfo = function(link)
        metadataReads = metadataReads + 1
        return "Fixture", link, 1, nil, nil, nil, nil, nil, nil, 1, nil, 7
    end,
}
local frame = addon.Collection.open(native.api, restored, "Fixture", "Test")
local function visible(text)
    for _, control in ipairs(native.controls) do
        if control.text == text and control:IsVisible() then
            return control
        end
    end
end
assert(visible("Loading your Collection…"), "Large native book should show loading immediately")
for _ = 1, 12000 do
    if visible("10000 items") then
        break
    end
    frame.scripts.OnUpdate(frame)
end
assert(visible("10000 items"), "Native book must finish its query across frames")
frame.scripts.OnKeyDown(frame, "ENTER")
local beforePage = metadataReads
frame.scripts.OnKeyDown(frame, "PAGEDOWN")
assert(visible("2 / 1429"))
assert(metadataReads - beforePage < 20, "Paging must reuse its completed query")
frame.scripts.OnEvent(frame, "ITEM_DATA_LOAD_RESULT", 10001, true)
frame.scripts.OnUpdate(frame)
assert(not visible("Loading your Collection…"), "Metadata refresh should keep the completed Collection visible")
assert(visible("2 / 1429"), "Metadata refresh must preserve the current page")
for _ = 1, 12000 do
    if visible("10000 items") then
        break
    end
    frame.scripts.OnUpdate(frame)
end
assert(visible("10000 items") and visible("2 / 1429"), "A background refresh must preserve the current page")
print("performance_spec: native loading and cached paging passed")

local raw = fixture(3)
local failSave = false
local atomic = addon.Schema.open(raw, function()
    if failSave then
        error("test save failure")
    end
end)
local priorRevision = atomic:revision()
failSave = true
local accepted = pcall(
    atomic.scan,
    atomic,
    { character = "Fixture", realm = "Test", area = "bags", seenAt = 1002, complete = true, items = {} }
)
assert(not accepted and atomic:revision() == priorRevision)
assert(atomic:find("10001:0").observations[1].quantity == 1)
assert(addon.Schema.open(raw, function() end):find("10001:0").observations[1].quantity == 1)
failSave = false
assert(
    atomic:scan({ character = "Fixture", realm = "Test", area = "bags", seenAt = 1002, complete = true, items = {} })
)
local cleared = atomic:find("10001:0").observations
assert(cleared[#cleared].quantity == 0, "Failed save must leave the held-item index usable")
print("performance_spec: failed save preserves public and saved facts")

local repeated = {}
assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))("Tests", repeated)
local unorderedRaw = repeated.repeatedFixture(5, 5)
unorderedRaw.records["10001:0"].observations = {
    { character = "Fixture", realm = "Test", area = "bags", quantity = 1, seenAt = 1001 },
    { character = "Fixture", realm = "Test", area = "bags", quantity = 5, seenAt = 1005 },
    { character = "Fixture", realm = "Test", area = "bags", quantity = 2, seenAt = 1002 },
}
local unordered = addon.Schema.open(unorderedRaw, function() end)
assert(unordered:diagnostic().kind == "healthy")
local unorderedSeen = addon.LastSeen.project(unordered, unordered:find("10001:0"), "Fixture", "Test")
assert(
    unorderedSeen.checks[1].observedQuantity == 5 and unorderedSeen.checks[1].observedAt == 1005,
    "Compaction must preserve dated observations even when array order differs from timestamps"
)
local repeatedRaw = repeated.repeatedFixture(5000, 5000)
local repeatedStore = addon.Schema.open(repeatedRaw, function(value)
    repeatedRaw = value
end)
assert(repeatedStore:diagnostic().kind == "healthy")
instructions = 0
debug.sethook(function()
    instructions = instructions + 1000
end, "", 1000)
assert(repeatedStore:scan({
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 7000,
    complete = true,
    items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 5001 } },
}))
debug.sethook()
print("repeated scan instructions", instructions)
assert(instructions < 250000, "Repeated-item scan traversed lifetime history: " .. instructions)

instructions = 0
debug.sethook(function()
    instructions = instructions + 1000
end, "", 1000)
local repeatedJournal = repeatedStore:journal()
debug.sethook()
print("repeated Journal instructions", instructions)
assert(instructions < 4000000, "Retained Journal lookup traversed lifetime history: " .. instructions)
assert(#repeatedJournal == 5002 and repeatedJournal[1].contributions[1].at == 6000)
assert(repeatedJournal[1].contributions[1].source.name == "Fixture mob")
local repeatedRecord = repeatedStore:find("10001:0")
assert(#repeatedRecord.observations == 2 and repeatedRecord.observations[1].quantity == 1)
assert(repeatedRecord.observations[2].quantity == 5001)
assert(repeatedRecord.firstGained == 1001 and repeatedRecord.lastGained == 6000)
assert(repeatedStore:breakdown("10001:0").methods.Looted == 5000)
assert(repeatedStore:breakdown("10001:0").sources["Fixture mob"] == 5000)
local checked = addon.LastSeen.project(repeatedStore, repeatedRecord, "Fixture", "Test")
assert(checked.characterOverall == 5001 and checked.allCharactersOverall == 5001)
assert(checked.characterCurrent == 5001 and checked.allCharactersCurrent == 5001)
-- Public identity and activity copies cannot change indexed permanent facts.
local description = repeatedStore:describe("10001:0")
description.links[1], description.observations[1].quantity = "changed", 999
repeatedJournal[1].contributions[1].source.name = "changed"
assert(repeatedStore:journal()[1].contributions[1].source.name == "Fixture mob")
assert(repeatedStore:find("10001:0").observations[1].quantity == 1)

local metadataCalls, queryFrames = 0, 0
local session = addon.BookQuery.new(api)
local journalResult = session:step(repeatedStore, "Fixture", "Test", { view = "Journal" })
assert(not journalResult, "Maximum retained Journal must load cooperatively")
repeat
    journalResult = session:step(repeatedStore, "Fixture", "Test", { view = "Journal" })
    queryFrames = queryFrames + 1
until journalResult
assert(queryFrames > 2 and #journalResult.rows == 5002)
assert(journalResult.rows[1].quantity == 1 and journalResult.rows[1].record.gains == nil)
assert(repeatedStore:correctGain({
    id = "retained-proof",
    key = "10001:0",
    gainID = "repeated:1:5000",
    quantity = 1,
    fromMethod = "Looted",
    fromSource = { kind = "mob", guid = "Creature-0-0-0-0-123-0", name = "Fixture mob" },
    method = "Quest",
    context = { kind = "quest", id = 123 },
}))
assert(#repeatedStore:journal() == 5002 and repeatedStore:journal()[1].contributions[1].method == "Quest")
local hugeRaw = repeated.repeatedFixture(50000, 0, 3)
local huge = addon.Schema.open(hugeRaw, function(value)
    hugeRaw = value
end)
local hugeQuery = addon.Collection.startQuery(api, huge, "Fixture", "Test", {}, function()
    metadataCalls = metadataCalls + 1
    return { category = "Materials", icon = 1 }
end)
assert(hugeQuery:step() == nil and metadataCalls == 0, "Copying one lifetime history must yield")
local hugeResult
repeat
    hugeResult = hugeQuery:step()
until hugeResult
assert(#hugeResult.rows == 3 and hugeResult.rows[1].record.totalGained == 50000)
for _, category in ipairs({ "gains", "transfers", "vendor" }) do
    assert(huge:setRetention(category, 0))
end
assert(#huge:journal() == 0)
instructions = 0
debug.sethook(function()
    instructions = instructions + 1000
end, "", 1000)
assert(huge:scan({
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 60000,
    complete = true,
    items = {},
}))
debug.sethook()
assert(instructions < 250000, "Three long-lived items exceeded the selective scan budget: " .. instructions)
local reopened = addon.Schema.open(hugeRaw, function() end)
assert(#reopened:journal() == 0 and reopened:count() == 3)
assert(reopened:breakdown("10001:0").sources["Fixture mob"] == 50000)
assert(#reopened:find("10001:0").links == 2)
assert(#reopened:find("10001:0").observations == 2)
local inspectionSession = addon.BookQuery.new(api)
local inspection, inspectionPending = inspectionSession:inspect(huge, "10001:0", "Fixture", "Test", {})
assert(not inspection and inspectionPending, "Details for a long history must yield")
repeat
    inspection, inspectionPending = inspectionSession:inspect(huge, "10001:0", "Fixture", "Test", {})
until not inspectionPending
assert(inspection.breakdown.gained == 50000 and inspection.firstGained == 1001)
assert(
    inspectionSession:inspect(huge, "10001:0", "Fixture", "Test", {}) == inspection,
    "Paging the same item's Journal must reuse its completed details"
)
-- Visible paging must reuse lifetime details for the selected item.
assert(repeatedStore:setBook({ version = 1, filter = { view = "Journal" } }))
local repeatedFrame = addon.Collection.open(native.api, repeatedStore, "Fixture", "Test")
for _ = 1, 20000 do
    repeatedFrame.scripts.OnUpdate(repeatedFrame)
    if visible("5002 entries") and not visible("Loading item details…") then
        break
    end
end
assert(visible("5002 entries") and not visible("Loading item details…"))
local detailFrames = addon.Work.timings["Item details"].frames
local priorMetadata = metadataReads
repeatedFrame.scripts.OnKeyDown(repeatedFrame, "ENTER")
repeatedFrame.scripts.OnKeyDown(repeatedFrame, "PAGEDOWN")
assert(visible("2 / 715") and metadataReads - priorMetadata < 20)
assert(addon.Work.timings["Item details"].frames == detailFrames)
repeatedFrame.scripts.OnEvent(repeatedFrame, "ITEM_DATA_LOAD_RESULT", 10001, true)
repeatedFrame.scripts.OnUpdate(repeatedFrame)
assert(not visible("Loading your Journal…"), "Metadata refresh should keep the completed Journal visible")
assert(visible("2 / 715"), "Journal metadata refresh must preserve the current page")
for _ = 1, 20000 do
    repeatedFrame.scripts.OnUpdate(repeatedFrame)
    if visible("5002 entries") then
        break
    end
end
assert(visible("5002 entries") and visible("2 / 715"))
local fewRaw = repeated.repeatedFixture(2000, 5000, 3)
local few = addon.Schema.open(fewRaw, function(value)
    fewRaw = value
end)
assert(#few:journal() == 5006 and few:count() == 3)
-- A failed save cannot change a shared gain, a quantity observation, or its index.
local failedRaw = repeated.repeatedFixture(5000, 5000)
local failing = addon.Schema.open(failedRaw, function()
    error("save failed")
end)
local failingRevision = failing:revision()
assert(
    not pcall(
        failing.scan,
        failing,
        { character = "Fixture", realm = "Test", area = "bags", seenAt = 7000, complete = true, items = {} }
    )
)
assert(failing:revision() == failingRevision and #failing:journal() == 5002)
assert(failing:find("10001:0").observations[2].quantity == 5000)
assert(addon.Schema.open(failedRaw, function() end):find("10001:0").observations[2].quantity == 5000)
print("performance_spec: repeated-item history, retention and cooperative queries passed")

for _, gainCount in ipairs({ 5000, 50000 }) do
    local acquisitionRaw = repeated.repeatedFixture(gainCount, 5000)
    local acquisition = addon.Schema.open(acquisitionRaw, function(value)
        acquisitionRaw = value
    end)
    local gainActor = { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }
    assert(
        acquisition:rewardReceipt(
            { key = "10001:0", quantity = 1, method = "Crafted", context = { kind = "recipe", id = 123 } },
            1001 + gainCount,
            gainActor
        )
    )
    instructions = 0
    debug.sethook(function()
        instructions = instructions + 1000
    end, "", 1000)
    assert(acquisition:scan({
        character = "Fixture",
        realm = "Test",
        area = "bags",
        seenAt = 1002 + gainCount,
        complete = true,
        items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = gainCount + 1 } },
    }))
    debug.sethook()
    print("confirmed acquisition instructions", gainCount, instructions)
    assert(instructions < 250000, "Confirmed acquisition traversed lifetime history: " .. instructions)
    assert(acquisition:breakdown("10001:0").methods.Crafted == 1)
    assert(addon.Schema.open(acquisitionRaw, function() end):diagnostic().kind == "healthy")
    instructions = 0
    debug.sethook(function()
        instructions = instructions + 1000
    end, "", 1000)
    local tooltip = addon.Presentation.line(acquisition, "|Hitem:10001::::::::|h[Item 00001]|h", "Fixture", "Test")
    debug.sethook()
    assert(
        instructions < 250000 and tooltip:find("Crafted", 1, true),
        "Tooltip traversed lifetime history: " .. instructions
    )
    print("tooltip instructions", gainCount, instructions)
end

local retryRaw = repeated.repeatedFixture(5000, 5000)
local failGainSave = false
local retryStore
retryStore = addon.Schema.open(retryRaw, function(value)
    if failGainSave then
        assert(retryStore:find("10001:0").totalGained == 5000)
        assert(#retryStore:find("10001:0").gains == 5000)
        error("gain save failed")
    end
    retryRaw = value
end)
assert(
    retryStore:rewardReceipt(
        { key = "10001:0", quantity = 3, method = "Crafted", context = { kind = "recipe", id = 123 } },
        6001,
        { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }
    )
)
failGainSave = true
local retrySnapshot = {
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 6002,
    complete = true,
    items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 5001 } },
}
assert(not pcall(retryStore.scan, retryStore, retrySnapshot))
assert(retryStore:find("10001:0").totalGained == 5000 and #retryStore:journal() == 5002)
assert(#retryRaw.records["10001:0"].gains == 5000)
failGainSave = false
assert(retryStore:scan(retrySnapshot))
assert(retryStore:find("10001:0").totalGained == 5001)
retrySnapshot.seenAt, retrySnapshot.items[1].quantity = 6003, 5003
assert(retryStore:scan(retrySnapshot))
assert(retryStore:breakdown("10001:0").methods.Crafted == 3)
assert(retryStore:journal()[1].contributions[1].quantity == 3 and #retryStore:journal() == 5002)
assert(addon.Schema.open(retryRaw, function() end):diagnostic().kind == "healthy")

for _, channel in ipairs({ "vendor", "mail", "loot" }) do
    local failureRaw = repeated.repeatedFixture(5000, 5000)
    local failingSave = false
    local failureStore = addon.Schema.open(failureRaw, function(value)
        if failingSave then
            error("failed " .. channel .. " save")
        end
        failureRaw = value
    end)
    local actor = { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }
    local link = "|Hitem:10001::::::::|h[Item 00001]|h"
    if channel == "vendor" then
        assert(
            failureStore:vendorAction(
                { kind = "purchase", key = "10001:0", itemID = 10001, link = link, quantity = 1 },
                6001,
                actor
            )
        )
        assert(failureStore:vendorReceipt({ key = "10001:0", quantity = 1 }, 6001, actor))
    elseif channel == "mail" then
        local id = assert(failureStore:exchangeIntent({
            channel = "mail",
            direction = "in",
            key = "10001:0",
            itemID = 10001,
            link = link,
            quantity = 1,
            peerName = "Outside",
            peerRealm = "Test",
        }, 6001, actor))
        assert(failureStore:exchangeConfirm("mail", "in", 6001, actor, id))
    else
        assert(failureStore:scan({
            character = "Fixture",
            realm = "Test",
            area = "equipped",
            seenAt = 6000,
            complete = true,
            items = {},
        }))
        assert(failureStore:lootOpen({
            character = "Fixture",
            realm = "Test",
            level = 1,
            place = "Test zone",
            at = 6001,
            slots = {
                {
                    key = "10001:0",
                    quantity = 1,
                    source = { kind = "mob", guid = "Creature-0-0-0-0-123-0", name = "Fixture mob" },
                },
            },
        }))
        assert(failureStore:lootReceipt({ key = "10001:0", quantity = 1 }, 6001, actor))
    end
    local snapshot = {
        character = "Fixture",
        realm = "Test",
        area = "bags",
        seenAt = 6002,
        complete = true,
        items = { { itemID = 10001, link = link, quantity = 5001 } },
    }
    failingSave = true
    assert(not pcall(failureStore.scan, failureStore, snapshot))
    assert(failureStore:find("10001:0").totalGained == 5000 and #failureRaw.records["10001:0"].gains == 5000)
    failingSave = false
    instructions = 0
    debug.sethook(function()
        instructions = instructions + 1000
    end, "", 1000)
    assert(failureStore:scan(snapshot))
    debug.sethook()
    assert(instructions < 250000, "Confirmed " .. channel .. " scan exceeded budget: " .. instructions)
    assert(failureStore:find("10001:0").totalGained == 5001, "Retry lost the " .. channel .. " gain")
    assert(addon.Schema.open(failureRaw, function() end):diagnostic().kind == "healthy")
end

-- A receipt can arrive after the quantity scan; failed settlement must remain retryable.
local lateRaw = repeated.repeatedFixture(5000, 5000)
local lateFail = false
local lateStore = addon.Schema.open(lateRaw, function(value)
    if lateFail then
        error("late receipt save failed")
    end
    lateRaw = value
end)
assert(lateStore:scan({
    character = "Fixture",
    realm = "Test",
    area = "equipped",
    seenAt = 6000,
    complete = true,
    items = {},
}))
assert(lateStore:lootOpen({
    character = "Fixture",
    realm = "Test",
    level = 1,
    place = "Test zone",
    at = 6001,
    slots = {
        {
            key = "10001:0",
            quantity = 1,
            source = { kind = "mob", guid = "Creature-0-0-0-0-123-0", name = "Fixture mob" },
        },
    },
}))
assert(lateStore:scan({
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 6002,
    complete = true,
    items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 5001 } },
}))
local lateReceipt, lateActor = { key = "10001:0", quantity = 1 }, { character = "Fixture", realm = "Test" }
lateFail = true
assert(not pcall(lateStore.lootReceipt, lateStore, lateReceipt, 6003, lateActor))
assert(lateStore:find("10001:0").totalGained == 5000 and #lateRaw.records["10001:0"].gains == 5000)
lateFail = false
instructions = 0
debug.sethook(function()
    instructions = instructions + 1000
end, "", 1000)
assert(lateStore:lootReceipt(lateReceipt, 6003, lateActor))
debug.sethook()
assert(instructions < 250000 and lateStore:find("10001:0").totalGained == 5001)
