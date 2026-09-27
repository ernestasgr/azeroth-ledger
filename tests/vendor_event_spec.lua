local addon = {}
local bread = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local frame = { registered = {} }
local clock = 1000
local bagQuantity = 0
local buybackQuantity = 0
date = os.date

function frame:RegisterEvent(event)
    self.registered[event] = true
end

function frame:SetScript(name, handler)
    if name == "OnEvent" then
        self.onEvent = handler
    end
end

CreateFrame = function()
    return frame
end
GetBuildInfo = function()
    return "1.60.1", 70009, "date", 16001
end
GetLocale = function()
    return "enUS"
end
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
LOOT_ITEM_SELF = "You receive item: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive item: %sx%d."
SlashCmdList = {}

C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and 1 or 0
    end,
    GetContainerItemInfo = function(bag)
        return bag == 0 and bagQuantity > 0 and { itemID = 4540, hyperlink = bread, stackCount = bagQuantity } or nil
    end,
    UseContainerItem = function(_bag, _slot)
        bagQuantity = 0
        buybackQuantity = 1
    end,
    ContainerRefundItemPurchase = function(_bag, _slot)
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

for _, source in ipairs({ "Item", "Schema", "Client", "Scan", "Loot", "Reward", "Vendor", "Collection", "Main" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end

local function event(name, ...)
    assert(frame.registered[name])
    clock = clock + 1
    frame.onEvent(frame, name, ...)
end

local key = addon.Item.key(bread, 4540)
event("PLAYER_LOGIN")
event("MERCHANT_SHOW")
PickupMerchantItem(1)
assert(#AzerothLedgerDB.vendor.actions == 1, "merchant pickup must record item-specific action")
event("BAG_UPDATE_DELAYED")
assert(addon.store:find(key).totalGained == 1, "merchant purchase without loot chat must count")
local purchaseLines = table.concat(addon.Collection.lines(addon.store, "Ada", "Realm"), "\n")
assert(purchaseLines:find("Source total: Dermot Johns 1", 1, true), "vendor name must be a source")
assert(purchaseLines:find("vendor Dermot Johns", 1, true), "purchase detail must name the vendor")

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

assert(addon.store:lootOpen({
    character = "Ada",
    realm = "Realm",
    level = 12,
    place = "Elwynn Forest",
    at = clock,
    slots = { { key = key, quantity = 1 } },
}))
bagQuantity = 3
event("CHAT_MSG_LOOT", "You receive item: " .. bread .. ".")
event("BAG_UPDATE_DELAYED")
assert(addon.store:find(key).totalGained == 2)

print("vendor_event_spec: passed")
