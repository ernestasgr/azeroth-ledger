-- Replays overlapping quest accept windows from a Forever trace (build
-- 1.60.1.70450): each item belongs to one quest, and nothing is left to review.
local load = assert(loadfile("tests/support/addon.lua"))()
local fake = assert(loadfile("tests/support/client.lua"))()
local client, addon
local clock = 1000
local quest = 0
local rewards = {}
local bags = {}
local titles = {
    [54] = "Report to Goldshire",
    [96627] = "The Adventurer",
    [91743] = "Rascally Rodents",
    [91758] = "Follow That Kobold!",
    [91772] = "Shhh! We're Hunting Kobolds",
}
local documents = "|cnIQ1:|Hitem:745::::::::4:1490:::::::::|h[Marshal McBride's Documents]|h|r"
local harvest = "|cnIQ1:|Hitem:247841::::::::4:1490::11:::::::|h[Wild Harvest]|h|r"
local kit = "|cnIQ1:|Hitem:247970::::::::4:1490::11:::::::|h[Kobold Tracking Kit]|h|r"

GetServerTime = function()
    return clock
end
UnitName = function()
    return "Kimberdra"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 4
end
GetRealZoneText = function()
    return "Elwynn Forest"
end
GetInventoryItemLink = function()
    return nil
end
LOOT_ITEM_PUSHED_SELF = "You receive item: %s"
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d"
C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and 4 or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local link = bag == 0 and bags[slot]
        return link and { itemID = tonumber(link:match("|Hitem:(%d+)")), hyperlink = link, stackCount = 1 } or nil
    end,
}
_G.C_QuestLog = {
    GetTitleForQuestID = function(id)
        return titles[id]
    end,
}
rawset(_G, "GetQuestID", function()
    return quest
end)
rawset(_G, "GetNumQuestChoices", function()
    return 0
end)
rawset(_G, "GetNumQuestRewards", function()
    return #rewards
end)
rawset(_G, "GetQuestItemLink", function(kind, index)
    return kind == "reward" and rewards[index] or nil
end)
rawset(_G, "GetQuestItemInfo", function(kind, index)
    return kind == "reward" and rewards[index] and "Reward" or nil, nil, 1
end)

local function boot()
    client = fake.install({ build = 70450 })
    AzerothLedgerDB = nil
    clock, quest, rewards, bags = 1000, 0, {}, {}
    addon = client.boot({}, load)
end

local event = function(...)
    client.event(...)
end

local function accept(id, at, gift)
    clock, quest = at, id
    event("QUEST_DETAIL", 0)
    event("QUEST_FINISHED")
    if gift then
        event("BAG_UPDATE_DELAYED")
    end
    event("QUEST_ACCEPTED", id)
    if gift then
        event("CHAT_MSG_LOOT", "You receive item: " .. gift)
        bags[#bags + 1] = gift
        event("BAG_UPDATE_DELAYED")
    end
end

local function questOf(link)
    local record = addon.store:find(addon.Item.key(link, tonumber(link:match("|Hitem:(%d+)"))))
    assert(record and record.totalGained == 1, link .. " was not counted once")
    return record.gains[1].context and record.gains[1].context.id
end

local function nothingToReview(message)
    clock = clock + 120
    event("BAG_UPDATE_DELAYED")
    assert(#addon.store:unresolved() == 0, message)
end

-- A turn-in reward that arrives while other quests' accept windows are open
-- is the turned-in quest's.
boot()
accept(54, 1648, documents)
accept(96627, 1650)
clock, quest, rewards = 1661, 91743, { harvest }
event("QUEST_COMPLETE")
clock = 1663
event("QUEST_TURNED_IN", 91743, 170, 17)
event("QUEST_LOOT_RECEIVED", 91743, harvest, 1)
event("CHAT_MSG_LOOT", "You receive item: " .. harvest)
bags[#bags + 1] = harvest
event("BAG_UPDATE_DELAYED")
event("QUEST_FINISHED")
assert(questOf(documents) == 54, "the quest-start item lost its quest")
assert(questOf(harvest) == 91743, "a turn-in reward was credited to an accepted quest")
nothingToReview("open accept windows also claimed a turn-in reward")

-- An item handed over on accept is the newest accepted quest's, not an
-- earlier one's whose window is still open.
boot()
accept(91758, 2132)
clock, quest, rewards = 2162, 91758, {}
event("QUEST_COMPLETE")
event("QUEST_TURNED_IN", 91758, 35, 0)
event("QUEST_FINISHED")
accept(91772, 2164, kit)
assert(questOf(kit) == 91772, "the quest-start item was credited to an earlier quest")
nothingToReview("an earlier accept window left the quest-start item to review")

print("quest_accept_overlap_event_spec: passed")
