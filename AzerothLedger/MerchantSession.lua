local _, addon = ...
addon.Sessions = addon.Sessions or {}

-- Vendor purchases, sales, refunds, and buybacks while a merchant window is open.
-- Sales and refunds read the slot before the client empties it, so bag and
-- equipped slots are cached at each scan and taken once when the action fires.
local MerchantSession = {}

---@param runtime ALRuntime
function MerchantSession.new(runtime)
    local api = runtime.api
    local open = false
    local vendorName, bagSlots, equippedSlots, buybacks

    local function act(action)
        local context = runtime.player()
        if context then
            context.vendorName = vendorName or addon.Runtime.npcName(api)
        end
        if open and action and context and runtime.command("vendorAction", action, context) then
            runtime.refresh(context.character, context.realm)
        end
    end

    local function takeEquipped(slot)
        local cached = equippedSlots and equippedSlots[slot]
        if cached then
            equippedSlots[slot] = nil
        end
        return cached or addon.Vendor.equipped(api, slot)
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
        return addon.Vendor.container(api, kind, bag, slot, isEquipped)
    end

    local function takeBuyback(index)
        local cached = buybacks and buybacks[index]
        if cached then
            buybacks[index] = nil
        end
        return cached or addon.Vendor.buyback(api, index)
    end

    local function checkPossessions()
        runtime.inventory:check("bags")
        runtime.inventory:check("equipped")
    end

    local hook = addon.Events.hook
    hook(api, runtime.issues, "vendor", api, "BuyMerchantItem", function(index, count)
        act(addon.Vendor.purchase(api, index, count))
    end)
    hook(api, runtime.issues, "vendor", api, "PickupMerchantItem", function(index)
        act(addon.Vendor.purchase(api, index))
    end)
    hook(api, runtime.issues, "vendor", api, "BuybackItem", function(index)
        act(takeBuyback(index))
    end)
    if type(api.C_Container) == "table" then
        hook(api, runtime.issues, "vendor", api.C_Container, "UseContainerItem", function(bag, slot)
            if open then
                act(takeContainer("sale", bag, slot))
            end
        end)
        hook(
            api,
            runtime.issues,
            "vendor",
            api.C_Container,
            "ContainerRefundItemPurchase",
            function(bag, slot, isEquipped)
                act(takeContainer("refund", bag, slot, isEquipped))
            end
        )
    end

    local session = {}

    function session.isOpen()
        return open
    end

    -- Refreshes the slot cache from the same scan the store just accepted.
    ---@param snapshot AzerothLedgerSnapshot
    function session.snapshot(snapshot)
        if not open then
            return
        end
        if snapshot.area == "bags" then
            bagSlots = addon.Vendor.slots(api)
        elseif snapshot.area == "equipped" then
            equippedSlots = addon.Vendor.equippedSlots(api)
        end
    end

    session.events = {
        MERCHANT_SHOW = function()
            open = true
            vendorName = addon.Runtime.npcName(api)
            checkPossessions()
            buybacks = addon.Vendor.buybacks(api)
        end,
        MERCHANT_UPDATE = function()
            buybacks = addon.Vendor.buybacks(api)
        end,
        MERCHANT_CLOSED = function()
            checkPossessions()
            open = false
            vendorName, bagSlots, equippedSlots, buybacks = nil, nil, nil, nil
        end,
    }

    return session
end

addon.Sessions.Merchant = MerchantSession
