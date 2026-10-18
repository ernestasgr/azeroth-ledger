local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerJournal")
local link = "|Hitem:4540::::::::|h[Bread]|h"
local key = addon.Item.key(link, 4540)

local function fixture()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
    local at = 1000
    local function bags(quantity)
        WoWUnit.IsTrue(store:scan({
            character = actor.character,
            realm = actor.realm,
            area = "bags",
            complete = true,
            seenAt = at,
            items = quantity > 0 and { { itemID = 4540, link = link, quantity = quantity } } or {},
        }))
        at = at + 1
    end
    local function action(kind, quantity)
        WoWUnit.IsTrue(
            store:command(
                "vendorAction",
                { kind = kind, key = key, itemID = 4540, link = link, quantity = quantity },
                at,
                actor
            )
        )
        at = at + 1
    end
    bags(0)
    return store,
        bags,
        action,
        function()
            store = addon.Schema.open(saved, function(value)
                saved = value
            end)
            return store
        end,
        function(value)
            at = value
        end,
        actor
end

function tests.LimitsAreIndependentAndTiesKeepCommitOrder(_self)
    local store, bags, action, restore, clock = fixture()
    WoWUnit.IsTrue(store:setRetention("gains", 1))
    WoWUnit.IsTrue(store:setRetention("vendor", 2))
    action("purchase", 1)
    bags(1)
    clock(1001)
    action("sale", 1)
    bags(0)
    local rows = addon.Journal.query(store)
    WoWUnit.AreEqual("vendor", rows[1].category)
    WoWUnit.AreEqual("gain", rows[2].category)
    WoWUnit.IsTrue(rows[1].sequence > rows[2].sequence)
    clock(1010)
    action("purchase", 2)
    bags(2)
    action("sale", 2)
    bags(0)
    WoWUnit.AreEqual(3, #addon.Journal.query(store))
    WoWUnit.AreEqual(1, addon.Journal.query(store)[3].quantity)
    WoWUnit.IsTrue(store:setRetention("vendor", 0))
    WoWUnit.AreEqual(1, #addon.Journal.query(store))
    WoWUnit.AreEqual(3, store:breakdown(key).recorded)
    store = restore()
    WoWUnit.AreEqual(1, #addon.Journal.query(store))
    WoWUnit.AreEqual(0, store:retention().vendor)
    for _, category in ipairs({ "gains", "transfers", "vendor" }) do
        WoWUnit.IsTrue(store:setRetention(category, category == "gains" and 5000 or 2000))
        WoWUnit.AreEqual(false, store:setRetention(category, category == "gains" and 5001 or 2001))
        WoWUnit.AreEqual(false, store:setRetention(category, -1))
        WoWUnit.AreEqual(false, store:setRetention(category, 0.5))
    end
end

function tests.SettingsUsePersistedStoreValuesAndExplicitZero(_self)
    local store = fixture()
    local setters, options = {}, {}
    local api = {
        Settings = {
            VarType = { Number = "number", Boolean = "boolean", String = "string" },
            CreateCheckbox = function() end,
            CreateColorSwatch = function() end,
            RegisterVerticalLayoutSubcategory = function()
                return {}, { AddInitializer = function() end }
            end,
            RegisterVerticalLayoutCategory = function(name)
                return { name = name }
            end,
            RegisterProxySetting = function(_, variable, kind, _, default, get, set)
                WoWUnit.IsTrue(kind == "number" or kind == "boolean" or kind == "string")
                WoWUnit.AreEqual(default, get())
                setters[variable] = set
                return variable
            end,
            CreateSliderOptions = function(minimum, maximum, step)
                return { minimum = minimum, maximum = maximum, step = step }
            end,
            CreateSlider = function(_, setting, limits, help)
                options[setting] = limits
                if
                    setting == "AzerothLedger_gains"
                    or setting == "AzerothLedger_transfers"
                    or setting == "AzerothLedger_vendor"
                then
                    WoWUnit.IsTrue(help:find("0", 1, true) ~= nil)
                end
            end,
            RegisterAddOnCategory = function(category)
                WoWUnit.AreEqual("Azeroth Ledger", category.name)
            end,
        },
    }
    WoWUnit.IsTrue(addon.Settings.register(api, store))
    setters.AzerothLedger_gains(0)
    setters.AzerothLedger_transfers(2000)
    setters.AzerothLedger_vendor(2)
    WoWUnit.AreEqual(0, store:retention().gains)
    WoWUnit.AreEqual(2000, store:retention().transfers)
    WoWUnit.AreEqual(2, store:retention().vendor)
    WoWUnit.AreEqual(5000, options.AzerothLedger_gains.maximum)
    WoWUnit.AreEqual(0, options.AzerothLedger_transfers.minimum)
    WoWUnit.AreEqual(1, options.AzerothLedger_vendor.step)
    WoWUnit.AreEqual(false, addon.Settings.register({}, store))
end

function tests.TransferLimitPreservesStockAndDiscoveryDates(_self)
    local store, bags, action, _, clock, actor = fixture()
    action("purchase", 3)
    bags(3)
    local function scan(character, at, quantity)
        WoWUnit.IsTrue(store:scan({
            character = character,
            realm = "Realm",
            area = "bags",
            complete = true,
            seenAt = at,
            items = quantity > 0 and { { itemID = 4540, link = link, quantity = quantity } } or {},
        }))
    end
    scan("Ben", 1004, 0)
    local function exchange(character, peer, direction, at)
        local who = { character = character, realm = "Realm", level = 12, place = "Elwynn" }
        WoWUnit.IsTrue(store:command("exchangeIntent", {
            channel = "mail",
            direction = direction,
            key = key,
            itemID = 4540,
            link = link,
            quantity = 1,
            peerName = peer,
            peerRealm = "Realm",
        }, at, who))
        WoWUnit.IsTrue(store:command("exchangeConfirm", { channel = "mail", direction = direction }, at + 1, who))
    end
    exchange(actor.character, "Ben", "out", 1005)
    scan("Ada", 1007, 2)
    exchange("Ben", "Ada", "in", 1008)
    scan("Ben", 1010, 1)
    WoWUnit.IsTrue(store:setRetention("transfers", 1))
    exchange("Ada", "Ben", "out", 1011)
    scan("Ada", 1013, 1)
    exchange("Ben", "Ada", "in", 1014)
    scan("Ben", 1016, 2)
    WoWUnit.AreEqual(1, #store:exchangeActivity())
    WoWUnit.AreEqual(1014, store:exchangeActivity()[1].at)
    local rows = addon.Journal.query(store)
    WoWUnit.AreEqual("transfer", rows[1].category)
    WoWUnit.AreEqual("Ada-Realm → Ben-Realm", rows[1].actors)
    local before = store:find(key)
    local totals = store:breakdown(key)
    WoWUnit.IsTrue(store:setRetention("transfers", 0))
    WoWUnit.AreEqual(0, #store:exchangeActivity())
    WoWUnit.AreEqual(1, #addon.Journal.query(store))
    WoWUnit.AreEqual(before.firstSeen, store:find(key).firstSeen)
    WoWUnit.AreEqual(before.firstGained, store:find(key).firstGained)
    WoWUnit.AreEqual(totals.recorded, store:breakdown(key).recorded)
    WoWUnit.AreEqual(totals.methods.Vendor, store:breakdown(key).methods.Vendor)
    WoWUnit.AreEqual(totals.sources.Unknown, store:breakdown(key).sources.Unknown)
    clock(1020)
    action("sale", 1)
    bags(0)
    WoWUnit.AreEqual(1, #store:vendorActivity())
end

function tests.DanglingHistoryIsIsolatedWithADiagnostic(_self)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
    local function scan(at, quantity)
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            complete = true,
            seenAt = at,
            items = {
                { itemID = 4540, link = link, quantity = quantity },
                { itemID = 159, link = "|Hitem:159::::::::|h[Water]|h", quantity = 1 },
            },
        }))
    end
    scan(100, 2)
    WoWUnit.IsTrue(
        store:command(
            "vendorAction",
            { kind = "sale", key = key, itemID = 4540, link = link, quantity = 1 },
            101,
            actor
        )
    )
    scan(102, 1)
    saved.records[key] = "damaged"
    store = addon.Schema.open(saved, function() end)
    WoWUnit.AreEqual("damaged", store:diagnostic().kind)
    WoWUnit.AreEqual(1, #store:list())
    WoWUnit.AreEqual(0, #addon.Journal.query(store))
    local unsupported = addon.Schema.open(42, function()
        error("Read-only data was written")
    end)
    WoWUnit.AreEqual(1000, unsupported:retention().gains)
    WoWUnit.AreEqual(false, unsupported:setRetention("gains", 0))
end

function tests.PurchaseIsOneGainAndZeroRetentionPreservesRefundReferences(_self)
    local store, bags, action, saved = fixture()
    WoWUnit.AreEqual(1000, store:retention().gains)
    WoWUnit.AreEqual(250, store:retention().transfers)
    WoWUnit.AreEqual(250, store:retention().vendor)
    action("purchase", 3)
    bags(3)
    local rows = addon.Journal.query(store)
    WoWUnit.AreEqual(1, #rows)
    WoWUnit.AreEqual("gain", rows[1].category)
    WoWUnit.AreEqual(3, rows[1].quantity)
    local before = store:breakdown(key)
    WoWUnit.IsTrue(store:setRetention("gains", 0))
    WoWUnit.AreEqual(0, #addon.Journal.query(store))
    WoWUnit.AreEqual(before.recorded, store:breakdown(key).recorded)
    WoWUnit.AreEqual(before.methods.Vendor, store:breakdown(key).methods.Vendor)
    WoWUnit.AreEqual(before.sources.Unknown, store:breakdown(key).sources.Unknown)
    WoWUnit.IsTrue(store:correctGain({
        id = "vendor-name",
        key = key,
        gainID = store:find(key).gains[1].id,
        quantity = 3,
        fromMethod = "Vendor",
        method = "Vendor",
        source = { kind = "vendor", name = "Dermot" },
    }))
    WoWUnit.AreEqual(3, store:breakdown(key).sources["Vendor: Dermot"])
    WoWUnit.AreEqual(
        3,
        addon.Collection.query(store, "Ada", "Realm", { source = "vendor:Dermot" }).rows[1].sourceQuantity
    )
    WoWUnit.AreEqual(0, #addon.Journal.query(store))
    store = saved()
    WoWUnit.AreEqual(0, store:retention().gains)
    WoWUnit.AreEqual(0, #addon.Journal.query(store))
    action("refund", 3)
    bags(0)
    WoWUnit.AreEqual(0, store:breakdown(key).gained)
    WoWUnit.AreEqual(0, #addon.Collection.query(store, "Ada", "Realm", { source = "vendor:Dermot" }).rows)
    WoWUnit.AreEqual(1, #store:vendorActivity())
end

function tests.ExactHistoryExplainsPartialRefundAndKeepsPrunedPurchaseAbsent(_self)
    local store, bags, action, restore = fixture()
    action("purchase", 3)
    bags(3)
    action("refund", 1)
    bags(2)
    local rows = addon.Journal.query(store, { historyKey = key })
    WoWUnit.AreEqual(2, #rows)
    WoWUnit.AreEqual(2, rows[2].netQuantity)
    WoWUnit.AreEqual(1, rows[2].refunded)
    WoWUnit.AreEqual(rows[2].sequence, rows[1].purchaseSequence)
    WoWUnit.AreEqual(rows[1].sequence, rows[2].refundSequences[1])
    WoWUnit.AreEqual("Elwynn", rows[1].place)
    WoWUnit.AreEqual(12, rows[1].level)
    WoWUnit.AreEqual(0, #addon.Journal.query(store, { historyKey = "4540:99" }))
    store = restore()
    WoWUnit.AreEqual(rows[2].sequence, addon.Journal.query(store)[1].purchaseSequence)
    WoWUnit.IsTrue(store:setRetention("gains", 0))
    rows = addon.Journal.query(store, { historyKey = key })
    WoWUnit.AreEqual(1, #rows)
    WoWUnit.AreEqual(nil, rows[1].purchaseSequence)
    WoWUnit.IsTrue(rows[1].linkedGainID ~= nil)
    WoWUnit.AreEqual(2, store:breakdown(key).gained)
end

function tests.ProvenExchangeChannelsSurviveReloadAndUnknownHistoryStaysUnknown(_self)
    for _, channel in ipairs({ "mail", "trade" }) do
        local saved
        local store = addon.Schema.open(nil, function(value)
            saved = value
        end)
        local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
        local function scan(at, quantity)
            WoWUnit.IsTrue(store:scan({
                character = "Ada",
                realm = "Realm",
                area = "bags",
                complete = true,
                seenAt = at,
                items = quantity > 0 and { { itemID = 4540, link = link, quantity = quantity } } or {},
            }))
        end
        scan(100, 0)
        WoWUnit.IsTrue(store:command("exchangeIntent", {
            channel = channel,
            direction = "in",
            key = key,
            itemID = 4540,
            link = link,
            quantity = 2,
            peerName = "Cara",
            peerRealm = "OtherRealm",
        }, 101, actor))
        WoWUnit.IsTrue(store:command("exchangeConfirm", { channel = channel, direction = "in" }, 102, actor))
        scan(103, 2)
        store = addon.Schema.open(saved, function(value)
            saved = value
        end)
        local row = addon.Journal.query(store, { historyKey = key })[1]
        WoWUnit.AreEqual(channel == "mail" and "Mail" or "Trade", row.action)
        WoWUnit.AreEqual("Cara-OtherRealm", row.details[1].source)
        WoWUnit.AreEqual("Elwynn", row.details[1].place)
        WoWUnit.AreEqual(12, row.details[1].level)
        WoWUnit.IsTrue(store:correctGain({
            id = "source-name",
            key = key,
            gainID = store:find(key).gains[1].id,
            quantity = 1,
            fromMethod = "Obtained",
            method = "Obtained",
            fromSource = { kind = "player", name = "Cara", realm = "OtherRealm" },
            source = { kind = "player", name = "Dana", realm = "OtherRealm" },
        }))
        store = addon.Schema.open(saved, function(value)
            saved = value
        end)
        local rows = addon.Journal.query(store, { historyKey = key })
        WoWUnit.AreEqual(1, #rows)
        WoWUnit.AreEqual(2, rows[1].quantity)
        WoWUnit.AreEqual(2, #rows[1].details)
        for _, gain in ipairs(rows[1].contributions) do
            WoWUnit.AreEqual(channel, gain.channel)
        end
        -- Historical records without a saved channel cannot prove mail or trade.
        for _, gain in ipairs(saved.records[key].gains) do
            gain.channel = nil
        end
        store = addon.Schema.open(saved, function() end)
        for _, detail in ipairs(addon.Journal.query(store)[1].details) do
            WoWUnit.AreEqual("Obtained (way unknown)", detail.method)
        end
        WoWUnit.IsTrue(store:setRetention("gains", 0))
        WoWUnit.AreEqual(0, #addon.Journal.query(store))
        WoWUnit.AreEqual(2, store:breakdown(key).gained)
    end
end

function tests.SameNamedIntrinsicVariantsHaveSeparateReadOnlyHistory(_self)
    local writes = 0
    local store = addon.Schema.open(nil, function()
        writes = writes + 1
    end)
    local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
    local items = {}
    local function scan(at)
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            complete = true,
            seenAt = at,
            items = items,
        }))
    end
    scan(100)
    for index, suffix in ipairs({ 0, 99 }) do
        local variant = "|Hitem:4540:0:0:0:0:0:" .. suffix .. ":0|h[Bread]|h"
        local variantKey = addon.Item.key(variant, 4540)
        WoWUnit.IsTrue(store:command("vendorAction", {
            kind = "purchase",
            key = variantKey,
            itemID = 4540,
            link = variant,
            quantity = index,
        }, 100 + index * 2, actor))
        items[#items + 1] = { itemID = 4540, link = variant, quantity = index }
        scan(101 + index * 2)
    end
    local before = writes
    for index, suffix in ipairs({ 0, 99 }) do
        local rows = addon.Journal.query(store, { historyKey = "4540:" .. suffix })
        WoWUnit.AreEqual(1, #rows)
        WoWUnit.AreEqual(index, rows[1].quantity)
        WoWUnit.AreEqual("4540:" .. suffix, rows[1].key)
    end
    WoWUnit.AreEqual(before, writes)
end
function tests.JournalFiltersCombineScopeActionAndHalfOpenDates(_self)
    local store, bags, action, _, clock, actor = fixture()
    action("purchase", 2)
    bags(2)
    clock(2000)
    action("sale", 1)
    bags(1)
    actor.character, actor.realm = "Ben", "Other"
    clock(2998)
    bags(0)
    clock(3000)
    action("purchase", 1)
    bags(1)
    WoWUnit.AreEqual(3, #addon.Journal.query(store))
    local rows = addon.Journal.query(
        store,
        { character = "Ada", realm = "Realm", action = "Sale", dateFrom = 2000, dateTo = 2001, search = "Bread" }
    )
    WoWUnit.AreEqual(1, #rows)
    WoWUnit.AreEqual("Sale", rows[1].action)
    WoWUnit.AreEqual(0, #addon.Journal.query(store, { dateTo = 1001 }))
    WoWUnit.AreEqual(1, #addon.Journal.query(store, { realm = "Other" }))
    WoWUnit.AreEqual(0, #addon.Journal.query(store, { action = "Looted" }))
    WoWUnit.AreEqual(0, #addon.Journal.query(store, { dateFrom = 3000, dateTo = 2000 }))
end
