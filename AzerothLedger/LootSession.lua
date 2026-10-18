local _, addon = ...
addon.Sessions = addon.Sessions or {}

-- The loot window and loot chat receipts. A receipt while a merchant window is
-- open is a vendor purchase, not loot.
local LootSession = {}

---@param runtime ALRuntime
---@param merchantOpen fun(): boolean
function LootSession.new(runtime, merchantOpen)
    local api = runtime.api
    -- Fast loot can finish at LOOT_READY; LOOT_OPENED must keep that pre-gain baseline.
    local captured = false

    local function proveSources(slots)
        local proven, context = runtime.command("lootSourceProof", { slots = slots })
        if proven and context then
            runtime.refresh(context.character, context.realm)
        end
    end

    local function opened()
        local slots = addon.Loot.open(api)
        if not slots then
            return
        end
        if captured then
            proveSources(slots)
        elseif #slots > 0 then
            captured = runtime.command("lootOpen", { slots = slots }) == true
        end
    end

    local function receipt(message)
        local parsed = addon.Loot.receipt(api, message)
        if not parsed then
            return
        end
        local accepted, context = runtime.command(merchantOpen() and "vendorReceipt" or "lootReceipt", parsed)
        if accepted and context then
            runtime.refresh(context.character, context.realm)
        end
    end

    return {
        events = {
            LOOT_READY = opened,
            LOOT_OPENED = opened,
            LOOT_SLOT_CHANGED = function()
                local slots = addon.Loot.open(api)
                if slots then
                    proveSources(slots)
                end
            end,
            LOOT_CLOSED = function()
                captured = false
                runtime.command("lootClose")
            end,
            CHAT_MSG_LOOT = receipt,
        },
    }
end

addon.Sessions.Loot = LootSession
