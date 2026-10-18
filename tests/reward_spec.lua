local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("Collection")
date = os.date

local questLink = "|Hitem:263409::::::::|h[Gardening Pants]|h"
local boltLink = "|Hitem:2996::::::::|h[Bolt of Linen Cloth]|h"
local clothLink = "|Hitem:2589::::::::|h[Linen Cloth]|h"
local questKey = addon.Item.key(questLink, 263409)
local boltKey = addon.Item.key(boltLink, 2996)
local clothKey = addon.Item.key(clothLink, 2589)
local otherChoice = assert(addon.Reward.quest({}, 92463, boltLink, 1))

local function scenario()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    assert(store:setCharacter("Ada", "Realm"))
    local function bags(at, quest, bolts, cloth)
        local items = {}
        local entries = { { questLink, 263409, quest }, { boltLink, 2996, bolts }, { clothLink, 2589, cloth } }
        for _, entry in ipairs(entries) do
            if entry[3] > 0 then
                items[#items + 1] = { link = entry[1], itemID = entry[2], quantity = entry[3] }
            end
        end
        assert(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            seenAt = at,
            complete = true,
            items = items,
        }))
    end
    local function restore()
        store = addon.Schema.open(saved, function(value)
            saved = value
        end)
        assert(store:setCharacter("Ada", "Realm"))
        return store
    end
    return store, bags, restore
end

local quest = assert(addon.Reward.quest(
    { C_QuestLog = {
        GetTitleForQuestID = function()
            return "Garden Work"
        end,
    } },
    92463,
    questLink,
    1
))
assert(quest.context.id == 92463 and quest.context.name == "Garden Work")
assert(not addon.Reward.quest({}, 92463, "broken", 1))
local crafted = assert(addon.Reward.craft({}, { itemID = 2996, hyperlink = boltLink, quantity = 1 }))
assert(crafted.method == "Crafted" and crafted.context == nil)
local function recipeInfo()
    return { name = "Bolt of Linen Cloth" }
end
local recipeAPI = { C_TradeSkillUI = { GetRecipeInfo = recipeInfo } }
local namedCraft = addon.Reward.craft(recipeAPI, { itemID = 2996, hyperlink = boltLink, quantity = 1 }, 2963)
assert(namedCraft.context.id == 2963 and namedCraft.context.name == "Bolt of Linen Cloth")

