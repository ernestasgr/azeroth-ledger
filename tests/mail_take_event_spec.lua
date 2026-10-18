-- Synthetic production hooks/events; this does not certify native client behavior.
local mailbox = assert(loadfile("tests/support/mailbox.lua"))()
local addon, state, record
local variant = "|Hitem:15222::::::1647:::|h[Barbed Club of the Bear]|h"

-- A character's view also shows units that appeared after its earlier check with no known way.
addon, state = mailbox()
state.bags = { { quantity = 1 } }
state:event("BAG_UPDATE_DELAYED")
local appeared = addon.store:breakdown("4540:0", { character = "Ada", realm = "Realm" })
assert(appeared.methods.Appeared == 1 and appeared.sources["Appeared later"] == 1)

-- A character switch reads empty bags until the client loads them; that read proves nothing.
addon, state = mailbox(nil, true)
state.bags = { { quantity = 3 } }
state:event("BAG_UPDATE_DELAYED")
record = addon.store:find("4540:0")
assert(not record.firstSeenLater, "items present at login were already had, not appeared later")

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
print("mail_take_event_spec: passed")
