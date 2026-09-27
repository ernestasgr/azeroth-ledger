local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerVendor")

local bread = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local key = addon.Item.key(bread, 4540)

function tests.MerchantAdapterKeepsExactItemAndUnitCount(_self)
    local api = {
        GetMerchantItemLink = function()
            return bread
        end,
        GetMerchantItemInfo = function()
            return "Bread", nil, 10, 5
        end,
        GetBuybackItemLink = function()
            return bread
        end,
        GetBuybackItemInfo = function()
            return "Bread", nil, 10, 3
        end,
        GetNumBuybackItems = function()
            return 1
        end,
        GetInventoryItemLink = function()
            return bread
        end,
        C_Container = {
            GetContainerNumSlots = function(bag)
                return bag == 0 and 1 or 0
            end,
            GetContainerItemInfo = function()
                return { hyperlink = bread, stackCount = 2 }
            end,
            GetContainerItemPurchaseInfo = function()
                return { itemCount = 2 }
            end,
        },
    }
    WoWUnit.AreEqual(5, addon.Vendor.purchase(api, 1).quantity)
    WoWUnit.AreEqual(7, addon.Vendor.purchase(api, 1, 7).quantity)
    WoWUnit.AreEqual(key, addon.Vendor.purchase(api, 1).key)
    WoWUnit.AreEqual(3, addon.Vendor.buyback(api, 1).quantity)
    WoWUnit.AreEqual(2, addon.Vendor.container(api, "sale", 0, 1).quantity)
    WoWUnit.AreEqual(2, addon.Vendor.container(api, "refund", 0, 1).quantity)
    WoWUnit.AreEqual("equipped", addon.Vendor.equipped(api, 7).area)
    WoWUnit.AreEqual(key, addon.Vendor.equippedSlots(api)[7].key)
    local slots = addon.Vendor.slots(api)
    local buybacks = addon.Vendor.buybacks(api)
    api.C_Container.GetContainerItemInfo = function()
        return nil
    end
    api.GetBuybackItemLink = function()
        return nil
    end
    WoWUnit.AreEqual(nil, addon.Vendor.container(api, "sale", 0, 1))
    WoWUnit.AreEqual(key, slots["0:1"].key)
    WoWUnit.AreEqual(key, buybacks[1].key)
end

