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
    "LastSeen",
}) do
    assert(loadfile("AzerothLedger/" .. name .. ".lua"))("AzerothLedger", addon)
end
date = os.date

local link = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local key = addon.Item.key(link, 4540)
local otherLink = "|Hitem:2589::::::::|h[Linen Cloth]|h"
local otherKey = addon.Item.key(otherLink, 2589)

local function world()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    -- Each character's realm; a case may move Ben to another realm.
    local w = { realms = { Ada = "Realm", Ben = "Realm" } }
    function w.realm(character)
        return w.realms[character or "Ada"] or "Realm"
    end
    function w.actor(character, at)
        return {
            character = character or "Ada",
            realm = w.realm(character),
            level = 12,
            place = "Elwynn Forest",
            at = at,
        }
    end
    function w.bags(at, quantity, character, extra)
        local items = quantity > 0 and { { itemID = 4540, link = link, quantity = quantity } } or {}
        if extra and extra > 0 then
            items[#items + 1] = { itemID = 2589, link = otherLink, quantity = extra }
        end
        assert(store:scan({
            character = character or "Ada",
            realm = w.realm(character),
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

-- Units a breakdown explains for one view: a character, a realm, or the account.
local function explained(store, itemKey, scope)
    local total = 0
    for _, quantity in pairs(store:breakdown(itemKey, scope).methods) do
        total = total + quantity
    end
    return total
end

-- Two lines per record: the facts every crediting path must keep consistent,
-- then what each view shows. Characters read "overall/breakdown", each realm
-- reads its breakdown, and "all" reads the account overall and breakdown.
local function facts(record, store)
    if not record then
        return "missing"
    end
    local characters, found, realms, all = {}, {}, {}, nil
    for _, seen in ipairs(record.characters) do
        characters[#characters + 1] = seen.name .. "=" .. seen.firstSeenUnits
        local projection = addon.LastSeen.project(store, record, seen.name, seen.realm)
        found[#found + 1] = seen.name
            .. "="
            .. tostring(projection.characterOverall)
            .. "/"
            .. explained(store, record.key, { character = seen.name, realm = seen.realm })
        realms[seen.realm] = true
        all = projection.allCharactersOverall
    end
    local realmViews = {}
    for realm in pairs(realms) do
        realmViews[#realmViews + 1] = realm .. "=" .. explained(store, record.key, { realm = realm })
    end
    table.sort(characters)
    table.sort(found)
    table.sort(realmViews)
    all = tostring(all) .. "/" .. explained(store, record.key)
    local gains = {}
    for _, gain in ipairs(record.gains) do
        gains[#gains + 1] = gain.method .. "+" .. gain.quantity .. (gain.refunded and ("-" .. gain.refunded) or "")
    end
    return string.format(
        "gained=%d first=%s last=%s firstSeenUnits=%d chars=[%s] gains=[%s] discovery=%s"
            .. "\nfound=[%s] realms=[%s] all=%s",
        record.totalGained,
        tostring(record.firstGained),
        tostring(record.lastGained),
        record.firstSeenUnits,
        table.concat(characters, ","),
        table.concat(gains, ","),
        tostring(record.evidencedDiscovery == true),
        table.concat(found, ","),
        table.concat(realmViews, ","),
        all
    )
end

local cases = {
    {
        name = "already present at the first check",
        run = function(w)
            w.bags(100, 4)
        end,
        expect = "gained=0 first=nil last=nil firstSeenUnits=4 chars=[Ada=4] gains=[] discovery=false",
        found = "found=[Ada=4/4] realms=[Realm=4] all=4/4",
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
        found = "found=[Ada=nil/2] realms=[Realm=2] all=nil/2",
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
        found = "found=[Ada=nil/2] realms=[Realm=2] all=nil/2",
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
        found = "found=[Ada=6/6] realms=[Realm=6] all=6/6",
    },
    {
        name = "loot settled by a late source proof",
        run = function(w)
            w.bags(100, 0)
            w.lateLoot(100)
        end,
        expect = "gained=2 first=101 last=101 firstSeenUnits=0 chars=[Ada=0] gains=[Looted+2] discovery=true",
        found = "found=[Ada=2/2] realms=[Realm=2] all=2/2",
    },
    {
        name = "quest reward of a newly seen item",
        run = function(w)
            w.bags(100, 0)
            w.reward(110, "Quest", 1)
            w.bags(111, 1)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Quest+1] discovery=true",
        found = "found=[Ada=1/1] realms=[Realm=1] all=1/1",
    },
    {
        name = "quest reward of an item already held",
        run = function(w)
            w.bags(100, 2)
            w.reward(110, "Quest", 1)
            w.bags(111, 3)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=2 chars=[Ada=2] gains=[Quest+1] discovery=false",
        found = "found=[Ada=3/3] realms=[Realm=3] all=3/3",
    },
    {
        name = "crafted item",
        run = function(w)
            w.bags(100, 0)
            w.reward(110, "Crafted", 1)
            w.bags(111, 1)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Crafted+1] discovery=true",
        found = "found=[Ada=1/1] realms=[Realm=1] all=1/1",
    },
    {
        name = "vendor purchase of a newly seen item",
        run = function(w)
            w.bags(100, 0)
            w.vendor(110, "purchase", 1)
            w.bags(111, 1)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Vendor+1] discovery=true",
        found = "found=[Ada=1/1] realms=[Realm=1] all=1/1",
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
        found = "found=[Ada=5/5] realms=[Realm=5] all=5/5",
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
        found = "found=[Ada=0/0] realms=[Realm=0] all=0/0",
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
        found = "found=[Ada=1/1] realms=[Realm=1] all=1/1",
    },
    {
        name = "mail from another player, item already held",
        run = function(w)
            w.bags(100, 5, "Ben")
            w.mail(110, "Ben", "in", 2, "Cara")
            w.bags(112, 7, "Ben")
        end,
        expect = "gained=2 first=110 last=110 firstSeenUnits=5 chars=[Ben=5] gains=[Obtained+2] discovery=false",
        found = "found=[Ben=7/7] realms=[Realm=7] all=7/7",
    },
    {
        name = "mail from another player, newly seen item",
        run = function(w)
            w.bags(100, 0, "Ben")
            w.mail(110, "Ben", "in", 2, "Cara")
            w.bags(112, 2, "Ben")
        end,
        expect = "gained=2 first=110 last=110 firstSeenUnits=0 chars=[Ben=0] gains=[Obtained+2] discovery=true",
        found = "found=[Ben=2/2] realms=[Realm=2] all=2/2",
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
        found = "found=[Ada=3/3,Ben=3/3] realms=[Realm=3] all=3/3",
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
        found = "found=[Ada=nil/3] realms=[Realm=3] all=nil/3",
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
        expect = "gained=1 first=110 last=110 firstSeenUnits=2 chars=[Ada=2,Ben=0] gains=[Obtained+1] discovery=false",
        found = "found=[Ada=2/2,Ben=1/1] realms=[Realm=3] all=3/3",
    },
    {
        name = "two items settled by one check",
        run = function(w)
            w.bags(100, 0, "Ada", 0)
            w.vendor(110, "purchase", 1)
            w.bags(111, 1, "Ada", 4)
        end,
        expect = "gained=1 first=110 last=110 firstSeenUnits=0 chars=[Ada=0] gains=[Vendor+1] discovery=true",
        found = "found=[Ada=1/1] realms=[Realm=1] all=1/1",
    },
}

local failures = {}
local function fail(rule, name, expected, actual)
    failures[#failures + 1] = rule .. ": " .. name .. "\n  expected " .. expected .. "\n  actual   " .. actual
end
for _, case in ipairs(cases) do
    local w = world()
    case.run(w)
    local live = facts(w.store():find(key), w.store())
    local reopened = w.reopen()
    local restored = facts(reopened:find(key), reopened)
    local expected = case.expect .. "\n" .. case.found
    if live ~= expected then
        fail("each confirmed gain counts once and every view shows what the characters hold", case.name, expected, live)
    elseif restored ~= live then
        fail("a reopened save shows the same Collection", case.name, live, restored)
    elseif reopened:diagnostic().kind ~= "healthy" then
        fail("a save the Ledger wrote reopens healthy", case.name, "healthy", reopened:diagnostic().kind)
    end
    local persisted = w.saved().records[key]
    if persisted and persisted.totalGained ~= w.store():find(key).totalGained then
        fail(
            "the saved Total gained matches the one shown",
            case.name,
            tostring(w.store():find(key).totalGained),
            tostring(persisted.totalGained)
        )
    end
end
do
    local w = world()
    cases[#cases].run(w)
    local expected = "gained=0 first=nil last=nil firstSeenUnits=4 chars=[Ada=4] gains=[] discovery=false"
        .. "\nfound=[Ada=4/4] realms=[Realm=4] all=4/4"
    local actual = facts(w.store():find(otherKey), w.store())
    if actual ~= expected then
        fail("an item that appears in a check without any action stays Seen", "second item", expected, actual)
    end
end

-- Every non-loot channel against the orderings that decide a discovery, with
-- Ben on Ada's realm and on another realm. The truth is what each character
-- holds: every character, realm and account view must show it.
local function act(w, channel, at, character)
    if channel == "quest" or channel == "craft" then
        local receipt = channel == "quest" and assert(addon.Reward.quest({}, 92463, link, 1))
            or assert(addon.Reward.craft({}, { itemID = 4540, hyperlink = link, quantity = 1 }))
        assert(w.store():rewardReceipt(receipt, at, w.actor(character)))
        if channel == "quest" then
            assert(w.store():questTurnedIn(92463, at, { character = character, realm = w.realm(character) }))
        end
    elseif channel == "vendor" then
        assert(
            w.store():vendorAction(
                { kind = "purchase", key = key, itemID = 4540, link = link, quantity = 1 },
                at,
                { character = character, realm = w.realm(character), level = 12, place = "Elwynn Forest" }
            )
        )
    else
        w.mail(at, character, "in", 1, "Cara")
    end
end
local orderings = {
    {
        name = "newly seen",
        run = function(w, channel)
            w.bags(100, 0)
            act(w, channel, 110, "Ada")
            w.bags(112, 1)
        end,
        holds = { Ada = 1 },
    },
    {
        name = "already held",
        run = function(w, channel)
            w.bags(100, 2)
            act(w, channel, 110, "Ada")
            w.bags(112, 3)
        end,
        holds = { Ada = 3 },
    },
    {
        name = "another character sees it first",
        run = function(w, channel)
            w.bags(100, 0)
            act(w, channel, 110, "Ada")
            w.bags(111, 1, "Ben")
            w.bags(112, 1)
        end,
        holds = { Ada = 1, Ben = 1 },
    },
    {
        name = "a new character gains it",
        run = function(w, channel)
            w.bags(100, 2)
            w.bags(101, 0, "Ben")
            act(w, channel, 110, "Ben")
            w.bags(112, 1, "Ben")
        end,
        holds = { Ada = 2, Ben = 1 },
    },
}
-- The view line facts() prints when every view shows what the characters hold.
local function truth(holds, realmOf)
    local characters, realms, total = {}, {}, 0
    for name, quantity in pairs(holds) do
        characters[#characters + 1] = name .. "=" .. quantity .. "/" .. quantity
        realms[realmOf[name]] = (realms[realmOf[name]] or 0) + quantity
        total = total + quantity
    end
    local realmViews = {}
    for realm, quantity in pairs(realms) do
        realmViews[#realmViews + 1] = realm .. "=" .. quantity
    end
    table.sort(characters)
    table.sort(realmViews)
    return "found=["
        .. table.concat(characters, ",")
        .. "] realms=["
        .. table.concat(realmViews, ",")
        .. "] all="
        .. total
        .. "/"
        .. total
end
for _, benRealm in ipairs({ "Realm", "Other Realm" }) do
    for _, channel in ipairs({ "quest", "craft", "vendor", "mail" }) do
        for _, ordering in ipairs(orderings) do
            local w = world()
            w.realms.Ben = benRealm
            ordering.run(w, channel)
            local found = facts(w.store():find(key), w.store()):match("\n(.*)$")
            local expected = truth(ordering.holds, w.realms)
            if found ~= expected then
                fail(
                    "every view shows what each character holds",
                    channel .. ", " .. ordering.name .. ", Ben on " .. benRealm,
                    expected,
                    found
                )
            end
        end
    end
end
-- Saves written before the Total found fix took a discovered vendor purchase's
-- units off the character's first-check units. This is the exact save that
-- code wrote after buying three newly seen items. Read now, it shows the three
-- units held; a refund, already saved or made after the update, leaves zero.
local function purchasedBeforeTheFix()
    return {
        areas = {
            ["Realm:Ada:bags"] = {
                character = "Ada",
                checkID = 2,
                complete = true,
                lastCompleteAt = 112,
                realm = "Realm",
                seenAt = 112,
            },
        },
        evidence = {
            discarded = 0,
            nextID = 1,
            unresolved = {},
        },
        journal = {
            gains = {
                {
                    at = 110,
                    id = "vendor:1:4540:0",
                    key = "4540:0",
                    sequence = 1,
                },
            },
            nextSequence = 2,
        },
        records = {
            ["4540:0"] = {
                characters = {
                    {
                        firstSeen = 112,
                        firstSeenLater = true,
                        firstSeenUnits = 0,
                        lastSeen = 112,
                        name = "Ada",
                        realm = "Realm",
                    },
                },
                evidencedDiscovery = true,
                firstGained = 110,
                firstSeen = 112,
                firstSeenLater = true,
                firstSeenUnits = 0,
                gains = {
                    {
                        at = 110,
                        character = "Ada",
                        id = "vendor:1:4540:0",
                        level = 12,
                        method = "Vendor",
                        place = "Elwynn Forest",
                        quantity = 3,
                        realm = "Realm",
                        source = {
                            kind = "vendor",
                            name = "Dermot",
                        },
                    },
                },
                itemID = 4540,
                key = "4540:0",
                lastGained = 110,
                lastSeen = 112,
                links = {
                    "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h",
                },
                observations = {
                    {
                        area = "bags",
                        character = "Ada",
                        quantity = 3,
                        realm = "Realm",
                        seenAt = 112,
                    },
                },
                totalGained = 3,
            },
        },
        schema = 2,
        vendor = {
            actions = {
                {
                    area = "bags",
                    at = 110,
                    baseline = 0,
                    baselineGained = 0,
                    character = "Ada",
                    id = 1,
                    itemID = 4540,
                    key = "4540:0",
                    kind = "purchase",
                    level = 12,
                    link = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h",
                    place = "Elwynn Forest",
                    quantity = 3,
                    realm = "Realm",
                    receiptQuantity = 3,
                    status = "confirmed",
                    vendorName = "Dermot",
                },
            },
            journal = {},
            nextID = 2,
        },
    }
end

local function refundedBeforeTheFix()
    local raw = purchasedBeforeTheFix()
    local record = raw.records[key]
    record.gains[1].refunded = 3
    record.totalGained = 0
    record.observations[2] = { area = "bags", character = "Ada", quantity = 0, realm = "Realm", seenAt = 114 }
    raw.areas["Realm:Ada:bags"].seenAt, raw.areas["Realm:Ada:bags"].lastCompleteAt = 114, 114
    raw.areas["Realm:Ada:bags"].checkID = 3
    return raw
end

local function totalFound(store)
    local projection = addon.LastSeen.project(store, store:find(key), "Ada", "Realm")
    return projection.characterOverall, projection.allCharactersOverall
end

do
    local store = addon.Schema.open(refundedBeforeTheFix(), function() end)
    local character, account = totalFound(store)
    if character ~= 0 or account ~= 0 then
        fail(
            "an item bought and refunded before the update shows Total found 0",
            "saved refund",
            "0 / 0",
            tostring(character) .. " / " .. tostring(account)
        )
    end
end
do
    local store = addon.Schema.open(purchasedBeforeTheFix(), function() end)
    local held, heldAccount = totalFound(store)
    if held ~= 3 or heldAccount ~= 3 then
        fail(
            "an item bought before the update shows the units bought",
            "saved purchase",
            "3 / 3",
            tostring(held) .. " / " .. tostring(heldAccount)
        )
    end
    assert(
        store:vendorAction(
            { kind = "refund", key = key, itemID = 4540, link = link, quantity = 3 },
            113,
            { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest", vendorName = "Dermot" }
        )
    )
    assert(store:scan({ character = "Ada", realm = "Realm", area = "bags", seenAt = 114, complete = true, items = {} }))
    local character, account = totalFound(store)
    if store:find(key).totalGained ~= 0 or character ~= 0 or account ~= 0 then
        fail(
            "a refund after the update of an item bought before it shows Total found 0",
            "refund after update",
            "0 / 0",
            tostring(character) .. " / " .. tostring(account)
        )
    end
end
assert(#failures == 0, "\n" .. table.concat(failures, "\n"))

print("total_gained_spec: passed")
