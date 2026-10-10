local addon = {}
for _, name in ipairs({
    "Item",
    "Work",
    "Schema",
    "Client",
    "Scan",
    "Inventory",
    "LastSeen",
    "Collection",
    "Journal",
    "BookQuery",
    "Presentation",
}) do
    assert(loadfile("AzerothLedger/" .. name .. ".lua"))("AzerothLedger", addon)
end
date = os.date

local fixture = assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))()
local function storeWith(count)
    return addon.Schema.open(fixture(count), function() end)
end
local clock, reads = 0, 0
local metadataCategory = "Materials"
local queryApi = {
    debugprofilestop = function()
        clock = clock + 0.2
        return clock
    end,
}
addon.Client.itemMetadata = function()
    reads = reads + 1
    return { category = metadataCategory, gear = true, loading = false }
end
local function finish(query, store, filter)
    for _ = 1, 3000 do
        local result, pending = query:step(store, "Fixture", "Test", filter)
        if result then
            assert(not pending)
            return result
        end
        assert(pending)
    end
    error("Query never reached a current result")
end

-- A running cursor can see new facts; its result must be discarded if the store
-- changed, and the next completed result must include every current discovery.
local store = storeWith(180)
local query = addon.BookQuery.new(queryApi)
---@type AzerothLedgerCollectionFilter
local filter = {}
assert(query:step(store, "Fixture", "Test", filter) == nil)
assert(store:scan({
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 1002,
    complete = true,
    items = { { itemID = 999, link = "|Hitem:999::::::::|h[New item]|h", quantity = 1 } },
}))
for _ = 1, 5 do
    query:metadataChanged()
    assert(query:step(store, "Fixture", "Test", filter) == nil)
