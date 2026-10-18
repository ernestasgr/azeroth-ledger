-- Synthetic production hooks/events; this does not certify native client behavior.
local mailbox = assert(loadfile("tests/support/mailbox.lua"))()
local link = "|Hitem:4540::::::::|h[Bread]|h"

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

-- A Black Market win arrives as system mail with no invoice. Won this session,
-- it is a purchase; the same mail with no win stays unconfirmed.
for _, wonHere in ipairs({ true, false }) do
    addon, state = mailbox()
    state.messages = { { sender = "Madam Swyndle", canReply = false, items = { { quantity = 1 } } } }
    if wonHere then
        state:event("BLACK_MARKET_WON", 7, 4540)
    end
    state:event("MAIL_SHOW")
    _G.TakeInboxItem(1, 1)
    state:event("CHAT_MSG_LOOT", "You receive item: |Hitem:4540::::::::|h[Bread]|h.")
    state.messages[1].items = {}
    state.bags = { { quantity = 1 } }
    state:event("MAIL_SUCCESS")
    state:event("BAG_UPDATE_DELAYED")
    state:event("BAG_UPDATE_DELAYED")
    record = addon.store:find("4540:0")
    assert(record.totalGained == (wonHere and 1 or 0), "only a Black Market win makes system mail a purchase")
    if wonHere then
        assert(addon.Journal.query(addon.store)[1].action == "Auction purchase")
    end
end

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
state = select(2, mailbox({ { quantity = 2 } }))
state:event("MAIL_SHOW")
state.outbox = { { quantity = 2 } }
state:event("MAIL_SEND_INFO_UPDATE")
_G.SendMail("Ben-Realm")
state.bags = {}
state:event("MAIL_SEND_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state:event("MAIL_CLOSED")
addon = state:relog("Ben")
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
state = select(2, mailbox({ { quantity = 2 } }))
state:event("MAIL_SHOW")
state.outbox = { { quantity = 2 } }
state:event("MAIL_SEND_INFO_UPDATE")
_G.SendMail("Ben Truehammer")
state.bags = {}
state:event("MAIL_SEND_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
state:event("MAIL_CLOSED")
addon = state:relog("Ben")
state.messages = { { sender = "Ada Quietfield", items = { { quantity = 2 } } } }
state:event("MAIL_SHOW")
_G.AutoLootMailItem(1)
state.messages = {}
state.bags = { { quantity = 2 } }
state:event("MAIL_SUCCESS")
state:event("BAG_UPDATE_DELAYED")
assert(addon.store:find("4540:0").totalGained == 0, "surnamed alt mail must be a transfer")
assert(#addon.store:exchangeActivity() == 1 and addon.store:exchangeActivity()[1].sender == "Ada")
-- A transfer moves units between characters; the account still has only Ada's two.
local seen = addon.LastSeen.project(addon.store, addon.store:find("4540:0"), "Ben", "Realm")
assert(seen.characterOverall == 2, "Ben received two by transfer")
assert(seen.allCharactersOverall == 2, "a transfer must not count the same units twice")
local received = addon.store:breakdown("4540:0", { character = "Ben", realm = "Realm" })
assert(received.methods.Transfer == 2, "Ben's view must say how the transferred units arrived")
assert(received.sources["Your characters"] == 2 and received.gained == 0)
assert(not addon.store:breakdown("4540:0").methods.Transfer, "the account view counts them where they started")
assert(not received.methods.Seen, "Ben had none of his own")
local sender = addon.store:breakdown("4540:0", { character = "Ada", realm = "Realm" })
assert(sender.methods.Seen == 2, "Ada's view must show the units she already had")
assert(sender.sources["Initial stock"] == 2)
-- Across the realm both ends of the transfer are in view: each unit has one way.
local realm = addon.store:breakdown("4540:0", { realm = "Realm" })
assert(not realm.methods.Transfer and realm.methods.Seen == 2, "a realm view holds both ends of the transfer")
assert(not realm.sources["Your characters"])
print("mail_event_spec: passed")
