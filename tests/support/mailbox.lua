local load = assert(loadfile("tests/support/addon.lua"))()
local fake = assert(loadfile("tests/support/client.lua"))()
-- A mailbox on the shared fake client, driven by the mail specs. Synthetic
-- production hooks/events; this does not certify native client behavior.
local link = "|Hitem:4540::::::::|h[Bread]|h"

-- switching leaves the client mid-load, before its first BAG_UPDATE_DELAYED.
local function mailbox(initial, switching)
    local addon = {}
    local client = fake.install()
    local state = { bags = initial or {}, messages = {}, clock = 1000, character = "Ada", outbox = {} }
    _G.AzerothLedgerDB = nil
    _G.GetServerTime = function()
        return state.clock
    end
    _G.UnitName = function()
        return state.character
    end
    _G.GetRealmName = function()
        return "Realm"
    end
    _G.UnitLevel = function()
        return 12
    end
    _G.GetRealZoneText = function()
        return "Elwynn Forest"
    end
    _G.GetInventoryItemLink = function() end
    _G.C_Timer = nil
    _G.C_Container = {
        GetContainerNumSlots = function(bag)
            return bag == 0 and #state.bags or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local entry = bag == 0 and state.bags[slot]
            if entry then
                return { itemID = entry.itemID or 4540, hyperlink = entry.link or link, stackCount = entry.quantity }
            end
        end,
    }
    _G.GetInboxNumItems = function()
        return #state.messages
    end
    _G.GetInboxHeaderInfo = function(index)
        local message = state.messages[index]
        local canReply = message.canReply
        if canReply == nil and not message.unknownReply then
            canReply = true
        end
        local count = 0
        for _ in pairs(message.items) do
            count = count + 1
        end
        return nil,
            message.stationery,
            message.sender,
            message.subject,
            0,
            0,
            30,
            count,
            false,
            message.returned,
            false,
            canReply
    end
    _G.GetInboxItemLink = function(index, slot)
        local entry = state.messages[index].items[slot]
        return not state.unreadable and entry and (entry.link or link) or nil
    end
    _G.GetInboxItem = function(index, slot)
        local entry = state.messages[index].items[slot]
        if entry then
            return "Bread", entry.itemID or 4540, nil, entry.quantity
        end
    end
    _G.GetInboxInvoiceInfo = function(index)
        return state.messages[index].invoice
    end
    _G.GetSendMailItem = function(slot)
        local entry = state.outbox[slot]
        if entry then
            return "Bread", entry.itemID or 4540, nil, entry.quantity
        end
    end
    _G.GetSendMailItemLink = function(slot)
        local entry = state.outbox[slot]
        return entry and (entry.link or link)
    end
    -- Native calls are asynchronous. The driver supplies the later inbox/bag changes.
    -- A relog loads a fresh UI, so it starts again from unhooked natives.
    local function natives()
        _G.TakeInboxItem = function(_index, _attachment) end
        _G.AutoLootMailItem = function(_index) end
        _G.TakeInboxMoney = function(_index) end
        _G.ReturnInboxItem = function(_index) end
        _G.DeleteInboxItem = function(_index) end
        _G.SendMail = function(_recipient) end
    end
    natives()
    _G.hooksecurefunc = function(target, method, callback)
        if type(target) == "string" then
            target, method, callback = _G, target, method
        end
        local original = target[method]
        target[method] = function(...)
            original(...)
            callback(...)
        end
    end
    _G.LOOT_ITEM_SELF = "You receive loot: %s."
    _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    -- Forever prints a mail take as an item handed over.
    _G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
    _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
    load.addon("Main", addon)
    function state:event(name, ...)
        if not self.sameSecond then
            self.clock = self.clock + 1
        end
        client.event(name, ...)
    end
    state:event("ADDON_LOADED", "AzerothLedger")
    state:event("PLAYER_LOGIN")
    if not switching then
        state:event("BAG_UPDATE_DELAYED")
    end
    -- Logging in as another character reloads the addon from its saved data.
    function state:relog(character)
        self.character = character
        natives()
        local relogged = {}
        load.addon("Main", relogged)
        self:event("ADDON_LOADED", "AzerothLedger")
        self:event("PLAYER_LOGIN")
        self:event("BAG_UPDATE_DELAYED")
        return relogged
    end
    return addon, state
end

return mailbox