local choice, choiceBags, choiceRestore = scenario()
choiceBags(1000, 0, 0, 2)
assert(
    choice:command(
        "rewardReceipt",
        quest,
        1010,
        { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest" }
    )
)
assert(choice:command("questTurnedIn", 92463, 1010, { character = "Ada", realm = "Realm" }))
choiceBags(1011, 1, 0, 2)
assert(
    choice:command(
        "rewardReceipt",
        quest,
        1012,
        { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest" }
    )
)
choiceRestore()
local choiceRecord = assert(choice:find(questKey))
assert(choiceRecord.totalGained == 1 and #choiceRecord.gains == 1)
assert(choiceRecord.firstSeenUnits == 0)
assert(choiceRecord.gains[1].method == "Quest" and choiceRecord.gains[1].context.id == 92463)
local lines = table.concat(addon.Collection.lines(choice, "Ada", "Realm"), "\n")
assert(lines:find("+1 Quest", 1, true) and lines:find("Garden Work", 1, true))
assert(lines:find("Recent activity", 1, true))

local fixed, fixedBags = scenario()
fixedBags(2000, 2, 0, 0)
assert(
    fixed:command("rewardReceipt", quest, 2010, { character = "Ada", realm = "Realm", level = 12, place = "Unknown" })
)
assert(fixed:command("questTurnedIn", 92463, 2010, { character = "Ada", realm = "Realm" }))
fixedBags(2011, 3, 0, 0)
assert(fixed:find(questKey).totalGained == 1)
assert(fixed:find(questKey).firstSeenUnits == 2)

local overlapping, overlappingBags = scenario()
overlappingBags(2500, 0, 0, 0)
assert(
    overlapping:command(
        "rewardReceipt",
        quest,
        2510,
        { character = "Ada", realm = "Realm", level = 12, place = "Unknown" }
    )
)
local otherQuest = addon.Reward.quest({}, 92464, questLink, 1)
assert(
    overlapping:command(
        "rewardReceipt",
        otherQuest,
        2510,
        { character = "Ada", realm = "Realm", level = 12, place = "Unknown" }
    )
)
assert(overlapping:command("questTurnedIn", 92463, 2510, { character = "Ada", realm = "Realm" }))
assert(overlapping:command("questTurnedIn", 92464, 2510, { character = "Ada", realm = "Realm" }))
overlappingBags(2511, 1, 0, 0)
assert(overlapping:find(questKey).totalGained == 1)

local repeatable, repeatableBags = scenario()
repeatableBags(2600, 0, 0, 0)
local repeatActor = { character = "Ada", realm = "Realm", level = 12, place = "Unknown" }
local repeatIdentity = { character = "Ada", realm = "Realm" }
assert(repeatable:command("rewardReceipt", quest, 2610, repeatActor))
assert(repeatable:command("questTurnedIn", 92463, 2610, repeatIdentity))
repeatableBags(2611, 1, 0, 0)
assert(repeatable:command("rewardReceipt", quest, 2620, repeatActor))
assert(repeatable:command("questTurnedIn", 92463, 2620, repeatIdentity))
repeatableBags(2621, 2, 0, 0)
assert(repeatable:find(questKey).totalGained == 2)

local canceled, canceledBags = scenario()
canceledBags(3000, 0, 0, 2)
assert(
    canceled:command(
        "rewardReceipt",
        quest,
        3005,
        { character = "Ada", realm = "Realm", level = 12, place = "Unknown" }
    )
)
canceledBags(3010, 0, 0, 2)
assert(canceled:find(clothKey).totalGained == 0)
assert(
    canceled:command(
        "rewardReceipt",
        crafted,
        3020,
        { character = "Ada", realm = "Realm", level = 12, place = "Unknown" }
    )
)
canceledBags(3021, 0, 0, 2)
assert(canceled:find(boltKey) == nil)

local batch, batchBags, batchRestore = scenario()
batchBags(4000, 0, 5, 10)
local actor = { character = "Ada", realm = "Realm", level = 12, place = "Stormwind" }
assert(batch:command("rewardReceipt", crafted, 4010, actor))
assert(batch:command("rewardReceipt", crafted, 4011, actor))
batchBags(4012, 0, 7, 6)
assert(batch:find(boltKey).totalGained == 2)
assert(batch:find(clothKey).totalGained == 0)
batchRestore()
assert(batch:find(boltKey).totalGained == 2)
assert(batch:command("rewardReceipt", crafted, 4013, actor))
batchBags(4014, 0, 7, 6)
assert(batch:find(boltKey).totalGained == 2)

local delayed, delayedBags, delayedRestore = scenario()
delayedBags(5000, 0, 5, 0)
assert(delayed:command("rewardReceipt", crafted, 5010, actor))
delayedBags(5011, 0, 5, 0)
delayed = delayedRestore()
delayedBags(5012, 0, 6, 0)
assert(delayed:find(boltKey).totalGained == 0)
assert(delayed:unresolved()[1].reason == "reload")

local cross, crossBags = scenario()
crossBags(6000, 0, 5, 0)
assert(
    cross:command(
        "lootOpen",
        { slots = { { key = boltKey, quantity = 1 } } },
        6010,
        { character = "Ada", realm = "Realm", level = 12, place = "Stormwind" }
    )
)
assert(cross:command("rewardReceipt", crafted, 6010, actor))
assert(cross:command("lootReceipt", { key = boltKey, quantity = 1 }, 6010, actor))
crossBags(6011, 0, 6, 0)
assert(cross:find(boltKey).totalGained == 1)
assert(cross:find(boltKey).gains[1].method == "Crafted")
assert(cross:command("lootClose", nil, 6012, actor))
assert(
    cross:command(
        "lootOpen",
        { slots = { { key = boltKey, quantity = 1 } } },
        6020,
        { character = "Ada", realm = "Realm", level = 12, place = "Stormwind" }
    )
)
assert(cross:command("lootReceipt", { key = boltKey, quantity = 1 }, 6020, actor))
crossBags(6021, 0, 7, 0)
assert(cross:find(boltKey).totalGained == 2)
assert(cross:find(boltKey).gains[2].method == "Looted")

local inferred, inferredBags, inferredRestore = scenario()
inferredBags(7000, 0, 0, 0)
local previewQuest = {
    key = questKey,
    quantity = 1,
    method = "Quest",
    context = quest.context,
    preview = true,
    choiceGroup = "choice:1",
}
local previewOther =
    { key = boltKey, quantity = 1, method = "Quest", context = quest.context, preview = true, choiceGroup = "choice:1" }
assert(inferred:command("rewardReceipt", previewQuest, 7010, actor))
assert(inferred:command("rewardReceipt", previewOther, 7010, actor))
assert(inferred:command("questTurnedIn", 92463, 7010, actor))
inferred = inferredRestore()
inferredBags(7011, 1, 0, 0)
assert(inferred:find(questKey).totalGained == 0)
assert(#inferred:unresolved() == 2)
inferredBags(7012, 1, 1, 0)
assert(inferred:find(boltKey).totalGained == 0)

local ambiguous, ambiguousBags = scenario()
ambiguousBags(8000, 0, 0, 0)
assert(ambiguous:command("rewardReceipt", previewQuest, 8010, actor))
assert(ambiguous:command("rewardReceipt", previewOther, 8010, actor))
assert(ambiguous:command("questTurnedIn", 92463, 8010, actor))
ambiguousBags(8011, 1, 1, 0)
assert(ambiguous:find(questKey).totalGained == 0)
assert(ambiguous:find(boltKey).totalGained == 0)
ambiguousBags(8012, 1, 0, 0)
assert(ambiguous:find(questKey).totalGained == 0)
assert(ambiguous:command("rewardReceipt", quest, 8013, actor))
ambiguousBags(8014, 2, 0, 0)
assert(ambiguous:find(questKey).totalGained == 1)

local explicit, explicitBags = scenario()
explicitBags(9000, 0, 0, 0)
assert(explicit:command("rewardReceipt", previewQuest, 9010, actor))
assert(explicit:command("rewardReceipt", previewOther, 9010, actor))
assert(explicit:command("rewardReceipt", otherChoice, 9010, actor))
assert(explicit:command("questTurnedIn", 92463, 9010, actor))
explicitBags(9011, 1, 1, 0)
assert(explicit:find(questKey).totalGained == 0)
assert(explicit:find(boltKey).totalGained == 1)

local late, lateBags, lateRestore = scenario()
local function scanEquipped(store, at, quantity)
    local items = quantity > 0 and { { link = questLink, itemID = 263409, quantity = quantity } } or {}
    assert(store:scan({
        character = "Ada",
        realm = "Realm",
        area = "equipped",
        seenAt = at,
        complete = true,
        items = items,
    }))
end
lateBags(10000, 2, 0, 0)
scanEquipped(late, 10000, 0)
assert(late:command("questPrepared", 92463, 10010, actor))
assert(not late:command("questPrepared", 92463, 10010, actor))
assert(late:command("questTurnedIn", 92463, 10011, actor))
lateBags(10012, 3, 0, 0)
scanEquipped(late, 10012, 0)
late = lateRestore()
assert(late:command("rewardReceipt", quest, 10013, actor))
lateBags(10014, 3, 0, 0)
scanEquipped(late, 10014, 0)
assert(late:find(questKey).totalGained == 0)
assert(late:find(questKey).firstSeenUnits == 2)
assert(late:command("rewardReceipt", quest, 10015, actor))
lateBags(10016, 3, 0, 0)
scanEquipped(late, 10016, 0)
assert(late:find(questKey).totalGained == 0)

local moved, movedBags = scenario()
movedBags(11000, 1, 0, 0)
scanEquipped(moved, 11000, 0)
assert(moved:command("questPrepared", 92463, 11010, actor))
assert(moved:command("questTurnedIn", 92463, 11011, actor))
movedBags(11012, 0, 0, 0)
scanEquipped(moved, 11012, 1)
assert(moved:command("rewardReceipt", quest, 11013, actor))
movedBags(11014, 0, 0, 0)
scanEquipped(moved, 11014, 1)
assert(moved:find(questKey).totalGained == 0)

print("reward_spec: passed")