end
local result = finish(query, store, filter)
assert(result.discoveryCount == 181 and #result.rows == 181)
assert(result.byKey["999:0"].ownershipState == "present")
local priorReads = reads
assert(query:step(store, "Fixture", "Test", {}) == result)
assert(reads == priorReads, "Equivalent filters must reuse the completed query")

-- Filter/view/store changes replace running work rather than changing its inputs
-- under a suspended coroutine or returning rows from the old store.
filter.search = "Item"
assert(query:step(store, "Fixture", "Test", filter) == nil)
filter.search = "Item 00002"
result = finish(query, store, filter)
assert(#result.rows == 1 and result.rows[1].key == "10002:0")
filter = { view = "Journal" }
assert(query:step(store, "Fixture", "Test", filter) == nil)
filter = { view = "Gallery", search = "New item" }
result = finish(query, store, filter)
assert(#result.rows == 1 and result.rows[1].key == "999:0")
local replacement = storeWith(1)
result = finish(query, replacement, {})
assert(result.discoveryCount == 1 and #result.rows == 1)
result = finish(query, replacement, { view = "Journal" })
assert(#result.rows == 3)
for index, row in ipairs(result.rows) do
    assert(result.bySequence[row.sequence] == row and result.positions[row.sequence] == index)
    assert(row.metadata and row.recorded == row.quantity)
end
local exact = finish(query, replacement, { view = "Journal", historyKey = "10001:0" })
assert(#exact.rows == 3)
local absentHistory = finish(query, replacement, { view = "Journal", historyKey = "10001:99" })
assert(#absentHistory.rows == 0, "Changing the intrinsic variant must invalidate cached Journal rows")
assert(#finish(query, replacement, { view = "Journal" }).rows == 3)
query:metadataChanged()
priorReads = reads
assert(#finish(query, replacement, {}).rows == 1)
assert(reads > priorReads, "Metadata changes must invalidate cached results")

local metadataQuery = addon.BookQuery.new(queryApi)
assert(metadataQuery:step(store, "Fixture", "Test", {}) == nil)
metadataCategory = "Weapons"
metadataQuery:metadataChanged()
result = finish(metadataQuery, store, {})
for _, row in ipairs(result.rows) do
    assert(row.category == "Weapons", "The first published result must use current item data")
end
metadataCategory = "Materials"
metadataQuery:metadataChanged()
result = finish(metadataQuery, store, {})
assert(result.categories.Materials == 181 and result.categories.Weapons == nil)
-- New browsing inputs are captured and invalidate suspended and completed jobs.
filter = { quality = "unknown", sort = "quantity" }
assert(query:step(store, "Fixture", "Test", filter) == nil)
filter.quality = 2
result = finish(query, store, filter)
assert(#result.rows == 0, "A quality change must replace work using the old filter")
filter.quality = "unknown"
assert(#finish(query, store, filter).rows == 181)
filter.method = "Crafted"
assert(#finish(query, store, filter).rows == 0)
filter = { ownership = "present", search = "New item", sort = "gained" }
assert(#finish(query, store, filter).rows == 1)
filter.ownership = "historical"
assert(#finish(query, store, filter).rows == 0)
filter = { view = "Journal", action = "Sale" }
assert(#finish(query, replacement, filter).rows == 1)
filter.action = nil
filter.realm = "Absent"
assert(#finish(query, replacement, filter).rows == 0)
filter.realm = nil
filter.dateFrom = 999999
assert(#finish(query, replacement, filter).rows == 0)
filter.dateFrom = nil
assert(#finish(query, replacement, filter).rows == 3)
filter.dateTo = 0
assert(#finish(query, replacement, filter).rows == 0)

print("architecture_spec: query invalidation during work and cached results passed")

-- All readers agree on storage truth, including offline and partial checks;
-- historical filtering uses classification rather than display wording.
local link = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local key = "4540:0"
local ownershipSaved
local ownershipStore = addon.Schema.open(nil, function(value)
    ownershipSaved = value
end)
local function scan(character, area, at, complete, quantity)
    assert(ownershipStore:scan({
        character = character,
        realm = "Realm",
        area = area,
        seenAt = at,
        complete = complete,
        items = quantity > 0 and { { itemID = 4540, link = link, quantity = quantity } } or {},
    }))
end
local function agree(expected)
    local detail = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm")
    local rows = addon.Collection.query(ownershipStore, "Ada", "Realm", {}, addon.Client.itemMetadata).rows
    assert(detail.ownershipState == expected and rows[1].ownershipState == expected)
    assert(detail.ownership == rows[1].ownership)
    local text = table.concat(addon.Collection.lines(ownershipStore, "Ada", "Realm"), "\n")
    assert(text:find("Status: " .. detail.ownership, 1, true))
    assert(addon.Presentation.line(ownershipStore, link, "Ada", "Realm"):find("status " .. detail.ownership, 1, true))
    local historical =
        addon.Collection.query(ownershipStore, "Ada", "Realm", { ownership = "historical" }, addon.Client.itemMetadata)
    assert(#historical.rows == (expected == "historical" and 1 or 0))
end
scan("Ada", "bags", 1000, true, 1)
agree("present")
for _, area in ipairs({ "bags", "bank", "equipped" }) do
    scan("Ada", area, 1001, true, 0)
end
agree("historical")
scan("Ada", "bank", 1002, false, 0)
agree("unknown")
scan("Ada", "bags", 1002, false, 1)
agree("present")
scan("Ada", "bags", 1003, true, 0)
scan("Ben", "bags", 1003, true, 1)
agree("unknown")
local offline = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ben" })
assert(offline.checkedUnits == 1 and offline.ownershipState == "unknown")
local empty = addon.LastSeen.project(ownershipStore, ownershipStore:find(key), "Ada", "Realm", { realm = "Absent" })
assert(empty.state == "unknown" and empty.checkedUnits == nil)
print("architecture_spec: list, details, text, tooltip, and historical filter agree")

-- A failed check must retain the last readable bank fact with its own date.
scan("Ada", "bags", 4000, true, 0)
scan("Ada", "equipped", 4000, true, 0)
scan("Ada", "bank", 4000, true, 5)
scan("Ada", "bank", 4001, false, 0)
local closed = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ada" })
assert(closed.ownershipState == "unknown")
local bank = closed.checks[2]
assert(bank.quantity == nil and bank.at == 4001)
assert(bank.observedQuantity == 5 and bank.observedAt == 4000, "Closing the bank hid its dated five-unit observation")
local datedBank = "Ada-Realm • Bank: last found 5 on " .. date("%Y-%m-%d %H:%M", 4000)
for _, text in ipairs({
    table.concat(addon.Collection.lines(ownershipStore, "Ada", "Realm", "Ada"), "\n"),
    table.concat(addon.Collection.details(ownershipStore, key, "Ada", "Realm", { character = "Ada" }), "\n"),
    addon.Presentation.line(ownershipStore, link, "Ada", "Realm"),
}) do
    assert(text:find(datedBank, 1, true), "A reader hid the dated bank observation: " .. text)
    assert(text:find("status Unknown", 1, true))
end
print("architecture_spec: dated bank observation survives closure")

scan("Ada", "bank", 4010, true, 2)
local reopened = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ada" })
assert(reopened.ownershipState == "present" and reopened.checks[2].observedQuantity == 2)
assert(reopened.checks[2].observedAt == 4010)
scan("Ada", "bank", 4020, true, 0)
scan("Ada", "bank", 4021, true, 0)
scan("Ada", "bank", 4022, false, 0)
local absent = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ada" })
assert(absent.ownershipState == "unknown" and absent.checks[2].quantity == nil)
assert(
    absent.checks[2].observedQuantity == 0 and absent.checks[2].observedAt == 4021,
    "The latest complete zero check must survive an unreadable attempt"
)
local restoredOwnership = addon.Schema.open(ownershipSaved, function() end)
local restoredAbsent = addon.Collection.inspect(restoredOwnership, key, "Ada", "Realm", { character = "Ada" })
assert(restoredAbsent.checks[2].observedQuantity == 0 and restoredAbsent.checks[2].observedAt == 4021)
assert(restoredAbsent.checkedUnits == nil, "A saved stale zero must not become current stock")
scan("Ada", "bank", 4023, false, 3)
local partial = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ada" })
assert(partial.ownershipState == "present" and partial.checks[2].observedQuantity == 3)
assert(partial.checks[2].observedAt == 4023)
scan("Ada", "bank", 4024, false, 0)
partial = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ada" })
assert(partial.ownershipState == "unknown" and partial.checkedUnits == nil)
assert(partial.checks[2].observedQuantity == 3 and partial.checks[2].observedAt == 4023)
local offlineBank = addon.Collection.inspect(ownershipStore, key, "Ben", "Realm", { character = "Ada" })
assert(offlineBank.ownershipState == "unknown" and not offlineBank.checks[2].online)
assert(offlineBank.checks[2].observedQuantity == 3 and offlineBank.checks[2].observedAt == 4023)
local scopedRows = addon.Collection.query(ownershipStore, "Ada", "Realm", { character = "Ada" }).rows
assert(scopedRows[1].ownershipState == partial.ownershipState and scopedRows[1].checkedUnits == nil)
for _, area in ipairs({ "bags", "bank", "equipped" }) do
    scan("Ada", area, 4030, true, 0)
end
local completeAbsence = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ada" })
assert(completeAbsence.ownershipState == "historical" and completeAbsence.checkedUnits == 0)
for _, check in ipairs(completeAbsence.checks) do
    assert(check.observedQuantity == 0 and check.observedAt == 4030)
end
-- Bank stock never seen on Ben still has a readable zero, preserved on closure.
scan("Ben", "bank", 4040, true, 0)
scan("Ben", "bank", 4041, false, 0)
local neverHeld = addon.Collection.inspect(ownershipStore, key, "Ada", "Realm", { character = "Ben" })
assert(neverHeld.checks[2].observedQuantity == 0 and neverHeld.checks[2].observedAt == 4040)
assert(neverHeld.checks[2].quantity == nil and neverHeld.ownershipState == "unknown")
scan("Cara", "bank", 4050, true, 0)
scan("Cara", "bank", 4051, false, 0)
local neverSeenText =
    table.concat(addon.Collection.details(ownershipStore, key, "Ada", "Realm", { character = "Cara" }), "\n")
assert(
    neverSeenText:find("Cara-Realm • Bank: last found 0 on " .. date("%Y-%m-%d %H:%M", 4050), 1, true),
    "Text details hid an observed zero on a character who never held the item"
)
print("architecture_spec: changed stock, partial/offline checks, persisted zero, and complete absence passed")

-- Drive the scan adapter without addon bootstrap. Use a clock that advances on
-- every read to prove that comparable areas still share the coordinator's date.
local timers, snapshots, bagReads, gearReads = {}, {}, {}, {}
local scanClock, readable = 2000, true
local api = {
    UnitName = function()
        return "Ada"
    end,
    GetRealmName = function()
        return "Realm"
    end,
    GetServerTime = function()
        scanClock = scanClock + 1
        return scanClock
    end,
    C_Timer = {
        After = function(_, callback)
            timers[#timers + 1] = callback
        end,
    },
    GetInventoryItemLink = function(_, slot)
        gearReads[slot] = (gearReads[slot] or 0) + 1
        return slot == 16 and link or nil
    end,
    C_Container = {
        GetContainerNumSlots = function(bag)
            bagReads[bag] = (bagReads[bag] or 0) + 1
            return bag == 0 and 1 or 0
        end,
        GetContainerItemInfo = function()
            return { itemID = 4540, hyperlink = readable and link or nil, stackCount = 1 }
        end,
    },
}
local flushSizes = {}
local inventory = addon.Inventory.new(api, function(snapshot)
    snapshots[#snapshots + 1] = snapshot
end, function()
    flushSizes[#flushSizes + 1] = #snapshots
end)
inventory:check("all")
assert(#flushSizes == 0, "Immediate baselines must not complete a queued update")
assert(snapshots[1].seenAt == snapshots[2].seenAt and snapshots[2].seenAt == snapshots[3].seenAt)
assert(not snapshots[3].complete, "A closed bank must remain incomplete")
snapshots, bagReads, gearReads = {}, {}, {}
inventory:event("BAG_UPDATE", 0)
inventory:event("BAG_UPDATE_DELAYED")
inventory:event("PLAYER_EQUIPMENT_CHANGED", 16)
assert(#timers == 1 and #snapshots == 0 and #flushSizes == 0)
timers[1]()
assert(#flushSizes == 1 and flushSizes[1] == 2, "Completion must follow both possession scans")
assert(#snapshots == 2 and snapshots[1].seenAt == snapshots[2].seenAt)
assert(bagReads[0] == 1 and bagReads[1] == nil and gearReads[16] == 1 and gearReads[15] == nil)

inventory:event("BANKFRAME_OPENED")
assert(snapshots[#snapshots].area == "bank" and snapshots[#snapshots].complete)
inventory:event("BAG_UPDATE", 5)
inventory:event("BAG_UPDATE_DELAYED")
inventory:event("BANKFRAME_CLOSED")
local beforeFlush = #snapshots
timers[2]()
assert(#flushSizes == 2 and flushSizes[2] == #snapshots)
assert(#snapshots == beforeFlush + 2, "Queued work must not read a bank that has closed")
assert(snapshots[beforeFlush].area == "bank" and not snapshots[beforeFlush].complete)

readable = false
inventory:check("possessions")
assert(not snapshots[#snapshots - 1].complete)
readable = true
bagReads = {}
inventory:event("GET_ITEM_INFO_RECEIVED", true)
assert(snapshots[#snapshots].area == "bags" and snapshots[#snapshots].complete)
assert(bagReads[0] == 1 and bagReads[1] == nil)

inventory:event("BAG_UPDATE", 0)
inventory:event("BAG_UPDATE_DELAYED")
inventory:check("possessions")
local immediateBags, immediateGear = snapshots[#snapshots - 1], snapshots[#snapshots]
assert(immediateBags.seenAt == immediateGear.seenAt)
timers[3]()
assert(snapshots[#snapshots - 1].seenAt == snapshots[#snapshots].seenAt)
assert(snapshots[#snapshots].seenAt > immediateGear.seenAt)
api.C_Timer = nil
inventory:event("PLAYER_EQUIPMENT_CHANGED", 16)
assert(snapshots[#snapshots - 1].seenAt == snapshots[#snapshots].seenAt)
assert(#flushSizes == 4 and flushSizes[4] == #snapshots, "Synchronous flushes must also signal completion")
print("architecture_spec: mixed bursts, bank access, retries, and immediate baselines passed")
