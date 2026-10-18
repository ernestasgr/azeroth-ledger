local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerPresentation")
local link = "|Hitem:4540::::::::|h[Bread]|h"
local key = addon.Item.key(link, 4540)

local function fixture()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local at = 1000
    local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
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
    local function purchase()
        WoWUnit.IsTrue(
            store:command(
                "vendorAction",
                { kind = "purchase", key = key, itemID = 4540, link = link, quantity = 1 },
                at,
                actor
            )
        )
        at = at + 1
    end
    return store,
        bags,
        purchase,
        function()
            return addon.Schema.open(saved, function(value)
                saved = value
            end)
        end
end

function tests.LootDiscoveryWaitsForReceiptAndKeepsUnknownSource(_self)
    local store, bags = fixture()
    bags(0)
    WoWUnit.IsTrue(
        store:command(
            "lootOpen",
            { slots = { { key = key, quantity = 1 } } },
            1001,
            { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
        )
    )
    bags(1)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    local actor = { character = "Ada", realm = "Realm" }
    WoWUnit.IsTrue(store:command("lootReceipt", { key = key, quantity = 1 }, 1002, actor))
    WoWUnit.AreEqual(1, #store:takeDiscoveries())
    WoWUnit.AreEqual(
        "Azeroth Ledger: Looted • total gained 1 • status Present • source Unknown",
        addon.Presentation.line(store, link, "Ada", "Realm"):match("^[^\n]+")
    )
    store:command("lootReceipt", { key = key, quantity = 1 }, 1002, actor)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
end

function tests.RewardsDiscoverOnceWithZeroJournalRetention(_self)
    for _, method in ipairs({ "Quest", "Crafted" }) do
        local store, bags = fixture()
        WoWUnit.IsTrue(store:setRetention("gains", 0))
        bags(0)
        local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
        local reward = {
            key = key,
            itemID = 4540,
            link = link,
            quantity = 1,
            method = method,
            context = { kind = method == "Quest" and "quest" or "recipe", id = 123, name = "Proven reward" },
        }
        WoWUnit.IsTrue(store:command("rewardReceipt", reward, 1001, actor))
        if method == "Quest" then
            WoWUnit.IsTrue(store:command("questTurnedIn", 123, 1001, actor))
        end
        bags(1)
        WoWUnit.AreEqual(1, #store:takeDiscoveries())
        WoWUnit.AreEqual(0, #store:journal())
        WoWUnit.AreEqual(
            "Azeroth Ledger: Obtained (" .. method .. ") • total gained 1 • status Present • source Proven reward",
            addon.Presentation.line(store, link, "Ada", "Realm"):match("^[^\n]+")
        )
    end
end

function tests.RefundAndLaterPurchaseDoNotDiscoverAgain(_self)
    local store, bags, purchase = fixture()
    bags(0)
    purchase()
    bags(1)
    WoWUnit.AreEqual(1, #store:takeDiscoveries())
    WoWUnit.IsTrue(
        store:command(
            "vendorAction",
            { kind = "refund", key = key, itemID = 4540, link = link, quantity = 1 },
            1003,
            { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
        )
    )
    bags(0)
    purchase()
    bags(1)
    WoWUnit.AreEqual(1, store:breakdown(key).gained)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
end

function tests.MutedDiscoveriesAreConsumedWithoutChangingTheLedger(_self)
    local store, bags, purchase = fixture()
    WoWUnit.IsTrue(store:setDisplay("toasts", false))
    bags(0)
    purchase()
    bags(1)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    WoWUnit.IsTrue(store:setDisplay("toasts", true))
    purchase()
    bags(2)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    WoWUnit.AreEqual(2, store:breakdown(key).gained)
end

function tests.OutsideMailDiscoversButAltMailDoesNot(_self)
    for _, peer in ipairs({ "Outside", "Ben" }) do
        local store, bags = fixture()
        bags(0)
        if peer == "Ben" then
            WoWUnit.IsTrue(store:scan({
                character = "Ben",
                realm = "Realm",
                area = "bags",
                seenAt = 1000,
                complete = true,
                items = {},
            }))
        end
        local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
        WoWUnit.IsTrue(store:command("exchangeIntent", {
            channel = "mail",
            direction = "in",
            key = key,
            itemID = 4540,
            link = link,
            quantity = 1,
            peerName = peer,
            peerRealm = "Realm",
        }, 1001, actor))
        WoWUnit.IsTrue(store:command("exchangeConfirm", { channel = "mail", direction = "in" }, 1001, actor))
        bags(1)
        WoWUnit.AreEqual(peer == "Outside" and 1 or 0, #store:takeDiscoveries())
        WoWUnit.AreEqual(peer == "Outside" and 1 or 0, store:breakdown(key).gained)
    end
end

function tests.VariantsDiscoverSeparatelyWhileEnchantsDoNot(_self)
    local store = fixture()
    local links = {
        "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h",
        "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h",
        "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h",
    }
    local function scan(at, items)
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            seenAt = at,
            complete = true,
            items = items,
        }))
    end
    scan(1000, {})
    local items = {}
    for index, itemLink in ipairs(links) do
        WoWUnit.IsTrue(
            store:command(
                "vendorAction",
                { kind = "purchase", key = addon.Item.key(itemLink, 100), itemID = 100, link = itemLink, quantity = 1 },
                1000 + index,
                { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
            )
        )
        items[#items + 1] = { itemID = 100, link = itemLink, quantity = 1 }
        scan(1000 + index, items)
        WoWUnit.AreEqual(index == 2 and 0 or 1, #store:takeDiscoveries())
    end
    WoWUnit.AreEqual(2, #store:list())
end

function tests.ItemLinksGroupByCanonicalVariantWithoutDroppingEnchants(_self)
    local links = {
        "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:2:111:222|h[Sword]|h",
        "|Hitem:100:0:0:0:0:0:42:9:70:0:0:0:2:222:111|h[Sword]|h",
        "|Hitem:100:88:0:0:0:0:42:1:60:0:0:0:2:111:222|h[Sword]|h",
    }
    WoWUnit.AreEqual(addon.Item.key(links[1], 100), addon.Item.key(links[2], 100))
    WoWUnit.AreEqual(2, #addon.Item.linkGroups(links))
end

function tests.UnsupportedAndDamagedDisplayDataStaySafe(_self)
    local writes = 0
    local store = addon.Schema.open({ schema = 999 }, function()
        writes = writes + 1
    end)
    WoWUnit.AreEqual(false, store:setDisplay("toasts", false))
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    WoWUnit.AreEqual(0, writes)
    store = addon.Schema.open(
        { schema = 2, records = {}, areas = {}, display = { tooltips = "false", toasts = false } },
        function() end
    )
    WoWUnit.AreEqual("damaged", store:diagnostic().kind)
    WoWUnit.AreEqual(true, store:display().tooltips)
    WoWUnit.IsTrue(store:setDisplay("toasts", false))
    WoWUnit.AreEqual(false, store:display().toasts)
end

function tests.TooltipUsesCommittedSeenAndObtainedFacts(_self)
    local store, bags, purchase = fixture()
    WoWUnit.AreEqual(nil, addon.Presentation.line(store, link, "Ada", "Realm"))
    bags(1)
    WoWUnit.AreEqual(
        "Azeroth Ledger: Seen • total gained 0 • status Present • source Unknown",
        addon.Presentation.line(store, link, "Ada", "Realm"):match("^[^\n]+")
    )
    purchase()
    bags(2)
    WoWUnit.AreEqual(
        "Azeroth Ledger: Seen, Obtained (Vendor) • total gained 1 • status Present • source Unknown",
        addon.Presentation.line(store, link, "Ada", "Realm"):match("^[^\n]+")
    )
    WoWUnit.IsTrue(addon.Presentation.line(store, link, "Ben", "Realm"):find("status Unknown", 1, true) ~= nil)
    WoWUnit.AreEqual(nil, addon.Presentation.line(store, "item:4540", "Ada", "Realm"))
end

function tests.FirstDiscoveryIsCommittedOnceAndNeverReplayed(_self)
    local store, bags, purchase, restore = fixture()
    bags(0)
    purchase()
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    bags(1)
    WoWUnit.AreEqual(key, store:takeDiscoveries()[1].key)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    bags(1)
    purchase()
    bags(2)
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    store = restore()
    WoWUnit.AreEqual(0, #store:takeDiscoveries())
    WoWUnit.AreEqual(2, store:breakdown(key).gained)
    local scanned, scanBags, buy = fixture()
    scanBags(1)
    buy()
    scanBags(2)
    WoWUnit.AreEqual(0, #scanned:takeDiscoveries())
end

function tests.DisplaySettingsPersistWithoutChangingFacts(_self)
    local store, bags, purchase, restore = fixture()
    bags(1)
    purchase()
    bags(2)
    WoWUnit.AreEqual(true, store:display().tooltips)
    WoWUnit.AreEqual(true, store:display().toasts)
    WoWUnit.IsTrue(store:setDisplay("tooltips", false))
    WoWUnit.IsTrue(store:setDisplay("toasts", false))
    WoWUnit.AreEqual(false, store:setDisplay("toasts", "false"))
    WoWUnit.AreEqual(false, store:setDisplay("missing", true))
    store = restore()
    WoWUnit.AreEqual(false, store:display().tooltips)
    WoWUnit.AreEqual(false, store:display().toasts)
    WoWUnit.AreEqual(1, store:breakdown(key).gained)
    WoWUnit.AreEqual(1, store:breakdown(key).initial)
    local display = store:display()
    display.toasts = true
    WoWUnit.AreEqual(false, store:display().toasts)
end

function tests.NativeCheckboxesReadAndWritePersistedControls(_self)
    local store, _, _, restore = fixture()
    local controls = {}
    local api = {
        Settings = {
            VarType = { Number = "number", Boolean = "boolean", String = "string" },
            CreateColorSwatch = function() end,
            RegisterVerticalLayoutSubcategory = function()
                return {}, { AddInitializer = function() end }
            end,
            RegisterVerticalLayoutCategory = function()
                return {}
            end,
            RegisterProxySetting = function(_, variable, kind, _, default, get, set)
                controls[variable] = { kind = kind, default = default, get = get, set = set }
                return variable
            end,
            CreateCheckbox = function(_, variable)
                WoWUnit.AreEqual("boolean", controls[variable].kind)
            end,
            CreateSliderOptions = function()
                return {}
            end,
            CreateSlider = function() end,
            RegisterAddOnCategory = function() end,
        },
    }
    WoWUnit.IsTrue(addon.Settings.register(api, store))
    local tooltips, toasts = controls.AzerothLedger_tooltips, controls.AzerothLedger_toasts
    WoWUnit.AreEqual(true, tooltips.get())
    tooltips.set(false)
    toasts.set(false)
    WoWUnit.AreEqual(false, tooltips.get())
    WoWUnit.AreEqual(false, restore():display().toasts)
end
