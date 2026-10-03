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
            store:vendorAction({ kind = kind, key = key, itemID = 4540, link = link, quantity = quantity }, at, actor)
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
            VarType = { Number = "number" },
            RegisterVerticalLayoutCategory = function(name)
                return { name = name }
            end,
            RegisterProxySetting = function(_, variable, kind, _, default, get, set)
                WoWUnit.AreEqual("number", kind)
                WoWUnit.AreEqual(default, get())
                setters[variable] = set
                return variable
            end,
            CreateSliderOptions = function(minimum, maximum, step)
                return { minimum = minimum, maximum = maximum, step = step }
            end,
            CreateSlider = function(_, setting, limits, help)
                options[setting] = limits
                WoWUnit.IsTrue(help:find("0", 1, true) ~= nil)
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
        WoWUnit.IsTrue(store:exchangeIntent({
            channel = "mail",
            direction = direction,
            key = key,
            itemID = 4540,
            link = link,
            quantity = 1,
            peerName = peer,
            peerRealm = "Realm",
        }, at, who))
        WoWUnit.IsTrue(store:exchangeConfirm("mail", direction, at + 1, who))
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
        store:vendorAction({ kind = "sale", key = key, itemID = 4540, link = link, quantity = 1 }, 101, actor)
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
    WoWUnit.AreEqual(3, store:breakdown(key).sources.Dermot)
    WoWUnit.AreEqual(0, #addon.Journal.query(store))
    store = saved()
    WoWUnit.AreEqual(0, store:retention().gains)
    WoWUnit.AreEqual(0, #addon.Journal.query(store))
    action("refund", 3)
    bags(0)
    WoWUnit.AreEqual(0, store:breakdown(key).gained)
    WoWUnit.AreEqual(1, #store:vendorActivity())
end
