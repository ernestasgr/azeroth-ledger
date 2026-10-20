-- Opening a trade (or mail, or the guild bank) checks possessions. When that
-- check covered bags alone, bags and gear held different check times, and the
-- next loot window could not trust its gear baseline, so its loot was never
-- credited and ended in review as an expired loot session.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70450 })
local addon = {}
local clock = 1000
local herb = { id = 765, link = "|cnIQ1:|Hitem:765::::::::6:1490:::::::::|h[Silverleaf]|h|r" }
local nodeGUID = "GameObject-0-6782-0-2-1617-569BE5869A"
local bags = {}

GetServerTime = function()
    return clock
end
UnitName = function(unit)
    return unit == "target" and "Hogger" or "Kimberdra"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 6
end
GetRealZoneText = function()
    return "Elwynn Forest"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(container)
        return container == 0 and 2 or 0
    end,
    GetContainerItemInfo = function(container, slot)
        local entry = container == 0 and bags[slot]
        return entry and { itemID = entry.item.id, hyperlink = entry.item.link, stackCount = entry.count } or nil
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
rawset(_G, "GetNumLootItems", function()
    return 1
end)
rawset(_G, "GetLootSlotLink", function()
    return herb.link
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Silverleaf", 3
end)
rawset(_G, "GetLootSourceInfo", function()
    return nodeGUID, 1
end)
rawset(_G, "UnitGUID", function()
    return nil
end)

load.addon("Main", addon)
local event = client.event
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")

-- The Forever order from the saved trace: a trade that moves nothing, then
-- a herb gather whose loot window fires LOOT_READY but no LOOT_OPENED.
clock = 1824
event("TRADE_SHOW")
event("TRADE_CLOSED")
clock = 1958
event("UNIT_SPELLCAST_SENT", "player", "Silverleaf", "Cast-3-1-1-1-2366-0001", 2366)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-2366-0001", 2366)
event("LOOT_READY", false)
event("LOOT_CLOSED")
event("LOOT_CLOSED")
event("CHAT_MSG_LOOT", "You receive loot: " .. herb.link .. "x3")
event("BAG_UPDATE_DELAYED")
clock = 1959
bags = { { item = herb, count = 3 } }
event("BAG_UPDATE_DELAYED")

local record = addon.store:find("765:0")
assert(record and #record.gains == 1, "the gathered Silverleaf was not credited once")
assert(record.gains[1].method == "Looted", "the gathered Silverleaf was not Looted")
assert(record.gains[1].quantity == 3, "the gathered Silverleaf was not credited as 3")
addon.store:visitEvidence(function(entry)
    assert(entry.kind ~= "loot", "the herb's loot session was left unsettled")
end)
assert(addon.store:expireEvidence(clock + 86400))
for _, entry in ipairs(addon.store:unresolved()) do
    assert(entry.kind ~= "loot", "the herb's loot session expired into review")
end
