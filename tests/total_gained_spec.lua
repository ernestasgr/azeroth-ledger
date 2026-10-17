-- Pins Total gained, gain dates and first-check units for every channel that
-- credits a gain, through the store's public interface and a save round trip.
local addon = {}
for _, name in ipairs({
    "Item",
    "Work",
    "SchemaValidate",
    "StoreKernel",
    "StorePreferences",
    "StoreJournal",
    "StoreEvidence",
    "StoreRecords",
    "StoreLoot",
    "StoreExchange",
    "StoreVendor",
    "StoreReward",
    "StoreScan",
    "Schema",
    "Reward",
    "Loot",
}) do
    assert(loadfile("AzerothLedger/" .. name .. ".lua"))("AzerothLedger", addon)
end

local link = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local key = addon.Item.key(link, 4540)
local otherLink = "|Hitem:2589::::::::|h[Linen Cloth]|h"
local otherKey = addon.Item.key(otherLink, 2589)

local function world()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local w = {}
    function w.actor(character, at)
        return { character = character or "Ada", realm = "Realm", level = 12, place = "Elwynn Forest", at = at }
    end
    function w.bags(at, quantity, character, extra)
        local items = quantity > 0 and { { itemID = 4540, link = link, quantity = quantity } } or {}
        if extra and extra > 0 then
            items[#items + 1] = { itemID = 2589, link = otherLink, quantity = extra }
        end
        assert(store:scan({
            character = character or "Ada",
            realm = "Realm",
            area = "bags",
            seenAt = at,
            complete = true,
            items = items,
        }))
    end
    function w.lootOpen(at, quantity)
        assert(store:lootOpen({
            character = "Ada",
            realm = "Realm",
            at = at,
            level = 12,
            place = "Elwynn Forest",
            slots = { { key = key, quantity = quantity } },
        }))
    end
    function w.lootReceipt(at, quantity)
        assert(store:lootReceipt({ key = key, quantity = quantity }, at, w.actor("Ada")))
    end
    -- A second same-item slot that only becomes readable after the loot closes.
    function w.lateLoot(at)
        local readable = false
        local api = {
            GetNumLootItems = function()
                return 2
            end,
            GetLootSlotInfo = function()
                return nil, "Loot item", 1
            end,
            GetLootSourceInfo = function()
                return "Creature-0-6783-1-118-1984-000040D7BC", 1
            end,
            GetLootSlotLink = function(slot)
                return (slot == 1 or readable) and link or nil
            end,
        }
        assert(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "equipped",
            complete = true,
            seenAt = at,
            items = {},
        }))
        local context = { character = "Ada", realm = "Realm", at = at, level = 1, place = "Teldrassil" }
        context.slots = assert(addon.Loot.open(api))
        assert(store:lootOpen(context))
        w.lootReceipt(at + 1, 2)
        w.bags(at + 2, 2)
        assert(store:lootClose(at + 2))
        readable = true
        assert(store:lootSourceProof(assert(addon.Loot.open(api)), at + 3, w.actor("Ada")))
    end
    function w.reward(at, method, quantity)
        local receipt = method == "Quest" and assert(addon.Reward.quest({}, 92463, link, quantity))
            or assert(addon.Reward.craft({}, { itemID = 4540, hyperlink = link, quantity = quantity }))
        assert(store:rewardReceipt(receipt, at, w.actor("Ada")))
        if method == "Quest" then
            assert(store:questTurnedIn(92463, at, { character = "Ada", realm = "Realm" }))
        end
    end
    function w.vendor(at, kind, quantity)
        assert(
            store:vendorAction(
                { kind = kind, key = key, itemID = 4540, link = link, quantity = quantity },
                at,
                { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest", vendorName = "Dermot" }
            )
        )
    end
    function w.vendorReceipt(at, quantity)
        assert(store:vendorReceipt({ key = key, quantity = quantity }, at, { character = "Ada", realm = "Realm" }))
    end
    function w.mail(at, character, direction, quantity, peer)
        assert(store:exchangeIntent({
            channel = "mail",
            direction = direction,
            key = key,
            itemID = 4540,
            link = link,
            quantity = quantity,
            peerName = peer,
            peerRealm = peer and "Realm" or nil,
        }, at, w.actor(character, at)))
        assert(store:exchangeConfirm("mail", direction, at + 1, w.actor(character, at + 1)))
    end
    function w.store()
        return store
    end
    function w.reopen()
        return addon.Schema.open(saved, function(value)
            saved = value
        end)
    end
    function w.saved()
        return saved
    end
    return w
end

-- One line per record: the facts every crediting path must keep consistent.
local function facts(record)
    if not record then
        return "missing"
    end
    local characters = {}
    for _, seen in ipairs(record.characters) do
        characters[#characters + 1] = seen.name .. "=" .. seen.firstSeenUnits
    end
    table.sort(characters)
    local gains = {}
    for _, gain in ipairs(record.gains) do
        gains[#gains + 1] = gain.method .. "+" .. gain.quantity .. (gain.refunded and ("-" .. gain.refunded) or "")
    end
    return string.format(
        "gained=%d first=%s last=%s firstSeenUnits=%d chars=[%s] gains=[%s] discovery=%s",
        record.totalGained,
        tostring(record.firstGained),
        tostring(record.lastGained),
        record.firstSeenUnits,
        table.concat(characters, ","),
        table.concat(gains, ","),
        tostring(record.evidencedDiscovery == true)
    )
end

local cases = {
    {
        name = "already present at the first check",
        run = function(w)
            w.bags(100, 4)
        end,
        expect = "gained=0 first=nil last=nil firstSeenUnits=4 chars=[Ada=4] gains=[] discovery=false",
    },
    {
        name = "loot of a newly seen item, bags checked before the receipt",
        run = function(w)
            w.bags(100, 0)
            w.lootOpen(110, 2)
            w.bags(111, 2)
            w.lootReceipt(112, 2)
        end,
        expect = "gained=2 first=112 last=112 firstSeenUnits=0 chars=[Ada=0] gains=[Looted+2] discovery=true",
    },
    {
        name = "loot of a newly seen item, receipt before the bags check",
        run = function(w)
            w.bags(100, 0)
            w.lootOpen(110, 2)
            w.lootReceipt(111, 2)
            w.bags(112, 2)
        end,
        expect = "gained=2 first=111 last=111 firstSeenUnits=0 chars=[Ada=0] gains=[Looted+2] discovery=true",
    },
    {
        name = "loot of an item already held",
        run = function(w)
            w.bags(100, 5)
            w.lootOpen(110, 1)
            w.lootReceipt(111, 1)
            w.bags(112, 6)
        end,
        expect = "gained=1 first=111 last=111 firstSeenUnits=5 chars=[Ada=5] gains=[Looted+1] discovery=false",
    },
    {
        name = "loot settled by a late source proof",
        run = function(w)
            w.bags(100, 0)
            w.lateLoot(100)
        end,
        expect = "gained=2 first=101 last=101 firstSeenUnits=0 chars=[Ada=0] gains=[Looted+2] discovery=true",
    },
    {
        name = "quest reward of a newly seen item",
        run = function(w)
            w.bags(100, 0)
            w.reward(110, "Quest", 1)
            w.bags(111, 1)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Quest+1] discovery=true",
    },
    {
        name = "quest reward of an item already held",
        run = function(w)
            w.bags(100, 2)
            w.reward(110, "Quest", 1)
            w.bags(111, 3)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=2 chars=[Ada=2] gains=[Quest+1] discovery=false",
    },
    {
        name = "crafted item",
        run = function(w)
            w.bags(100, 0)
            w.reward(110, "Crafted", 1)
            w.bags(111, 1)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Crafted+1] discovery=true",
    },
    {
        name = "vendor purchase of a newly seen item",
        run = function(w)
            w.bags(100, 0)
            w.vendor(110, "purchase", 1)
            w.bags(111, 1)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Vendor+1] discovery=true",
    },
    {
        name = "vendor purchase of an item already held, with a receipt",
        run = function(w)
            w.bags(100, 2)
            w.vendor(110, "purchase", 3)
            w.vendorReceipt(111, 3)
            w.bags(112, 5)
        end,
        expect = "gained=3 first=110 last=110 firstSeenUnits=2 chars=[Ada=2] gains=[Vendor+3] discovery=false",
    },
    {
        name = "vendor purchase then refund",
        run = function(w)
            w.bags(100, 0)
            w.vendor(110, "purchase", 3)
            w.vendorReceipt(111, 3)
            w.bags(112, 3)
            w.vendor(113, "refund", 3)
            w.bags(114, 0)
        end,
        expect = "gained=0 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Vendor+3-3] discovery=true",
    },
    {
        name = "vendor sale and buyback",
        run = function(w)
            w.bags(100, 0)
            w.vendor(110, "purchase", 1)
            w.bags(111, 1)
            w.vendor(112, "sale", 1)
            w.bags(113, 0)
            w.vendor(114, "buyback", 1)
            w.bags(115, 1)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Vendor+1] discovery=true",
    },
    {
        name = "mail from another player, item already held",
        run = function(w)
            w.bags(100, 5, "Ben")
            w.mail(110, "Ben", "in", 2, "Cara")
            w.bags(112, 7, "Ben")
        end,
        expect = "gained=2 first=110 last=110 firstSeenUnits=5 chars=[Ben=5] gains=[Obtained+2] discovery=false",
    },
    {
        name = "mail from another player, newly seen item",
        run = function(w)
            w.bags(100, 0, "Ben")
            w.mail(110, "Ben", "in", 2, "Cara")
            w.bags(112, 2, "Ben")
        end,
        expect = "gained=2 first=110 last=110 firstSeenUnits=0 chars=[Ben=0] gains=[Obtained+2] discovery=true",
    },
    {
        name = "Transfer between own characters",
        run = function(w)
            w.bags(100, 3, "Ada")
            w.bags(100, 0, "Ben")
            w.mail(101, "Ada", "out", 3, "Ben")
            w.bags(103, 0, "Ada")
            w.mail(104, "Ben", "in", 3, "Ada")
            w.bags(106, 3, "Ben")
        end,
        expect = "gained=0 first=nil last=nil firstSeenUnits=3 chars=[Ada=3,Ben=0] gains=[] discovery=false",
    },
    {
        name = "loot then vendor on one item keeps first and last dates",
        run = function(w)
            w.bags(100, 0)
            w.lootOpen(110, 1)
            w.lootReceipt(111, 1)
            w.bags(112, 1)
            w.vendor(120, "purchase", 2)
            w.bags(121, 3)
        end,
        expect = "gained=3 first=111 last=120 firstSeenUnits=0 chars=[Ada=0] gains=[Looted+1,Vendor+2] discovery=true",
    },
    {
        name = "gain on a second character after the first check",
        run = function(w)
            w.bags(100, 2, "Ada")
            w.bags(101, 0, "Ben")
            w.mail(110, "Ben", "in", 1, "Cara")
            w.bags(112, 1, "Ben")
        end,
        -- Current behaviour: Ben's first-check units still count the mailed unit.
        expect = "gained=1 first=110 last=110 firstSeenUnits=2 chars=[Ada=2,Ben=1] gains=[Obtained+1] discovery=false",
    },
    {
        name = "two items settled by one check",
        run = function(w)
            w.bags(100, 0, "Ada", 0)
            w.vendor(110, "purchase", 1)
            w.bags(111, 1, "Ada", 4)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Vendor+1] discovery=true",
    },
}

local failures = {}
for _, case in ipairs(cases) do
    local w = world()
    case.run(w)
    local live = facts(w.store():find(key))
    local reopened = w.reopen()
    local restored = facts(reopened:find(key))
    if live ~= case.expect then
        failures[#failures + 1] = case.name .. "\n  expected " .. case.expect .. "\n  actual   " .. live
    elseif restored ~= live then
        failures[#failures + 1] = case.name .. " after reopening\n  expected " .. live .. "\n  actual   " .. restored
    elseif reopened:diagnostic().kind ~= "healthy" then
        failures[#failures + 1] = case.name .. ": reopened save is " .. reopened:diagnostic().kind
    end
    local persisted = w.saved().records[key]
    if persisted and persisted.totalGained ~= w.store():find(key).totalGained then
        failures[#failures + 1] = case.name .. ": saved Total gained differs from the live record"
    end
end
-- The second item in the shared check stays a first-check item.
do
    local w = world()
    cases[#cases].run(w)
    assert(
        facts(w.store():find(otherKey))
            == "gained=0 first=nil last=nil firstSeenUnits=4 chars=[Ada=4] gains=[] discovery=false"
    )
end
assert(#failures == 0, "\n" .. table.concat(failures, "\n"))

print("total_gained_spec: passed")
