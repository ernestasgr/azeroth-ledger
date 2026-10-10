local addon = {}
for _, name in ipairs({ "Item", "Work", "Schema", "Client", "LastSeen", "Collection", "Journal", "BookQuery" }) do
    assert(loadfile("AzerothLedger/" .. name .. ".lua"))("AzerothLedger", addon)
end
---@type AzerothLedgerData?
local saved
local writes = 0
local store = addon.Schema.open(nil, function(value)
    saved, writes = value, writes + 1
end)
local actor = { character = "Ada", realm = "Realm", level = 12, place = "Forest" }
local link = "|Hitem:2672::::::::|h[Meat]|h"
assert(store:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    complete = true,
    seenAt = 1000,
    items = { { itemID = 2672, link = link, quantity = 5 } },
}))
assert(store:lootOpen({
    character = "Ada",
    realm = "Realm",
    level = 12,
    place = "Forest",
    at = 1010,
    slots = { { key = "2672:0", quantity = 1 } },
}))
local before = writes
local result = addon.Collection.evidenceQuery(store, {})
assert(#result.rows == 1 and result.rows[1].name == "Meat")
assert(result.rows[1].status == "Still checking" and result.rows[1].action == "Loot pickup")
assert(writes == before and store:find("2672:0").totalGained == 0)
assert(store:expireEvidence(1070))
result = addon.Collection.evidenceQuery(store, {})
assert(#result.rows == 1 and result.rows[1].status == "Timed out")
assert(result.rows[1].nextStep:find("can no longer be confirmed", 1, true))
assert(#addon.Collection.evidenceQuery(store, { search = "mEaT", character = "Ada", realm = "Realm" }).rows == 1)
assert(#addon.Collection.evidenceQuery(store, { character = "Ben" }).rows == 0)
assert(#addon.Collection.evidenceQuery(store, { search = "Sword" }).rows == 0)
assert(saved and saved.schema == 2)
print("evidence_query_spec: lifecycle, filtering and read-only totals passed")

assert(store:vendorAction({ kind = "purchase", key = "2672:0", itemID = 2672, link = link, quantity = 1 }, 1080, actor))
assert(store:exchangeIntent({
    channel = "mail",
    direction = "in",
    key = "2672:0",
    itemID = 2672,
    link = link,
    quantity = 1,
    mailKind = "unresolved",
}, 1081, actor))
result = addon.Collection.evidenceQuery(store, {})
assert(#result.rows == 3)
assert(result.rows[1].action == "Mail received" and result.rows[1].status == "Still checking")
assert(result.rows[2].action == "Vendor purchase")
assert(store:vendorAction({ kind = "purchase", key = "2672:0", itemID = 2672, link = link, quantity = 1 }, 1082, actor))
result = addon.Collection.evidenceQuery(store, {})
assert(#result.rows == 4)
assert(result.rows[3].status == "Could not match")
assert(result.rows[3].nextStep:find("will not retry", 1, true))
before = writes
local reopened = addon.Schema.open(saved, function() end)
result = addon.Collection.evidenceQuery(reopened, {})
assert(#result.rows == 4 and result.rows[1].status == "Login interrupted")
assert(writes == before)
assert(reopened:find("2672:0").totalGained == 0)

assert(store:scan({
    character = "Ben",
    realm = "Elsewhere",
    area = "bank",
    complete = false,
    seenAt = 1082,
    items = { { itemID = 999, link = "|Hitem:999|h[Broken]|h", quantity = 2, location = "bank:1" } },
}))
result = addon.Collection.evidenceQuery(store, { character = "Ben", realm = "Elsewhere" })
assert(#result.rows == 1 and result.rows[1].link == nil)
assert(result.rows[1].name == "Item 999 • unresolved variant")
assert(result.rows[1].status == "Item name unavailable" and result.rows[1].nextStep:find("bank", 1, true))
assert(store:scan({
    character = "Ben",
    realm = "Elsewhere",
    area = "bank",
    complete = false,
    seenAt = 1083,
    items = { { itemID = 999, quantity = 2, location = "bank:2" } },
}))
result = addon.Collection.evidenceQuery(store, { character = "Ben" })
assert(#result.rows == 2)

-- A persisted queue at its retention limit; details outside the limit cannot be filtered.
local large = {
    schema = saved.schema,
    records = saved.records,
    areas = saved.areas,
    evidence = { nextID = 2001, unresolved = {}, discarded = 19, firstDiscarded = 100, lastDiscarded = 200 },
}
for index = 1, 2000 do
    large.evidence.unresolved[index] = {
        id = index,
        kind = "vendorReceipt",
        reason = "overflow",
        at = 200 + index,
        character = "Ada",
        realm = "Realm",
        detail = { itemID = 2672, key = "2672:0", link = link, quantity = 1 },
    }
end
local largeWrites = 0
local largeStore = addon.Schema.open(large, function()
    largeWrites = largeWrites + 1
end)
assert(largeStore:diagnostic().kind == "healthy")
local query, steps = addon.BookQuery.new({}), 0
local filter = { view = "Evidence", search = "Meat" }
repeat
    result = query:step(largeStore, "Ada", "Realm", filter)
    steps = steps + 1
    assert(steps < 2000)
until result
assert(steps > 1 and #result.rows == 2000 and result.discarded == 19)
assert(result.firstDiscarded == 100 and result.lastDiscarded == 200)
assert(largeWrites == 0 and largeStore:find("2672:0").totalGained == 0)
assert(result.rows[1].status == "Too many changes")
assert(#addon.Collection.evidenceQuery(largeStore, { search = "discarded item" }).rows == 0)
print("evidence_query_spec: vendor, exchange, identity, overflow and cooperative paging passed")

-- Retained evidence payloads are deliberately permissive. A damaged field
-- must still produce an inspectable unknown row rather than break the book.
local damaged = {
    schema = 2,
    records = {},
    areas = {},
    evidence = {
        nextID = 4,
        discarded = 0,
        unresolved = {
            {
                id = 1,
                kind = "loot",
                reason = "expired",
                at = 1000,
                character = "Ada",
                realm = "Realm",
                detail = { slot = 1, link = {}, key = {}, itemID = {}, quantity = {}, location = {} },
            },
            {
                id = 2,
                kind = "lootOpen",
                reason = "overflow",
                at = 1001,
                character = "Ada",
                realm = "Realm",
                detail = { slots = { false } },
            },
            {
                id = 3,
                kind = "exchange",
                reason = "unknown",
                at = 1002,
                character = "Ada",
                realm = "Realm",
                detail = {},
            },
        },
    },
}
local damagedStore = addon.Schema.open(damaged, function()
    error("Read-only inspection wrote data")
end)
result = addon.Collection.evidenceQuery(damagedStore, {})
assert(#result.rows == 3 and result.rows[1].name == "Unresolved item identity")
assert(result.rows[1].link == nil and result.rows[2].quantity == nil)
assert(result.rows[1].action == "Mail or trade" and result.rows[1].status == "Needs review")
assert(not result.rows[1].nextStep:find("eligible", 1, true))

local exchange = addon.Schema.open(nil, function() end)
assert(exchange:scan({ character = "Ada", realm = "Realm", area = "bags", complete = true, seenAt = 1000, items = {} }))
assert(
    exchange:exchangeIntent(
        { channel = "trade", direction = "in", key = "2672:0", itemID = 2672, link = link, quantity = 1 },
        1010,
        actor
    )
)
assert(exchange:exchangeMarkUnresolved(1, actor))
result = addon.Collection.evidenceQuery(exchange, {})
assert(#result.rows == 1 and result.rows[1].status == "Could not match")
assert(not result.rows[1].nextStep:find("eligible", 1, true))

-- Exact saved preparation IDs tie the unknown quest item to its reward row.
local quest = {
    schema = 2,
    records = saved.records,
    areas = saved.areas,
    evidence = {
        nextID = 3,
        discarded = 0,
        unresolved = {
            {
                id = 1,
                kind = "quest",
                reason = "expired",
                at = 1000,
                character = "Ada",
                realm = "Realm",
                detail = { id = 7, questID = 99 },
            },
            {
                id = 2,
                kind = "rewards",
                reason = "expired",
                at = 1001,
                character = "Ada",
                realm = "Realm",
                detail = { key = "2672:0", method = "Quest", quantity = 1, questPreparationID = 7 },
            },
        },
    },
}
local questStore = addon.Schema.open(quest, function()
    error("Query restarted expired evidence")
end)
result = addon.Collection.evidenceQuery(questStore, {})
assert(#result.rows == 1 and result.rows[1].action == "Quest reward")
assert(result.rows[1].status == "Timed out")
print("evidence_query_spec: damaged payloads, stopped exchanges and linked quest presentation passed")
