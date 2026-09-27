local _, addon = ...

local Vendor = {}

---@class AzerothLedgerVendorContainerApi
---@field GetContainerItemInfo? fun(bag: integer, slot: integer): AzerothLedgerContainerItemInfo?

---@class AzerothLedgerMerchantApi
---@field GetMerchantItemLink? fun(index: integer): string?
---@field GetMerchantItemInfo? fun(index: integer): string?, any, number?, integer?
---@field GetBuybackItemLink? fun(index: integer): string?
---@field GetBuybackItemInfo? fun(index: integer): string?, any, number?, integer?
---@field C_Container? AzerothLedgerVendorContainerApi

local function item(kind, link, quantity)
    local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
    local key = itemID and addon.Item.key(link, itemID)
    if not key or type(quantity) ~= "number" or quantity < 1 or quantity ~= math.floor(quantity) then
        return nil
    end
    return { kind = kind, key = key, itemID = itemID, link = link, quantity = quantity }
end

---@param api AzerothLedgerMerchantApi
---@param index integer
---@param count? integer
---@return AzerothLedgerVendorIntent?
function Vendor.purchase(api, index, count)
    local ok, result = pcall(function()
        if type(api.GetMerchantItemLink) ~= "function" or type(api.GetMerchantItemInfo) ~= "function" then
            return nil
        end
        local link = api.GetMerchantItemLink(index)
        local _, _, _, stack = api.GetMerchantItemInfo(index)
        return item("purchase", link, count or stack or 1)
    end)
    return ok and result or nil
end

---@param api AzerothLedgerMerchantApi
---@param index integer
---@return AzerothLedgerVendorIntent?
function Vendor.buyback(api, index)
    local ok, result = pcall(function()
        if type(api.GetBuybackItemLink) ~= "function" or type(api.GetBuybackItemInfo) ~= "function" then
            return nil
        end
        local link = api.GetBuybackItemLink(index)
        local _, _, _, quantity = api.GetBuybackItemInfo(index)
        return item("buyback", link, quantity)
    end)
    return ok and result or nil
end

---@param api AzerothLedgerMerchantApi
---@param kind 'sale'|'refund'
---@param bag integer
---@param slot integer
---@param isEquipped? boolean
---@return AzerothLedgerVendorIntent?
function Vendor.container(api, kind, bag, slot, isEquipped)
    local ok, result = pcall(function()
        if isEquipped then
            return nil
        end
        local containers = api.C_Container
        if type(containers) ~= "table" or type(containers.GetContainerItemInfo) ~= "function" then
            return nil
        end
        local info = containers.GetContainerItemInfo(bag, slot)
        if type(info) ~= "table" then
            return nil
        end
        return item(kind, info.hyperlink, info.stackCount)
    end)
    return ok and result or nil
end

addon.Vendor = Vendor
