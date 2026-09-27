local _, addon = ...

local Vendor = {}

---@class AzerothLedgerVendorContainerApi
---@field GetContainerNumSlots? fun(bag: integer): integer?
---@field GetContainerItemInfo? fun(bag: integer, slot: integer): AzerothLedgerContainerItemInfo?

---@class AzerothLedgerMerchantApi
---@field GetMerchantItemLink? fun(index: integer): string?
---@field GetMerchantItemInfo? fun(index: integer): string?, any, number?, integer?
---@field GetBuybackItemLink? fun(index: integer): string?
---@field GetBuybackItemInfo? fun(index: integer): string?, any, number?, integer?
---@field GetNumBuybackItems? fun(): integer
---@field GetInventoryItemLink? fun(unit: string, slot: integer): string?
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

---@param api AzerothLedgerMerchantApi
---@param slot integer
---@return AzerothLedgerVendorIntent?
function Vendor.equipped(api, slot)
    local ok, result = pcall(function()
        if type(api.GetInventoryItemLink) ~= "function" then
            return nil
        end
        local action = item("refund", api.GetInventoryItemLink("player", slot), 1)
        if action then
            action.area = "equipped"
        end
        return action
    end)
    return ok and result or nil
end

---@param api AzerothLedgerMerchantApi
---@return table<string, AzerothLedgerVendorIntent>?
function Vendor.slots(api)
    local containers = api.C_Container
    if type(containers) ~= "table" or type(containers.GetContainerNumSlots) ~= "function" then
        return nil
    end
    local result = {}
    for bag = 0, 4 do
        local ok, count = pcall(containers.GetContainerNumSlots, bag)
        if not ok or type(count) ~= "number" or count < 0 or count > 100 or count ~= math.floor(count) then
            return nil
        end
        for slot = 1, count do
            local action = Vendor.container(api, "sale", bag, slot)
            if action then
                result[bag .. ":" .. slot] = action
            end
        end
    end
    return result
end

---@param api AzerothLedgerMerchantApi
---@return table<integer, AzerothLedgerVendorIntent>
function Vendor.equippedSlots(api)
    local result = {}
    for slot = 1, 19 do
        result[slot] = Vendor.equipped(api, slot)
    end
    return result
end

---@param api AzerothLedgerMerchantApi
---@return table<integer, AzerothLedgerVendorIntent>?
function Vendor.buybacks(api)
    if type(api.GetNumBuybackItems) ~= "function" then
        return nil
    end
    local ok, count = pcall(api.GetNumBuybackItems)
    if not ok or type(count) ~= "number" or count < 0 or count > 100 or count ~= math.floor(count) then
        return nil
    end
    local result = {}
    for index = 1, count do
        result[index] = Vendor.buyback(api, index)
    end
    return result
end

addon.Vendor = Vendor
