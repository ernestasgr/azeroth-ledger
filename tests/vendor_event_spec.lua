local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
local addon = {}
local bread = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local clock = 1000
local bagQuantity = 0
-- A merchant won't buy the wand: the client reports it with no value.
local wand = "|Hitem:20409::::::::|h[Hallowed Wand - Ghost]|h"
local wandInBags = false
local buybackQuantity = 0
date = os.date

GetServerTime = function()
    return clock
end
UnitName = function(unit)
    return unit == "npc" and "Dermot Johns" or "Ada"
end
GetRealmName = function()
    return "Realm"
end
UnitLevel = function()
    return 12
end
GetRealZoneText = function()
    return "Elwynn Forest"
end
GetInventoryItemLink = function()
    return nil
end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
-- The client prints a purchase as an item handed over, not as loot.
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."

C_Container = {
    GetContainerNumSlots = function(bag)
        return (bag == 0 or bag == 1 and wandInBags) and 1 or 0
    end,
    GetContainerItemInfo = function(bag)
        if bag == 1 and wandInBags then
            return { itemID = 20409, hyperlink = wand, stackCount = 1, hasNoValue = true }
        end
        return bag == 0 and bagQuantity > 0 and { itemID = 4540, hyperlink = bread, stackCount = bagQuantity } or nil
    end,
    UseContainerItem = function(bag, _slot)
        if bag == 1 then
            return
        end
        bagQuantity = 0
        buybackQuantity = 1
    end,
    ContainerRefundItemPurchase = function(bag, _slot)
        if bag == 1 then
            wandInBags = false
            return
        end
        bagQuantity = 0
    end,
}
GetMerchantItemLink = function()
    return bread
end
C_MerchantFrame = {
    GetItemInfo = function()
        return { name = "Bread", price = 10, stackCount = 1 }
    end,
}
GetNumBuybackItems = function()
    return buybackQuantity
end
GetBuybackItemLink = function()
    return buybackQuantity > 0 and bread or nil
end
GetBuybackItemInfo = function()
    return "Bread", nil, 10, buybackQuantity
end
BuyMerchantItem = function(_index)
    bagQuantity = bagQuantity + 1
end
PickupMerchantItem = function(_index)
    bagQuantity = bagQuantity + 1
end
BuybackItem = function(_index)
    buybackQuantity = 0
    bagQuantity = bagQuantity + 1
end
hooksecurefunc = function(target, method, callback)
    local original = target[method]
    target[method] = function(...)
        original(...)
        callback(...)
    end
end

load.addon("Main", addon)

local function event(name, ...)
    clock = clock + 1
    client.event(name, ...)
end

local key = addon.Item.key(bread, 4540)
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")
event("MERCHANT_SHOW")
PickupMerchantItem(1)
assert(#AzerothLedgerDB.vendor.actions == 1, "merchant pickup must record item-specific action")
event("BAG_UPDATE_DELAYED")
assert(addon.store:find(key).totalGained == 1, "merchant purchase without loot chat must count")
local purchaseDetails = addon.Collection.inspect(addon.store, key, "Ada", "Realm")
assert(purchaseDetails.breakdown.sources["Vendor: Dermot Johns"] == 1, "vendor name must be a source")
local purchase = addon.Journal.query(addon.store)[1]
assert(purchase.action == "Purchase", "the Journal must show the purchase")
assert(purchase.details[1].source == "Dermot Johns", "purchase detail must name the vendor")

C_Container.ContainerRefundItemPurchase(0, 1)
event("BAG_UPDATE_DELAYED")
assert(addon.store:find(key).totalGained == 0)
assert(addon.store:vendorActivity()[1].kind == "refund")

BuyMerchantItem(1)
event("CHAT_MSG_LOOT", "You receive item: " .. bread .. ".")
event("BAG_UPDATE_DELAYED")
C_Container.UseContainerItem(0, 1)
event("BAG_UPDATE_DELAYED")
event("MERCHANT_UPDATE")
assert(addon.store:find(key).totalGained == 1)
BuybackItem(1)
event("BAG_UPDATE_DELAYED")
assert(addon.store:find(key).totalGained == 1)
assert(#addon.store:vendorActivity() == 3)

BuyMerchantItem(1)
event("BAG_UPDATE_DELAYED")
assert(addon.store:find(key).totalGained == 2, "direct purchase without loot chat must count")

assert(
    addon.store:command(
        "lootOpen",
        { slots = { { key = key, quantity = 1 } } },
        clock,
        { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest" }
    )
)
bagQuantity = 3
event("CHAT_MSG_LOOT", "You receive item: " .. bread .. ".")
event("BAG_UPDATE_DELAYED")
assert(addon.store:find(key).totalGained == 2)

-- Two stacks of one item sold before the bags update are both sales.
bagQuantity = 7
event("BAG_UPDATE_DELAYED")
local actor = { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest", vendorName = "Dermot Johns" }
local sold = #addon.store:vendorActivity()
for _, quantity in ipairs({ 5, 2 }) do
    assert(addon.store:command("vendorAction", {
        kind = "sale",
        key = key,
        itemID = 4540,
        link = bread,
        quantity = quantity,
    }, clock, actor))
end
bagQuantity = 0
event("BAG_UPDATE_DELAYED")
local sales = 0
for index = sold + 1, #addon.store:vendorActivity() do
    sales = sales + addon.store:vendorActivity()[index].quantity
end
assert(sales == 7, "two sales of one item were not both confirmed")
assert(#addon.store:vendorUnresolved() == 0, "a repeated sale was left to review")

-- Using an item the merchant won't buy leaves the bags as they were.
wandInBags = true
event("BAG_UPDATE_DELAYED")
local actionsBefore = #AzerothLedgerDB.vendor.actions
local entriesBefore = #addon.Journal.query(addon.store)
C_Container.UseContainerItem(1, 1)
C_Container.UseContainerItem(1, 1)
event("BAG_UPDATE_DELAYED")
assert(#AzerothLedgerDB.vendor.actions == actionsBefore, "an item with no value was recorded as a sale")
assert(#addon.Journal.query(addon.store) == entriesBefore, "an item with no value got a Journal entry")
assert(#addon.store:vendorUnresolved() == 0, "an item with no value was left to review")
local wandKey = addon.Item.key(wand, 20409)
assert(addon.store:find(wandKey).totalGained == 0, "an unsold wand must not change its count")

-- An item with no value can still be refunded.
C_Container.ContainerRefundItemPurchase(1, 1)
assert(#AzerothLedgerDB.vendor.actions == actionsBefore + 1, "a refund of an item with no value must be recorded")
assert(AzerothLedgerDB.vendor.actions[actionsBefore + 1].kind == "refund")
assert(AzerothLedgerDB.vendor.actions[actionsBefore + 1].noValue == nil, "noValue must not be stored")

print("vendor_event_spec: passed")
