local _, addon = ...

-- The vendor channel: purchases, sales, refunds, and buybacks while a merchant
-- window is open. Sales and refunds read the slot before the client empties it,
-- so bag and equipped slots are cached at each scan and taken once when the
-- action fires.
local Vendor = {}

---@class AzerothLedgerVendorContainerApi
---@field GetContainerNumSlots? fun(bag: integer): integer?
---@field GetContainerItemInfo? fun(bag: integer, slot: integer): AzerothLedgerContainerItemInfo?

---@class AzerothLedgerMerchantApi
---@field GetMerchantItemLink? fun(index: integer): string?
---@field C_MerchantFrame? { GetItemInfo?: fun(index: integer): { stackCount?: integer }? }
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
        local merchant = api.C_MerchantFrame
        if
            type(api.GetMerchantItemLink) ~= "function"
            or type(merchant) ~= "table"
            or type(merchant.GetItemInfo) ~= "function"
        then
            return nil
        end
        local link = api.GetMerchantItemLink(index)
        local info = merchant.GetItemInfo(index)
        local stack = type(info) == "table" and info.stackCount or nil
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
    for _, bag in ipairs(addon.Scan.containers(api, "bags")) do
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

-- The store commands this channel writes through.
---@type ALCommandName[]
Vendor.commands = { "vendorAction" }

---@class ALVendorDependencies
---@field api AzerothLedgerMerchantApi|table
---@field clock fun(): integer?
---@field issues string[]
---@field commands ALCommands Built from `Vendor.commands`
---@field check fun(area: string)
---@field refresh fun(character: string, realm: string)

---@param deps ALVendorDependencies
function Vendor.new(deps)
    local api, clock, issues, commands = deps.api, deps.clock, deps.issues, deps.commands
    local check, refresh = deps.check, deps.refresh
    local Runtime = addon.Runtime
    local open = false
    local vendorName, bagSlots, equippedSlots, buybacks

    local function act(action)
        local context = Runtime.player(api, clock)
        if context then
            context.vendorName = vendorName or Runtime.npcName(api)
        end
        if open and action and context and commands.vendorAction(action, context) then
            refresh(context.character, context.realm)
        end
    end

    local function takeEquipped(slot)
        local cached = equippedSlots and equippedSlots[slot]
        if cached then
            equippedSlots[slot] = nil
        end
        return cached or Vendor.equipped(api, slot)
    end

    local function takeContainer(kind, bag, slot, isEquipped)
        if isEquipped then
            return takeEquipped(slot)
        end
        local slotKey = tostring(bag) .. ":" .. tostring(slot)
        local cached = bagSlots and bagSlots[slotKey]
        if cached then
            bagSlots[slotKey] = nil
            cached.kind = kind
            return cached
        end
        return Vendor.container(api, kind, bag, slot, isEquipped)
    end

    local function takeBuyback(index)
        local cached = buybacks and buybacks[index]
        if cached then
            buybacks[index] = nil
        end
        return cached or Vendor.buyback(api, index)
    end

    local function checkPossessions()
        check("bags")
        check("equipped")
    end

    local hook = addon.Events.hook
    hook(api, issues, "vendor", api, "BuyMerchantItem", function(index, count)
        act(Vendor.purchase(api, index, count))
    end)
    hook(api, issues, "vendor", api, "PickupMerchantItem", function(index)
        act(Vendor.purchase(api, index))
    end)
    hook(api, issues, "vendor", api, "BuybackItem", function(index)
        act(takeBuyback(index))
    end)
    if type(api.C_Container) == "table" then
        hook(api, issues, "vendor", api.C_Container, "UseContainerItem", function(bag, slot)
            if open then
                act(takeContainer("sale", bag, slot))
            end
        end)
        hook(api, issues, "vendor", api.C_Container, "ContainerRefundItemPurchase", function(bag, slot, isEquipped)
            act(takeContainer("refund", bag, slot, isEquipped))
        end)
    end

    local channel = {}

    function channel.isOpen()
        return open
    end

    -- Refreshes the slot cache from the same scan the store just accepted.
    ---@param snapshot AzerothLedgerSnapshot
    function channel.snapshot(snapshot)
        if not open then
            return
        end
        if snapshot.area == "bags" then
            bagSlots = Vendor.slots(api)
        elseif snapshot.area == "equipped" then
            equippedSlots = Vendor.equippedSlots(api)
        end
    end

    channel.events = {
        MERCHANT_SHOW = function()
            open = true
            vendorName = Runtime.npcName(api)
            checkPossessions()
            buybacks = Vendor.buybacks(api)
        end,
        MERCHANT_UPDATE = function()
            buybacks = Vendor.buybacks(api)
        end,
        MERCHANT_CLOSED = function()
            checkPossessions()
            open = false
            vendorName, bagSlots, equippedSlots, buybacks = nil, nil, nil, nil
        end,
    }

    return channel
end

addon.Vendor = Vendor
