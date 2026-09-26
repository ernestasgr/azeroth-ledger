local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerCollection")

local plain = "|Hitem:2672::::::::|h[Meat]|h"
local bear = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h"
local enchanted = "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h"
local wolf = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h"

local function replay()
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local clock = 1000
    local character = "Ada"
    local realm = "Realm A"
    local slots = { [0] = { itemID = 2672, hyperlink = plain, stackCount = 400 } }
    local api = {
        UnitName = function()
            return character
        end,
        GetRealmName = function()
            return realm
        end,
        GetServerTime = function()
            return clock
        end,
        C_Container = {
            GetContainerNumSlots = function(bag)
                return bag == 0 and 1 or 0
            end,
            GetContainerItemInfo = function(bag)
                return slots[bag]
            end,
        },
    }
    store:scan(addon.Scan.capture(api, "bags", false))
    store:scan(addon.Scan.capture(api, "bags", false))
    store:scan(addon.Scan.capture(api, "bank", false))
    clock = 1050
    slots[0] = { itemID = 100, hyperlink = bear, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    clock = 1100
    character = "Ben"
    realm = "Realm B"
    slots[0] = { itemID = 100, hyperlink = bear, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    clock = 1200
    slots[0] = { itemID = 100, hyperlink = enchanted, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    clock = 1300
    slots[0] = { itemID = 100, hyperlink = wolf, stackCount = 1 }
    store:scan(addon.Scan.capture(api, "bags", false))
    return addon.Schema.open(saved, function(value)
        saved = value
    end)
end

function tests.InitialStockHasNoGain(_self)
    local store = replay()
    local meat = store:find(addon.Item.key(plain, 2672))
    WoWUnit.AreEqual(400, meat.firstSeenUnits)
    WoWUnit.AreEqual(0, meat.totalGained)
    WoWUnit.AreEqual(nil, meat.firstGained)
    WoWUnit.AreEqual(2, #meat.observations)
    WoWUnit.AreEqual(0, meat.observations[2].quantity)
    WoWUnit.IsTrue(not store:area("Ada", "Realm A", "bank").complete)
end

function tests.VariantsAndLinksSurviveRestoration(_self)
    local store = replay()
    WoWUnit.AreEqual(3, #store:list())
    local bearRecord = store:find(addon.Item.key(bear, 100))
    WoWUnit.AreEqual(2, #bearRecord.links)
    WoWUnit.AreEqual(3, #bearRecord.observations)
    WoWUnit.AreEqual(0, bearRecord.observations[3].quantity)
    WoWUnit.AreEqual(2, #bearRecord.characters)
    WoWUnit.AreEqual(1050, bearRecord.firstSeen)
    WoWUnit.AreEqual(1200, bearRecord.lastSeen)
    WoWUnit.AreEqual(1050, bearRecord.characters[1].firstSeen)
    WoWUnit.AreEqual(1100, bearRecord.characters[2].firstSeen)
    WoWUnit.IsTrue(addon.Item.key(bear, 100) ~= addon.Item.key(wolf, 100))
end

function tests.CollectionOpensWithDatedObservations(_self)
    local store = replay()
    local lines = addon.Collection.lines(store, "Ada", "Realm A")
    WoWUnit.IsTrue(lines[2]:find("incomplete", 1, true) ~= nil)
    local frame = addon.Collection.open(_G, store, "Ada", "Realm A")
    WoWUnit.IsTrue(frame and frame:IsShown())
    frame:Hide()
end

function tests.StorageMovesAndUnreadableChecks(_self)
    local store = addon.Schema.open(nil, function() end)
    local clock = 2000
    local character = "Ada"
    ---@type string?
    local bagItem = plain
    local bankItem
    local equippedItem
    local equipmentReadable = true
    local bankReadable = true
    local bankBagReadable = true
    local bankCount = 1
    local api = {
        UnitName = function()
            return character
        end,
        GetRealmName = function()
            return "Realm"
        end,
        GetServerTime = function()
            return clock
        end,
        GetInventoryItemLink = function(_, slot)
            if slot == 1 and not equipmentReadable then
                error("equipment unreadable")
            end
            return slot == 1 and equippedItem or nil
        end,
        C_Container = {
            GetContainerNumSlots = function(bag)
                if bag == -1 and not bankReadable then
                    error("bank unreadable")
                end
                if bag == 6 and not bankBagReadable then
                    error("bank bag unreadable")
                end
                return (bag == 0 or bag == -1) and 1 or 0
            end,
            GetContainerItemInfo = function(bag)
                local link = bag == 0 and bagItem or bag == -1 and bankItem or nil
                return link and { itemID = 2672, hyperlink = link, stackCount = bag == -1 and bankCount or 1 } or nil
            end,
        },
    }
    local function scan(area, bankOpen)
        WoWUnit.IsTrue(store:scan(addon.Scan.capture(api, area, bankOpen)))
    end
    local function ownership(expected)
        local lines = addon.Collection.lines(store, character, "Realm", "Ada", "Realm")
        WoWUnit.IsTrue(table.concat(lines, "\n"):find("Ownership: " .. expected, 1, true) ~= nil)
    end
    scan("bags", true)
    scan("bank", true)
    scan("equipped", true)
    ownership("Present")
    clock = 2010
    bagItem, bankItem = nil, plain
    scan("bags", true)
    scan("bank", true)
    ownership("Present")
    clock = 2020
    bankItem, equippedItem = nil, plain
    scan("bank", true)
    scan("equipped", true)
    ownership("Present")
    clock = 2030
    equippedItem, bagItem = nil, plain
    scan("equipped", true)
    scan("bags", true)
    ownership("Present")
    local record = store:find(addon.Item.key(plain, 2672))
    WoWUnit.AreEqual(0, record.totalGained)
    WoWUnit.AreEqual(1, #store:list())
    clock = 2040
    bagItem = nil
    scan("bags", true)
    ownership("Unknown")
    scan("bank", true)
    scan("equipped", true)
    ownership("Historical only")
    clock = 2050
    scan("bank", false)
    ownership("Unknown")
    clock = 2060
    bankItem = plain
    bankReadable = false
    scan("bank", true)
    ownership("Unknown")
    bankReadable = true
    bankCount = 0
    scan("bank", true)
    ownership("Unknown")
    bankCount = 1
    bankBagReadable = false
    scan("bank", true)
    ownership("Present")
    bankBagReadable = true
    scan("bank", true)
    ownership("Present")
    clock = 2065
    bankItem, equippedItem = nil, plain
    scan("bank", true)
    equipmentReadable = false
    scan("equipped", true)
    ownership("Unknown")
    equipmentReadable = true
    scan("equipped", true)
    ownership("Present")
    clock = 2070
    character = "Ben"
    equippedItem = nil
    scan("bags", true)
    scan("bank", true)
    scan("equipped", true)
    ownership("Unknown")
end

local pelt = "|Hitem:4865::::::::|h[Ruined Pelt]|h"
local peltKey = addon.Item.key(pelt, 4865)

local function lootReplay(startingUnits, gainUnits, receiptUnits, duplicates, receiptAfterScan)
    local saved
    local store = addon.Schema.open(nil, function(value)
        saved = value
    end)
    local function bags(at, units)
        local items = {}
        if units > 0 then
            items[1] = { itemID = 4865, link = pelt, quantity = units }
        end
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            seenAt = at,
            complete = true,
            items = items,
        }))
    end
    bags(1000, startingUnits)
    WoWUnit.IsTrue(store:lootOpen({
        character = "Ada",
        realm = "Realm",
        at = 1010,
        level = 12,
        place = "Elwynn Forest",
        slots = { { key = peltKey } },
    }))
    local receipt = { key = peltKey, quantity = receiptUnits }
    if receiptAfterScan then
        bags(1011, startingUnits + gainUnits)
        WoWUnit.IsTrue(store:lootClose(1011))
        WoWUnit.IsTrue(store:lootClose(1011))
    end
    for _ = 1, duplicates do
        WoWUnit.IsTrue(store:lootReceipt(receipt, 1012, { character = "Ada", realm = "Realm" }))
    end
    if not receiptAfterScan then
        bags(1013, startingUnits + gainUnits)
    end
    return addon.Schema
        .open(saved, function(value)
            saved = value
        end)
        :find(peltKey)
end

function tests.TwoLootedUnitsAreCountedOnce(_self)
    local record = lootReplay(6, 2, 2, 1, false)
    WoWUnit.AreEqual(6, record.firstSeenUnits)
    WoWUnit.AreEqual(2, record.totalGained)
    WoWUnit.AreEqual(8, record.firstSeenUnits + record.totalGained)
    WoWUnit.AreEqual(1, #record.gains)
    WoWUnit.AreEqual("Looted", record.gains[1].method)
end

function tests.DuplicateLookingReceiptsRespectOneUnitIncrease(_self)
    local record = lootReplay(5, 1, 1, 2, false)
    WoWUnit.AreEqual(1, record.totalGained)
    WoWUnit.AreEqual(1, #record.gains)
end

function tests.LateReceiptAfterRepeatedCloseIsCounted(_self)
    local record = lootReplay(5, 1, 1, 1, true)
    WoWUnit.AreEqual(1, record.totalGained)
end

function tests.UnknownSourceStaysUnknown(_self)
    local record = lootReplay(5, 1, 1, 1, false)
    WoWUnit.AreEqual(nil, record.gains[1].source)
    WoWUnit.AreEqual("Elwynn Forest", record.gains[1].place)
    WoWUnit.AreEqual(12, record.gains[1].level)
end

local questLink = "|Hitem:263409::::::::|h[Gardening Pants]|h"
local craftLink = "|Hitem:2996::::::::|h[Bolt of Linen Cloth]|h"
local inputLink = "|Hitem:2589::::::::|h[Linen Cloth]|h"

local function rewardStore()
    local store = addon.Schema.open(nil, function() end)
    local function bags(at, quest, craft, input)
        local items = {}
        for _, item in ipairs({
            { 263409, questLink, quest },
            { 2996, craftLink, craft },
            { 2589, inputLink, input },
        }) do
            if item[3] > 0 then
                items[#items + 1] = { itemID = item[1], link = item[2], quantity = item[3] }
            end
        end
        WoWUnit.IsTrue(store:scan({
            character = "Ada",
            realm = "Realm",
            area = "bags",
            seenAt = at,
            complete = true,
            items = items,
        }))
    end
    return store, bags
end

local function rewardActor()
    return { character = "Ada", realm = "Realm", level = 12, place = "Elwynn Forest" }
end

function tests.ChoiceAndFixedQuestRewardsNeedBagIncrease(_self)
    local choice, choiceBags = rewardStore()
    choiceBags(1000, 0, 0, 0)
    local quest = addon.Reward.quest({}, 92463, questLink, 1)
    WoWUnit.IsTrue(choice:rewardReceipt(quest, 1010, rewardActor()))
    WoWUnit.IsTrue(choice:questTurnedIn(92463, 1010, rewardActor()))
    choiceBags(1011, 1, 0, 0)
    WoWUnit.IsTrue(choice:rewardReceipt(quest, 1012, rewardActor()))
    local key = addon.Item.key(questLink, 263409)
    WoWUnit.AreEqual(1, choice:find(key).totalGained)
    WoWUnit.AreEqual("Quest", choice:find(key).gains[1].method)
    WoWUnit.AreEqual(92463, choice:find(key).gains[1].context.id)

    local fixed, fixedBags = rewardStore()
    fixedBags(2000, 2, 0, 0)
    WoWUnit.IsTrue(fixed:rewardReceipt(quest, 2010, rewardActor()))
    WoWUnit.IsTrue(fixed:questTurnedIn(92463, 2010, rewardActor()))
    fixedBags(2011, 3, 0, 0)
    WoWUnit.AreEqual(1, fixed:find(key).totalGained)
    WoWUnit.AreEqual(2, fixed:find(key).firstSeenUnits)
end

function tests.DeclinedQuestAndCanceledCraftDoNotGain(_self)
    local store, bags = rewardStore()
    bags(3000, 0, 0, 2)
    local quest = addon.Reward.quest({}, 92463, questLink, 1)
    WoWUnit.IsTrue(store:rewardReceipt(quest, 3005, rewardActor()))
    bags(3010, 0, 0, 2)
    WoWUnit.AreEqual(nil, store:find(addon.Item.key(questLink, 263409)))
    local craft = addon.Reward.craft({}, { itemID = 2996, hyperlink = craftLink, quantity = 1 })
    WoWUnit.IsTrue(store:rewardReceipt(craft, 3020, rewardActor()))
    bags(3021, 0, 0, 2)
    WoWUnit.AreEqual(nil, store:find(addon.Item.key(craftLink, 2996)))
end

function tests.BatchAndPartialStackCountOnlyOutputs(_self)
    local store, bags = rewardStore()
    bags(4000, 0, 5, 10)
    local craft = addon.Reward.craft({}, { itemID = 2996, hyperlink = craftLink, quantity = 1 })
    WoWUnit.IsTrue(store:rewardReceipt(craft, 4010, rewardActor()))
    WoWUnit.IsTrue(store:rewardReceipt(craft, 4011, rewardActor()))
    bags(4012, 0, 7, 6)
    local output = store:find(addon.Item.key(craftLink, 2996))
    WoWUnit.AreEqual(2, output.totalGained)
    WoWUnit.AreEqual(1, #output.gains)
    WoWUnit.AreEqual("Crafted", output.gains[1].method)
    WoWUnit.AreEqual(0, store:find(addon.Item.key(inputLink, 2589)).totalGained)
end

function tests.SingleCraftShowsRecipeAndIgnoresDuplicateLootChannel(_self)
    local store, bags = rewardStore()
    bags(5000, 0, 0, 2)
    local key = addon.Item.key(craftLink, 2996)
    WoWUnit.IsTrue(store:lootOpen({
        character = "Ada",
        realm = "Realm",
        at = 5010,
        level = 12,
        place = "Elwynn Forest",
        slots = { { key = key, quantity = 1 } },
    }))
    local craft = addon.Reward.craft({
        C_TradeSkillUI = {
            GetRecipeInfo = function()
                return { name = "Bolt of Linen Cloth" }
            end,
        },
    }, { itemID = 2996, hyperlink = craftLink, quantity = 1 }, 2963)
    WoWUnit.IsTrue(store:rewardReceipt(craft, 5010, rewardActor()))
    WoWUnit.IsTrue(store:lootReceipt({ key = key, quantity = 1 }, 5010, rewardActor()))
    bags(5011, 0, 1, 0)
    local record = store:find(key)
    WoWUnit.AreEqual(1, record.totalGained)
    WoWUnit.AreEqual(1, #record.gains)
    WoWUnit.AreEqual("Crafted", record.gains[1].method)
    WoWUnit.AreEqual(2963, record.gains[1].context.id)
    local lines = table.concat(addon.Collection.lines(store, "Ada", "Realm"), "\n")
    WoWUnit.IsTrue(lines:find("recipe Bolt of Linen Cloth", 1, true) ~= nil)
end
