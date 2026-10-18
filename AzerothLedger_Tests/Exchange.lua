local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerExchange")
local link = "|Hitem:159::::::::|h[Refreshing Spring Water]|h"
local key = addon.Item.key(link, 159)

local function actor(character, at)
    return { character = character, realm = "Realm", level = 12, place = "Elwynn Forest", at = at }
end

local function scan(store, character, at, quantity)
    local items = quantity > 0 and { { itemID = 159, link = link, quantity = quantity } } or {}
    WoWUnit.IsTrue(store:scan({
        character = character,
        realm = "Realm",
        area = "bags",
        seenAt = at,
        complete = true,
        items = items,
    }))
end

local function intent(store, character, at, channel, direction, quantity, peer)
    local entry = {
        channel = channel,
        direction = direction,
        key = key,
        itemID = 159,
        link = link,
        quantity = quantity,
        peerName = peer,
        peerRealm = peer and "Realm" or nil,
    }
    WoWUnit.IsTrue(store:command("exchangeIntent", entry, at, actor(character, at)))
end

local function confirm(store, character, at, channel, direction)
    WoWUnit.IsTrue(
        store:command("exchangeConfirm", { channel = channel, direction = direction }, at, actor(character, at))
    )
end

function tests.AltMailWaitsForTakeAndSurvivesReplay(_self)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    scan(store, "Ada", 100, 3)
    scan(store, "Ben", 100, 3)
    intent(store, "Ada", 101, "mail", "out", 3, "Ben")
    confirm(store, "Ada", 102, "mail", "out")
    scan(store, "Ada", 103, 0)
    scan(store, "Ben", 104, 3) -- opening the message is not a gain
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    intent(store, "Ben", 105, "mail", "in", 3, "Ada")
    confirm(store, "Ben", 106, "mail", "in")
    WoWUnit.AreEqual(
        false,
        store:command("exchangeConfirm", { channel = "mail", direction = "in" }, 106, actor("Ben", 106))
    )
    scan(store, "Ben", 107, 6)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual(1, #store:exchangeActivity())
    WoWUnit.AreEqual(3, store:exchangeActivity()[1].quantity)
    local restored = addon.Schema.open(saved, function(value)
        saved = value
    end)
    scan(restored, "Ben", 108, 6)
    WoWUnit.AreEqual(1, #restored:exchangeActivity())
    WoWUnit.AreEqual(0, restored:find(key).totalGained)
end

function tests.OutsideMailNeedsIncreaseAndHasPlayerSource(_self)
    local store = addon.Schema.open(nil, function() end)
    scan(store, "Ben", 200, 5)
    intent(store, "Ben", 201, "mail", "in", 2, "Cara")
    confirm(store, "Ben", 202, "mail", "in")
    scan(store, "Ben", 203, 5)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    scan(store, "Ben", 204, 7)
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    WoWUnit.AreEqual("Obtained", store:find(key).gains[1].method)
    WoWUnit.AreEqual("Cara", store:find(key).gains[1].source.name)
    WoWUnit.AreEqual("Realm", store:find(key).gains[1].source.realm)
    local saved
    local persistent = addon.Schema.open(nil, function(value)
        saved = value
    end)
    scan(persistent, "Ben", 210, 5)
    intent(persistent, "Ben", 211, "mail", "in", 2, "Cara")
    confirm(persistent, "Ben", 212, "mail", "in")
    scan(persistent, "Ben", 213, 7)
    WoWUnit.AreEqual("healthy", addon.Schema.open(saved, function() end):diagnostic().kind)
end

function tests.CompletedTradeAndCanceledTrade(_self)
    local store = addon.Schema.open(nil, function() end)
    scan(store, "Ben", 300, 1)
    intent(store, "Ben", 301, "trade", "in", 2, "Cara")
    scan(store, "Ben", 302, 1)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.IsTrue(store:command("exchangeCancel", "trade", 303, actor("Ben", 303)))
    intent(store, "Ben", 303, "trade", "in", 2, "Dana")
    confirm(store, "Ben", 304, "trade", "in")
    scan(store, "Ben", 305, 3)
    WoWUnit.AreEqual(2, store:find(key).totalGained)
end

function tests.ConcurrentSameItemAndUncertainAltRemainUnresolved(_self)
    local store = addon.Schema.open(nil, function() end)
    scan(store, "Ada", 400, 1)
    scan(store, "Ben", 400, 1)
    intent(store, "Ada", 401, "mail", "out", 3, "Ben")
    confirm(store, "Ada", 402, "mail", "out")
    scan(store, "Ada", 403, 0)
    intent(store, "Ben", 404, "mail", "in", 3, "Ada")
    confirm(store, "Ben", 405, "mail", "in")
    scan(store, "Ben", 406, 4)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual(0, #store:exchangeActivity())
    WoWUnit.IsTrue(#store:exchangeUnresolved() > 0)

    local outside = addon.Schema.open(nil, function() end)
    scan(outside, "Ben", 500, 1)
    intent(outside, "Ben", 501, "trade", "in", 1, "Cara")
    intent(outside, "Ben", 501, "mail", "in", 2, "Dana")
    confirm(outside, "Ben", 502, "trade", "in")
    confirm(outside, "Ben", 502, "mail", "in")
    scan(outside, "Ben", 503, 2)
    WoWUnit.AreEqual(1, outside:find(key).totalGained)
    WoWUnit.AreEqual(1, #outside:find(key).gains)

    local both = addon.Schema.open(nil, function() end)
    scan(both, "Ben", 600, 1)
    intent(both, "Ben", 601, "trade", "in", 1, "Cara")
    intent(both, "Ben", 601, "mail", "in", 2, "Dana")
    confirm(both, "Ben", 602, "trade", "in")
    confirm(both, "Ben", 602, "mail", "in")
    scan(both, "Ben", 603, 4)
    WoWUnit.AreEqual(3, both:find(key).totalGained)
end

function tests.ClientAdaptersReadAttachmentAndTradeQuantities(_self)
    local api = {
        GetInboxNumItems = function()
            return 1
        end,
        GetInboxHeaderInfo = function()
            return nil, nil, "Cara-Realm", nil, 0, 0, 30, 1, false, false, false, true
        end,
        GetInboxItemLink = function(_, slot)
            return slot == 1 and link or nil
        end,
        GetInboxItem = function(_, slot)
            if slot == 1 then
                return "Water", 159, nil, 3
            end
        end,
        GetSendMailItem = function(slot)
            if slot == 1 then
                return "Water", 159, nil, 3
            end
        end,
        GetItemInfo = function()
            return "Water", link
        end,
        GetTradeTargetItemLink = function(slot)
            return slot == 1 and link or nil
        end,
        GetTradeTargetItemInfo = function(slot)
            if slot == 1 then
                return "Water", nil, 2
            end
        end,
        GetTradePlayerItemLink = function(slot)
            return slot == 1 and link or nil
        end,
        GetTradePlayerItemInfo = function(slot)
            if slot == 1 then
                return "Water", nil, 1
            end
        end,
    }
    WoWUnit.AreEqual(3, addon.Exchange.inbox(api)["1:1"].quantity)
    WoWUnit.AreEqual("Realm", addon.Exchange.inbox(api)["1:1"].peerRealm)
    WoWUnit.AreEqual(3, addon.Exchange.outbox(api)[1].quantity)
    WoWUnit.AreEqual(2, addon.Exchange.trade(api, "in")[1].quantity)
    WoWUnit.AreEqual(1, addon.Exchange.trade(api, "out")[1].quantity)
end

function tests.AmbiguousPlayerHasUnknownSourceAndMissingPlayerIsUnresolved(_self)
    local store = addon.Schema.open(nil, function() end)
    scan(store, "Ben", 700, 0)
    WoWUnit.IsTrue(store:command("exchangeIntent", {
        channel = "mail",
        direction = "in",
        key = key,
        itemID = 159,
        link = link,
        quantity = 1,
        peerName = "Cara",
    }, 701, actor("Ben", 701)))
    confirm(store, "Ben", 702, "mail", "in")
    scan(store, "Ben", 703, 1)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    WoWUnit.AreEqual(nil, store:find(key).gains[1].source)
    WoWUnit.IsTrue(store:command("exchangeIntent", {
        channel = "mail",
        direction = "in",
        key = key,
        itemID = 159,
        link = link,
        quantity = 1,
    }, 704, actor("Ben", 704)))
    confirm(store, "Ben", 705, "mail", "in")
    scan(store, "Ben", 706, 2)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    WoWUnit.IsTrue(#store:exchangeUnresolved() > 0)
end

function tests.PartialAltReceiptsAndOtherCharacterGains(_self)
    local store = addon.Schema.open(nil, function() end)
    scan(store, "Ada", 800, 3)
    scan(store, "Ben", 800, 0)
    intent(store, "Ada", 801, "mail", "out", 3, "Ben")
    confirm(store, "Ada", 802, "mail", "out")
    scan(store, "Ada", 803, 0)
    WoWUnit.IsTrue(store:command("exchangeIntent", {
        channel = "mail",
        direction = "in",
        key = key,
        itemID = 159,
        link = link,
        quantity = 2,
        peerName = "Ada",
    }, 804, actor("Ben", 804)))
    confirm(store, "Ben", 805, "mail", "in")
    scan(store, "Ben", 806, 2)
    WoWUnit.AreEqual(2, store:exchangeActivity()[1].quantity)
    intent(store, "Ben", 807, "mail", "in", 1, "Ada")
    confirm(store, "Ben", 808, "mail", "in")
    scan(store, "Ben", 809, 3)
    WoWUnit.AreEqual(2, #store:exchangeActivity())
    WoWUnit.AreEqual(0, store:find(key).totalGained)

    local concurrent = addon.Schema.open(nil, function() end)
    scan(concurrent, "Ada", 900, 0)
    scan(concurrent, "Ben", 900, 0)
    intent(concurrent, "Ben", 901, "mail", "in", 1, "Cara")
    intent(concurrent, "Ada", 902, "mail", "in", 1, "Dana")
    confirm(concurrent, "Ada", 903, "mail", "in")
    scan(concurrent, "Ada", 904, 1)
    confirm(concurrent, "Ben", 905, "mail", "in")
    scan(concurrent, "Ben", 906, 1)
    WoWUnit.AreEqual(2, concurrent:find(key).totalGained)
end

function tests.SuccessConfirmsOnlySelectedAttachment(_self)
    local store = addon.Schema.open(nil, function() end)
    scan(store, "Ben", 1000, 0)
    local first = store:command("exchangeIntent", {
        channel = "mail",
        direction = "in",
        key = key,
        itemID = 159,
        link = link,
        quantity = 1,
        peerName = "Cara",
        peerRealm = "Realm",
    }, 1001, actor("Ben", 1001))
    store:command("exchangeIntent", {
        channel = "mail",
        direction = "in",
        key = key,
        itemID = 159,
        link = link,
        quantity = 1,
        peerName = "Dana",
        peerRealm = "Realm",
    }, 1001, actor("Ben", 1001))
    WoWUnit.IsTrue(
        store:command("exchangeConfirm", { channel = "mail", direction = "in", ids = first }, 1002, actor("Ben", 1002))
    )
    scan(store, "Ben", 1003, 2)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
end

function tests.ReturnedOwnMailDoesNotAddGainsOrDiscoveries(_self)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    scan(store, "Ada", 1100, 2)
    intent(store, "Ada", 1101, "mail", "out", 2, "Cara")
    confirm(store, "Ada", 1102, "mail", "out")
    scan(store, "Ada", 1103, 0)
    local returned = {
        channel = "mail",
        direction = "in",
        key = key,
        itemID = 159,
        link = link,
        quantity = 2,
        peerName = "Cara",
        peerRealm = "Realm",
        mailKind = "return",
    }
    WoWUnit.IsTrue(store:command("exchangeIntent", returned, 1104, actor("Ada", 1104)))
    confirm(store, "Ada", 1105, "mail", "in")
    scan(store, "Ada", 1106, 2)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual(2, store:breakdown(key).recorded)
    WoWUnit.AreEqual(0, #store:exchangeActivity())
    WoWUnit.AreEqual(nil, store:find(key).evidencedDiscovery)
    WoWUnit.AreEqual("healthy", addon.Schema.open(saved, function() end):diagnostic().kind)
    -- The same outgoing units cannot prove a second return.
    scan(store, "Ada", 1107, 0)
    WoWUnit.IsTrue(store:command("exchangeIntent", returned, 1108, actor("Ada", 1108)))
    confirm(store, "Ada", 1109, "mail", "in")
    scan(store, "Ada", 1110, 2)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual(1, #store:exchangeUnresolved())
end

function tests.AuctionBuyerInvoiceCountsAndUnprovenReturnStaysUnresolved(_self)
    local store = addon.Schema.open(nil, function() end)
    scan(store, "Ben", 1200, 0)
    local entry = {
        channel = "mail",
        direction = "in",
        key = key,
        itemID = 159,
        link = link,
        quantity = 1,
        mailKind = "auction-purchase",
    }
    WoWUnit.IsTrue(store:command("exchangeIntent", entry, 1201, actor("Ben", 1201)))
    confirm(store, "Ben", 1202, "mail", "in")
    scan(store, "Ben", 1203, 1)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    WoWUnit.AreEqual("auction-purchase", store:find(key).gains[1].mailKind)
    WoWUnit.AreEqual(nil, store:find(key).gains[1].source)
    entry.mailKind = "return"
    entry.peerName = "Cara"
    WoWUnit.IsTrue(store:command("exchangeIntent", entry, 1204, actor("Ben", 1204)))
    confirm(store, "Ben", 1205, "mail", "in")
    scan(store, "Ben", 1206, 2)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    WoWUnit.AreEqual(1, #store:exchangeUnresolved())
end
