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

    local function proveSources(context, slots)
        if runtime.store():lootSourceProof(slots, context.at, context) then
            runtime.refresh(context.character, context.realm)
        end
    end

    local function opened()
        local context = runtime.player()
        local slots = addon.Loot.open(api)
        if not context or not slots then
            return
        end
        context.slots = slots
        if captured then
            proveSources(context, slots)
        elseif #slots > 0 then
            captured = runtime.store():lootOpen(context)
        end
    end

    local function receipt(message)
        local parsed = addon.Loot.receipt(api, message)
        local at = runtime.now()
        local character, realm = runtime.identity()
        if not parsed or not at or not character or not realm then
            return
        end
        local actor = { character = character, realm = realm }
        local store = runtime.store()
        local accepted
        if merchantOpen() then
            accepted = store:vendorReceipt(parsed, at, actor)
        else
            accepted = store:lootReceipt(parsed, at, actor)
        end
        if accepted then
            runtime.refresh(character, realm)
        end
    end

    return {
        events = {
            LOOT_READY = opened,
            LOOT_OPENED = opened,
            LOOT_SLOT_CHANGED = function()
                local context = runtime.player()
                local slots = addon.Loot.open(api)
                if context and slots then
                    proveSources(context, slots)
                end
            end,
            LOOT_CLOSED = function()
                captured = false
                local at = runtime.now()
                if at then
                    runtime.store():lootClose(at)
                end
            end,
            CHAT_MSG_LOOT = receipt,
        },
    }
end

addon.Sessions.Loot = LootSession
