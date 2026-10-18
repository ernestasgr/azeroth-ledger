local load = assert(loadfile("tests/support/addon.lua"))()
local addon
local link = "|Hitem:90::::::::|h[Simple Letter]|h"
local fake = assert(loadfile("tests/support/client.lua"))()
local client
local clock = 1000
local inBags = false

GetServerTime = function()
    return clock
end
UnitName = function(_unit)
    return "Ada"
end
GetRealmName = function()
    return "Realm"
end
UnitLevel = function(_unit)
    return 1
end
GetRealZoneText = function()
    return "Northshire"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and 1 or 0
    end,
    GetContainerItemInfo = function(bag)
        return bag == 0 and inBags and { itemID = 90, hyperlink = link, stackCount = 1 } or nil
    end,
}
_G.C_QuestLog = {
    GetTitleForQuestID = function()
        return "A Letter"
    end,
}
rawset(_G, "GetQuestID", function()
    return 42
end)

local function boot(present)
    client = fake.install()
    AzerothLedgerDB = nil
    clock, inBags = 1000, present
    addon = client.boot({}, load)
end

local function event(name, ...)
    client.event(name, ...)
end

local key = "90:0"

-- The item the quest giver hands over arrives after QUEST_ACCEPTED.
boot(false)
assert(addon.Item.key(link, 90) == key)
clock = 1010
event("QUEST_DETAIL")
clock = 1030
event("QUEST_ACCEPTED", 42)
clock = 1031
inBags = true
event("BAG_UPDATE_DELAYED")

local record = addon.store:find(key)
assert(record and record.totalGained == 1, "a quest-start item stayed Already had at first check")
assert(record.gains[1].method == "Quest")
assert(record.gains[1].context and record.gains[1].context.id == 42 and record.gains[1].context.name == "A Letter")
assert(record.firstSeenUnits == 0, "the quest gain still counted as initial stock")
assert((addon.store:breakdown(key).methods.Seen or 0) == 0)
assert(#addon.store:unresolved() == 0)

-- The bags can update before QUEST_ACCEPTED arrives.
boot(false)
clock = 1010
event("QUEST_DETAIL")
clock = 1030
inBags = true
event("BAG_UPDATE_DELAYED")
event("QUEST_ACCEPTED", 42)
record = addon.store:find(key)
assert(record.totalGained == 1 and record.gains[1].method == "Quest", "an early bag update lost the quest gain")
assert(record.firstSeenUnits == 0)

-- Declining an offer is ordinary: no gain and nothing to review.
boot(false)
clock = 1010
event("QUEST_DETAIL")
clock = 1700
event("BAG_UPDATE_DELAYED")
assert(#addon.store:unresolved() == 0, "a declined quest offer needs review")

-- An item that appears after a complete check, for no known reason, is not
-- one the character already had.
boot(false)
clock = 1010
inBags = true
event("BAG_UPDATE_DELAYED")
record = addon.store:find(key)
assert(record.totalGained == 0, "an unexplained arrival was guessed as a gain")
assert(record.firstSeenLater == true)
local breakdown = addon.store:breakdown(key)
assert(breakdown.methods.Appeared == 1 and breakdown.methods.Seen == nil)
assert(breakdown.sources["Appeared later"] == 1 and breakdown.sources["Initial stock"] == nil)

-- Items present at the first check are still ones the character already had.
boot(true)
record = addon.store:find(key)
assert(record.firstSeenLater == nil)
assert(addon.store:breakdown(key).methods.Seen == 1)

print("quest_accept_event_spec: passed")
