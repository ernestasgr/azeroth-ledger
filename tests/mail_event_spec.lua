-- Synthetic production hooks/events; this does not certify native client behavior.
local link = "|Hitem:4540::::::::|h[Bread]|h"

local function mailbox(initial)
    local addon = {}
    local frame = { registered = {} }
    local state = { bags = initial or {}, messages = {}, clock = 1000, character = "Ada", outbox = {} }
    function frame:RegisterEvent(name)
        self.registered[name] = true
    end
    function frame:SetScript(name, callback)
        self[name] = callback
    end
    _G.AzerothLedgerDB = nil
    _G.CreateFrame = function()
        return frame
    end
    _G.GetBuildInfo = function()
        return "1.60.1", 70009, "fixture", 16001
    end
    _G.GetLocale = function()
        return "enUS"
    end
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
    _G.TakeInboxItem = function(_index, _attachment) end
    _G.AutoLootMailItem = function(_index) end
    _G.TakeInboxMoney = function(_index) end
    _G.ReturnInboxItem = function(_index) end
    _G.DeleteInboxItem = function(_index) end
    _G.SendMail = function(_recipient) end
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
    _G.SlashCmdList = {}
    _G.LOOT_ITEM_SELF = "You receive item: %s."
    _G.LOOT_ITEM_SELF_MULTIPLE = "You receive item: %sx%d."
    for _, source in ipairs({
        "Item",
        "Work",
        "Trace",
        "SchemaValidate",
        "StoreKernel",
        "StorePreferences",
        "StoreJournal",
        "StoreEvidence",
        "StoreRecords",
        "StoreLoot",
        "StoreExchange",
        "StoreVendor",
        "StoreReward",
        "StoreScan",
        "Schema",
        "Client",
        "Scan",
        "Inventory",
        "Loot",
        "Reward",
        "Vendor",
        "Exchange",
        "LastSeen",
        "Collection",
        "Journal",
        "Events",
        "Runtime",
        "MerchantSession",
        "MailSession",
        "TradeSession",
        "LootSession",
        "QuestSession",
        "CraftSession",
        "Diagnostics",
        "Commands",
        "MinimapButton",
        "Main",
    }) do
        assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
    end
    function state:event(name, ...)
        assert(frame.registered[name], name)
        if not self.sameSecond then
            self.clock = self.clock + 1
        end
        frame.OnEvent(frame, name, ...)
    end
    state:event("ADDON_LOADED", "AzerothLedger")
    state:event("PLAYER_LOGIN")
    return addon, state
end

local addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages[1].items = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("CHAT_MSG_LOOT", "You receive item: " .. link .. ".")
state:event("BAG_UPDATE_DELAYED")
local record = addon.store:find("4540:0")
assert(record.totalGained == 1, "modified-click retrieval must gain one unit, not initial Seen stock")
assert(record.firstSeenUnits == 0 and #addon.Journal.query(addon.store) == 1)

addon, state = mailbox({ { quantity = 1 } })
state:event("MAIL_SHOW")
state.outbox = { { quantity = 1 } }
state:event("MAIL_SEND_INFO_UPDATE")
_G.SendMail("Cara-Realm")
state.bags = {}
state:event("MAIL_SEND_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state.messages = { { sender = "Cara-Realm", returned = true, items = { { quantity = 1 } } } }
state:event("MAIL_INBOX_UPDATE")
_G.TakeInboxItem(1, 1)
state.messages[1].items = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("CHAT_MSG_LOOT", "You receive item: " .. link .. ".")
state:event("BAG_UPDATE_DELAYED")
record = addon.store:find("4540:0")
assert(record.totalGained == 0, "returned starting stock must not become an external gain")
assert(record.firstSeenUnits == 1 and addon.store:breakdown(record.key).recorded == 1)
assert(#addon.Journal.query(addon.store) == 0 and not record.evidencedDiscovery)

-- Auction purchases need a buyer invoice; a non-replyable system sender is not a player source.
addon, state = mailbox()
state.messages = { { sender = "Auction House", canReply = false, invoice = "buyer", items = { { quantity = 2 } } } }
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state.messages[1].items = {}
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state:event("BAG_UPDATE_DELAYED")
record = addon.store:find("4540:0")
assert(record.totalGained == 2 and not record.gains[1].source)
assert(addon.Journal.query(addon.store)[1].action == "Auction purchase", "buyer invoice must remain identifiable")
local restored = addon.Schema.open(AzerothLedgerDB, function() end)
assert(restored:diagnostic().kind == "healthy")
assert(addon.Journal.query(restored)[1].action == "Auction purchase")

-- Duplicate success/chat/bag signals cannot re-credit an individual take.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 3 } } } }
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state.messages[1].items = {}
state.bags = { { quantity = 3 } }
state:event("MAIL_INBOX_UPDATE") -- inbox change before success
state:event("BAG_UPDATE_DELAYED") -- possessions before success
assert(addon.store:find("4540:0").totalGained == 0)
state:event("MAIL_SUCCESS")
state:event("MAIL_SUCCESS")
state:event("CHAT_MSG_LOOT", "You receive item: " .. link .. "x3.")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 3)
assert(#addon.Journal.query(addon.store) == 1)

-- An autoloot action can finish several attachments in successive inbox updates.
local variant = "|Hitem:15222::::::1647:::|h[Barbed Club of the Bear]|h"
addon, state = mailbox()
state.messages = {
    {
        sender = "Cara-Realm",
        items = {
            { quantity = 1 },
            { quantity = 1, link = variant, itemID = 15222 },
        },
    },
}
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages[1].items[1] = nil
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
assert(addon.store:find("4540:0").totalGained == 1)
state.messages[1].items[2] = nil
state.bags[2] = { quantity = 1, link = variant, itemID = 15222 }
state:event("MAIL_INBOX_UPDATE")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find(addon.Item.key(variant, 15222)).totalGained == 1)
assert(#addon.Journal.query(addon.store) == 2)

-- A partial autoloot of equal stacks cannot identify which attachment disappeared.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 }, { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages[1].items[1] = nil
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
state.clock = state.clock + 60
state:event("BAG_UPDATE_DELAYED")
assert(#addon.store:evidenceSummary().unresolved >= 2)

-- Unequal stacks can prove a unique partial retrieval, leaving the remainder unresolved.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 }, { quantity = 2 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages[1].items[1] = nil
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 1)
_G.TakeInboxItem(1, 2) -- retry the remaining attachment after the completed bag update
state.messages[1].items = {}
state.bags = { { quantity = 3 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 3)

-- Simultaneous takes have no action-specific success identity, even for the same item.
addon, state = mailbox()
state.messages = {
    { sender = "Cara-Realm", items = { { quantity = 1 } } },
    { sender = "Dana-Realm", items = { { quantity = 1 } } },
}
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
_G.TakeInboxItem(2, 1)
state.messages = {}
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
assert(#addon.store:exchangeUnresolved() == 2)

-- Success without inbox removal, including unrelated money operations, is insufficient.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
_G.TakeInboxMoney(1)
state.messages = {}
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0 and #addon.store:exchangeUnresolved() == 1)

-- Removing an earlier message shifts indexes but cannot change the captured variant/quantity.
addon, state = mailbox()
state.messages = {
    { sender = "Cara-Realm", items = { { quantity = 2 } } },
    { sender = "Dana-Realm", items = { { quantity = 1 } } },
}
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
table.remove(state.messages, 1)
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 2)
assert(addon.store:find("4540:0").gains[1].source.name == "Cara")

-- Returned items without a uniquely measured send, and expired/canceled auction mail, stay unresolved.
for _, message in ipairs({
    { sender = "Cara-Realm", returned = true },
    { sender = "Auction House", canReply = false, subject = "Auction expired: Bread" },
    { sender = "Auction House", canReply = false, subject = "Auction canceled: Bread" },
    { sender = "Auction House", canReply = false, invoice = "seller" },
    { sender = "Auction House", unknownReply = true },
}) do
    addon, state = mailbox()
    message.items = { { quantity = 1 } }
    state.messages = { message }
    state:event("MAIL_SHOW")
    _G.AutoLootMailItem(1)
    state.messages = {}
    state.bags = { { quantity = 1 } }
    state:event("MAIL_SUCCESS")
    state:event("BAG_UPDATE_DELAYED")
    record = addon.store:find("4540:0")
    assert(record.totalGained == 0 and not record.evidencedDiscovery)
    assert(#addon.Journal.query(addon.store) == 0 and #addon.store:exchangeUnresolved() == 1)
    assert(addon.Schema.open(AzerothLedgerDB, function() end):diagnostic().kind == "healthy")
end

-- A proven alt send remains a transfer through the native modified-click path.
addon, state = mailbox({ { quantity = 2 } })
state:event("MAIL_SHOW")
state.outbox = { { quantity = 2 } }
state:event("MAIL_SEND_INFO_UPDATE")
_G.SendMail("Ben-Realm")
state.bags = {}
state:event("MAIL_SEND_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state:event("MAIL_CLOSED")
state.character = "Ben"
state:event("PLAYER_LOGIN")
state.messages = { { sender = "Ada-Realm", items = { { quantity = 2 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
assert(#addon.store:exchangeActivity() == 1 and addon.store:exchangeActivity()[1].quantity == 2)

-- Forever shows surnames and omits the local realm: "Ada Quietfield" is still Ada on this realm.
addon, state = mailbox({ { quantity = 2 } })
state:event("MAIL_SHOW")
state.outbox = { { quantity = 2 } }
state:event("MAIL_SEND_INFO_UPDATE")
_G.SendMail("Ben Truehammer")
state.bags = {}
state:event("MAIL_SEND_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state:event("MAIL_CLOSED")
state.character = "Ben"
state:event("PLAYER_LOGIN")
state.messages = { { sender = "Ada Quietfield", items = { { quantity = 2 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0, "surnamed alt mail must be a transfer")
assert(#addon.store:exchangeActivity() == 1 and addon.store:exchangeActivity()[1].sender == "Ada")

-- A same-realm sender has no realm suffix but is still a named player source.
addon, state = mailbox()
state.messages = { { sender = "Cara Ironfoot", items = { { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
record = addon.store:find("4540:0")
assert(record.totalGained == 1 and record.gains[1].source, "same-realm mail must keep its sender")
assert(record.gains[1].source.name == "Cara" and record.gains[1].source.realm == "Realm")

-- A failed take ends its intent; a later successful retry can capture fresh proof.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state:event("MAIL_FAILED")
_G.TakeInboxItem(1, 1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 1)
assert(#addon.store:exchangeUnresolved() == 1)

-- Complete retrieval of equal stacks has one unique proof: both attachments disappeared.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 }, { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 2)
assert(addon.store:find("4540:0").firstSeenUnits == 0)

-- Unreadable surviving attachments cannot serve as proof that the selected one disappeared.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 }, { quantity = 2 } } } }
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state.messages[1].items[1] = nil
state.unreadable = true
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
state.unreadable = false
state:event("MAIL_INBOX_UPDATE")
assert(addon.store:find("4540:0").totalGained == 1)

-- Inbox removal still needs a matching bag gain of the exact built-in variant.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1, link = variant, itemID = 15222 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
assert(not addon.store:find(addon.Item.key(variant, 15222)))
assert(#addon.store:exchangeUnresolved() == 1)

-- Success may precede possessions. A new overlapping take cannot reuse that unmeasured proof.
addon, state = mailbox()
state.messages = {
    { sender = "Cara-Realm", items = { { quantity = 1 } } },
    { sender = "Dana-Realm", items = { { quantity = 1 } } },
}
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state.messages[1].items = {}
state:event("MAIL_SUCCESS") -- first attachment removed, bags still unchanged
_G.TakeInboxItem(2, 1)
state.messages[2].items = {}
state.bags = { { quantity = 1 } } -- one unit cannot identify which take reached bags
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0, "unmeasured successful take must remain unresolved on overlap")
assert(#addon.store:exchangeUnresolved() == 2)
-- Unresolved return attribution must not block the next independently measured ordinary take.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", returned = true, items = { { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state.messages = { { sender = "Dana-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_INBOX_UPDATE")
_G.TakeInboxItem(1, 1)
state.messages = {}
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 1)

-- A partial observation of one stack keeps its full selected quantity pending.
addon, state = mailbox()
state.messages = {
    { sender = "Cara-Realm", items = { { quantity = 2 } } },
    { sender = "Dana-Realm", items = { { quantity = 1 } } },
}
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state.messages[1].items = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
_G.TakeInboxItem(2, 1)
state.messages[2].items = {}
state.bags = { { quantity = 2 } } -- could be Cara's delayed second unit
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
assert(#addon.store:exchangeUnresolved() == 2)

-- With no overlap, the next complete observation proves the whole original stack once.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 2 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
state.bags = { { quantity = 2 } }
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 2)
assert(#addon.Journal.query(addon.store) == 1)

-- Expired waiting references cannot suppress an independent later take.
addon, state = mailbox()
state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state:event("MAIL_SUCCESS")
state.clock = state.clock + 61
state:event("BAG_UPDATE_DELAYED")
state.messages = { { sender = "Dana-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_INBOX_UPDATE")
_G.TakeInboxItem(1, 1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 1)
assert(#addon.store:evidenceSummary().unresolved >= 1)

-- Disposing of an earlier gain can repeat a numeric bag baseline without reusing its proof.
addon, state = mailbox()
state:event("MAIL_SHOW")
for take = 1, 3 do
    state.messages = { { sender = "Cara-Realm", items = { { quantity = 1 } } } }
    state:event("MAIL_INBOX_UPDATE")
    _G.TakeInboxItem(1, 1)
    state.messages = {}
    state.bags = { { quantity = 1 } }
    state:event("MAIL_SUCCESS")
    state:event("BAG_UPDATE_DELAYED")
    assert(addon.store:find("4540:0").totalGained == take)
    state.bags = {}
    state:event("BAG_UPDATE_DELAYED")
end

-- Neutral returns do not occupy a later independent gain after disposal, even in the same second.
addon, state = mailbox({ { quantity = 1 } })
state.sameSecond = true
state:event("MAIL_SHOW")
state.outbox = { { quantity = 1 } }
state:event("MAIL_SEND_INFO_UPDATE")
_G.SendMail("Cara-Realm")
state.bags = {}
state:event("MAIL_SEND_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state.messages = { { sender = "Cara-Realm", returned = true, items = { { quantity = 1 } } } }
state:event("MAIL_INBOX_UPDATE")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0)
state.bags = {}
state:event("BAG_UPDATE_DELAYED")
state.messages = { { sender = "Dana-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_INBOX_UPDATE")
_G.TakeInboxItem(1, 1)
state.messages = {}
state.bags = { { quantity = 1 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 1, "disposed return must not reserve a later gain")
-- Overlap protection lasts through a deferred scan, then releases for a fresh take.
addon, state = mailbox()
local timers = {}
_G.C_Timer = {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end,
}
state.messages = {
    { sender = "Cara-Realm", items = { { quantity = 1 } } },
    { sender = "Dana-Realm", items = { { quantity = 1 } } },
    { sender = "Eve-Realm", items = { { quantity = 1 } } },
}
state:event("MAIL_SHOW")
_G.TakeInboxItem(1, 1)
state.messages[1].items = {}
state:event("MAIL_SUCCESS")
_G.TakeInboxItem(2, 1)
state.messages[2].items = {}
state:event("MAIL_SUCCESS")
state.bags = { { quantity = 2 } }
state:event("BAG_UPDATE_DELAYED")
assert(#timers == 1)
_G.TakeInboxItem(3, 1)
state.messages[3].items = {}
state.bags = { { quantity = 3 } }
state:event("MAIL_SUCCESS")
timers[1]()
assert(addon.store:find("4540:0").totalGained == 0, "queued scans must retain overlapping mail uncertainty")
assert(#addon.store:exchangeUnresolved() == 3)
state.messages = { { sender = "Faye-Realm", items = { { quantity = 1 } } } }
state:event("MAIL_INBOX_UPDATE")
_G.TakeInboxItem(1, 1)
state.messages = {}
state.bags = { { quantity = 4 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
timers[2]()
assert(addon.store:find("4540:0").totalGained == 1, "completed flush must release a fresh independent take")
_G.C_Timer = nil
print("mail_event_spec: passed")