local function replay()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local units = 0
    local at = 1000
    local function bags(quantity)
        units = quantity
        local items = units > 0 and { { itemID = 4540, link = bread, quantity = units } } or {}
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            seenAt = at,
            complete = true,
            items = items,
        }))
        at = at + 1
    end
    local function action(kind, quantity)
        local result = store:vendorAction({
            kind = kind,
            key = key,
            itemID = 4540,
            link = bread,
            quantity = quantity,
        }, at, { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest" })
        at = at + 1
        return result
    end
    local function receipt(quantity)
        local result = store:vendorReceipt(
            { key = key, quantity = quantity },
            at,
            { character = "Ada", realm = "Realm" }
        )
        at = at + 1
        return result
    end
    return store,
        bags,
        action,
        receipt,
        function()
            store = addon.Schema.open(saved, function(value)
                saved = value
            end)
            return store
        end
end

function tests.SaleThenPurchaseNeedsReceiptAndIncrease(_self)
    local store, bags, action, receipt, restore = replay()
    bags(2)
    WoWUnit.IsTrue(action("sale", 2))
    bags(0)
    WoWUnit.IsTrue(action("purchase", 5))
    bags(0)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.IsTrue(receipt(5))
    bags(5)
    store = restore()
    local record = store:find(key)
    WoWUnit.AreEqual(5, record.totalGained)
    WoWUnit.AreEqual("Vendor", record.gains[1].method)
    WoWUnit.AreEqual(1, #record.gains)
    local lines = table.concat(addon.Collection.lines(store, "Ada", "Realm"), "\n")
    WoWUnit.IsTrue(lines:find("Method total: Vendor 5", 1, true) ~= nil)
    WoWUnit.IsTrue(lines:find("Source total: Vendor 5", 1, true) ~= nil)
    WoWUnit.IsTrue(lines:find("+5 Vendor", 1, true) ~= nil)
    WoWUnit.IsTrue(lines:find("Sale x2", 1, true) ~= nil)
    WoWUnit.AreEqual(1, #store:vendorActivity())
end

function tests.PurchaseRefundAndDuplicateReversal(_self)
    local store, bags, action, receipt, restore = replay()
    bags(0)
    WoWUnit.IsTrue(action("purchase", 3))
    WoWUnit.IsTrue(receipt(3))
    bags(3)
    WoWUnit.IsTrue(action("refund", 3))
    bags(0)
    store = restore()
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.AreEqual(3, store:find(key).gains[1].refunded)
    WoWUnit.IsTrue(action("refund", 3))
    bags(0)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.IsTrue(#store:vendorUnresolved() > 0)
    local lines = table.concat(addon.Collection.lines(store, "Ada", "Realm"), "\n")
    WoWUnit.IsTrue(lines:find("Refund x3", 1, true) ~= nil)
    WoWUnit.IsTrue(lines:find("Method total: Vendor 3", 1, true) == nil)
    WoWUnit.IsTrue(lines:find("Source total: Vendor 3", 1, true) == nil)
end

function tests.SaleBuybackAndIndependentPurchase(_self)
    local store, bags, action, receipt = replay()
    bags(0)
    WoWUnit.IsTrue(action("purchase", 1))
    WoWUnit.IsTrue(receipt(1))
    bags(1)
    WoWUnit.IsTrue(action("sale", 1))
    bags(0)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    WoWUnit.IsTrue(store:pruneJournal(0))
    WoWUnit.IsTrue(action("buyback", 1))
    bags(1)
    WoWUnit.AreEqual(1, store:find(key).totalGained)
    WoWUnit.IsTrue(action("purchase", 1))
    WoWUnit.IsTrue(receipt(1))
    bags(2)
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    local lines = table.concat(addon.Collection.lines(store, "Ada", "Realm"), "\n")
    WoWUnit.IsTrue(lines:find("Buyback x1", 1, true) ~= nil)
end

function tests.ReceiptAfterBagUpdateCountsOnce(_self)
    local store, bags, action, receipt = replay()
    bags(0)
    WoWUnit.IsTrue(action("purchase", 2))
    bags(2)
    WoWUnit.AreEqual(0, store:find(key).totalGained)
    WoWUnit.IsTrue(receipt(2))
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    WoWUnit.IsTrue(not receipt(2))
    WoWUnit.AreEqual(2, store:find(key).totalGained)
end

function tests.EquippedRefundDebitsItsPurchase(_self)
    local gear = "|Hitem:263409::::::::|h[Gardening Pants]|h"
    local gearKey = addon.Item.key(gear, 263409)
    local store = addon.Schema.open(nil, function() end)
    local at = 2000
    local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest" }
    local function scan(area, quantity)
        local items = quantity > 0 and { { itemID = 263409, link = gear, quantity = quantity } } or {}
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = area,
            seenAt = at,
            complete = true,
            items = items,
        }))
        at = at + 1
    end
    scan("bags", 0)
    scan("equipped", 0)
    WoWUnit.IsTrue(
        store:vendorAction({ kind = "purchase", key = gearKey, itemID = 263409, link = gear, quantity = 1 }, at, actor)
    )
    at = at + 1
    WoWUnit.IsTrue(store:vendorReceipt({ key = gearKey, quantity = 1 }, at, actor))
    at = at + 1
    scan("bags", 1)
    scan("bags", 0)
    scan("equipped", 1)
    WoWUnit.IsTrue(
        store:vendorAction(
            { kind = "refund", key = gearKey, itemID = 263409, link = gear, quantity = 1, area = "equipped" },
            at,
            actor
        )
    )
    at = at + 1
    scan("equipped", 0)
    WoWUnit.AreEqual(0, store:find(gearKey).totalGained)
    WoWUnit.AreEqual("refund", store:vendorActivity()[1].kind)
end

function tests.FailedPurchaseAmbiguousRefundAndPrunedJournal(_self)
    local store, bags, action, receipt, restore = replay()
    bags(0)
    WoWUnit.IsTrue(action("purchase", 1))
    WoWUnit.IsTrue(receipt(1))
    bags(0)
    WoWUnit.AreEqual(nil, store:find(key))
    WoWUnit.IsTrue(#store:vendorUnresolved() > 0)
    WoWUnit.IsTrue(action("purchase", 1))
    WoWUnit.IsTrue(receipt(1))
    bags(1)
    WoWUnit.IsTrue(action("purchase", 1))
    WoWUnit.IsTrue(receipt(1))
    bags(2)
    WoWUnit.IsTrue(action("refund", 1))
    bags(1)
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    WoWUnit.IsTrue(#store:vendorUnresolved() > 0)
    WoWUnit.IsTrue(action("sale", 1))
    bags(0)
    WoWUnit.AreEqual(1, #store:vendorActivity())
    WoWUnit.IsTrue(store:pruneJournal(0))
    store = restore()
    WoWUnit.AreEqual(2, store:find(key).totalGained)
    WoWUnit.AreEqual(0, #store:vendorActivity())
end
