local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70205 })
-- Loot that goes straight into gear, and loot slots that become readable late.
local link = "|cnIQ0:|Hitem:7098::::::::1:1485:::::::::|h[Splintered Tusk]|h|r"
local eggLink = "|cnIQ1:|Hitem:6889::::::::1:1485:::::::::|h[Small Egg]|h|r"
local clock = 2000
GetServerTime = function()
    return clock
end
UnitName = function(unit)
    return unit == "player" and "Mindria" or "Young Thistle Boar"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 1
end
GetRealZoneText = function()
    return "Teldrassil"
end
rawset(_G, "UnitGUID", function()
    return "Creature-0-6783-1-118-1984-000040D7BC"
end)
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
local addon = load.addon("Main", {})
local event = client.event

-- The client names the crafted result after the cast that began its recipe.
local function craft(recipeID, itemID, itemLink)
    event("TRADE_SKILL_CRAFT_BEGIN", recipeID)
    event("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = itemID, hyperlink = itemLink, quantity = 1 })
    event("UPDATE_TRADESKILL_CAST_STOPPED")
end

-- Equip a newly looted intrinsic variant before the deferred inventory check.
do
    local sword = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h"
    local otherSword = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h"
    local swordKey = addon.Item.key(sword, 100)
    for _, scenario in ipairs({
        "normal",
        "equip",
        "late receipt",
        "late slot",
        "reload before check",
        "partial bag baseline",
        "partial gear baseline",
        "incomparable baseline",
        "partial bags after loot",
        "partial gear after loot",
        "existing gear move",
        "partial existing gear move",
        "incomparable existing gear move",
        "unreadable owned gear move",
        "different variant",
        "no receipt",
        "no slot",
        "competing craft",
    }) do
        local bagSword, gearSword, callbacks = nil, nil, {}
        local slotReadable = scenario ~= "late slot"
        local bagReadable = scenario ~= "partial bag baseline"
        local gearReadable = scenario ~= "partial gear baseline" and scenario ~= "unreadable owned gear move"
        if scenario:find("existing gear move", 1, true) or scenario == "unreadable owned gear move" then
            gearSword = sword
        end
        _G.AzerothLedgerDB = nil
        local api = {
            GetInventoryItemLink = function(_, slot)
                assert(gearReadable, "unreadable equipment")
                return slot == 16 and gearSword or nil
            end,
            C_Container = {
                GetContainerNumSlots = function(bag)
                    assert(bagReadable, "unreadable bags")
                    return bag == 0 and 1 or 0
                end,
                GetContainerItemInfo = function(bag)
                    return bag == 0 and bagSword and { itemID = 100, hyperlink = bagSword, stackCount = 1 } or nil
                end,
            },
            GetNumLootItems = function()
                return scenario == "late slot" and 2 or 1
            end,
            GetLootSlotInfo = function()
                return nil, "Sword", 1
            end,
            GetLootSourceInfo = function()
                return "Creature-0-6783-1-118-1984-000040D7BC", 1
            end,
            GetLootSlotLink = function(slot)
                if scenario == "late slot" then
                    return slot == 1 and link or (slotReadable and sword or nil)
                end
                return scenario ~= "no slot" and sword or nil
            end,
            C_Timer = {
                After = function(_, callback)
                    callbacks[#callbacks + 1] = callback
                end,
            },
        }
        for name, value in pairs(api) do
            _G[name] = value
        end
        local function start()
            assert(loadfile("AzerothLedger/Main.lua"))("AzerothLedger", addon)
            event("ADDON_LOADED", "AzerothLedger")
            event("PLAYER_LOGIN")
            event("BAG_UPDATE_DELAYED")
            local loaded = callbacks
            callbacks = {}
            for _, callback in ipairs(loaded) do
                callback()
            end
        end
        local function check()
            clock = clock + 1
            event("BAG_UPDATE", 0)
            event("BAG_UPDATE_DELAYED")
            event("PLAYER_EQUIPMENT_CHANGED", 16)
            assert(#callbacks == 1, "Bag/gear changes must share one deferred observation")
            local callback = callbacks[1]
            callbacks = {}
            callback()
        end
        local function receipt()
            event("CHAT_MSG_LOOT", "You receive loot: " .. sword)
        end
        clock = 2100
        start()
        if
            scenario == "incomparable baseline"
            or scenario == "partial existing gear move"
            or scenario == "incomparable existing gear move"
        then
            assert(addon.store:scan({
                character = "Mindria",
                realm = "Classic Beta PvE",
                area = "equipped",
                seenAt = 2101,
                complete = scenario ~= "partial existing gear move",
                items = gearSword and { { itemID = 100, link = gearSword, quantity = 1 } } or {},
            }))
        end
        clock = 2110
        event("LOOT_READY", true, false)
        event("LOOT_READY", true, false)
        if scenario == "competing craft" then
            craft(nil, 100, sword)
            local crafts = 0
            addon.store:visitEvidence(function(entry)
                crafts = crafts + (entry.method == "Crafted" and entry.key == swordKey and 1 or 0)
            end)
            assert(crafts == 1, "The crafted sword must wait for its possessions check")
        end
        if scenario ~= "late receipt" and scenario ~= "no receipt" then
            receipt()
        end
        if scenario == "reload before check" then
            start()
        end
        bagReadable, gearReadable = scenario ~= "partial bags after loot", scenario ~= "partial gear after loot"
        if
            scenario == "normal"
            or scenario:find("existing gear move", 1, true)
            or scenario == "unreadable owned gear move"
        then
            bagSword, gearSword = sword, nil
        else
            gearSword = scenario == "different variant" and otherSword or sword
        end
        if scenario ~= "late slot" then
            event("LOOT_CLOSED")
        end
        check()
        local pending = scenario == "late receipt"
            or scenario == "late slot"
            or scenario == "partial bags after loot"
            or scenario == "partial gear after loot"
        local expected = (scenario == "normal" or scenario == "equip") and 1 or 0
        local gained = addon.store:find(swordKey)
        assert((gained and gained.totalGained or 0) == expected, scenario .. ": wrong confirmed gain count")
        if pending then
            assert(not gained or gained.firstSeenUnits == 1, "Unsettled proof must remain Seen")
            if scenario == "late receipt" then
                receipt()
            elseif scenario == "late slot" then
                slotReadable = true
                event("LOOT_OPENED", true, false)
                event("LOOT_CLOSED")
            else
                bagReadable, gearReadable = true, true
                check()
            end
            expected = 1
        end
        gained = addon.store:find(swordKey)
        if expected == 1 then
            assert(gained.totalGained == 1, "Equipped sword: Total gained 0 instead of one Looted gain")
            assert(gained.firstSeenUnits == 0, "Confirmed new loot must not remain initial stock")
            assert(addon.store:breakdown(swordKey).methods.Looted == 1)
            assert(addon.store:breakdown(swordKey).recorded == 1)
            assert(#addon.store:takeDiscoveries() == 1, "Exactly one persisted discovery should queue a toast")
            assert(gained.gains[1].source.guid == "Creature-0-6783-1-118-1984-000040D7BC")
            receipt()
            event("LOOT_OPENED", true, false)
            check()
            bagSword, gearSword = sword, nil
            check()
            bagSword, gearSword = nil, sword
            check()
            assert(addon.store:find(swordKey).totalGained == 1, "Moves or duplicates added another gain")
            assert(#addon.store:takeDiscoveries() == 0, "Duplicates queued another discovery")
        end
        start()
        check()
        gained = addon.store:find(swordKey)
        assert((gained and gained.totalGained or 0) == expected, scenario .. ": reload changed confirmed gains")
        assert(#addon.store:takeDiscoveries() == 0, "Reload queued an old discovery")
    end
end

-- A second same-item slot may become readable after the item-count update and
-- loot close; its exact source proof must still settle the measured receipt.
local lateStore = addon.Schema.open(nil, function() end)
local lateActor = { character = "Mindria", realm = "Classic Beta PvE" }
assert(lateStore:setCharacter(lateActor.character, lateActor.realm))
local lateContext = {
    character = lateActor.character,
    realm = lateActor.realm,
    at = 7000,
    level = 1,
    place = "Teldrassil",
}
assert(lateStore:scan({
    character = lateActor.character,
    realm = lateActor.realm,
    area = "bags",
    complete = true,
    seenAt = 7000,
    items = {},
}))
assert(lateStore:scan({
    character = lateActor.character,
    realm = lateActor.realm,
    area = "equipped",
    complete = true,
    seenAt = 7000,
    items = {},
}))
rawset(_G, "GetNumLootItems", function()
    return 2
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Loot item", 1
end)
rawset(_G, "GetLootSourceInfo", function()
    return "Creature-0-6783-1-118-1984-000040D7BC", 1
end)
local lateSlotReadable = false
rawset(_G, "GetLootSlotLink", function(slot)
    if slot == 1 or lateSlotReadable then
        return eggLink
    end
end)
local firstLateSlots = assert(addon.Loot.open(_G))
assert(#firstLateSlots == 1, "The first snapshot should contain only the readable loot slot")
lateContext.slots = firstLateSlots
assert(lateStore:command("lootOpen", lateContext, lateContext.at, lateContext))
assert(lateStore:command("lootReceipt", { key = "6889:0", quantity = 2 }, 7001, lateActor))
assert(lateStore:scan({
    character = lateActor.character,
    realm = lateActor.realm,
    area = "bags",
    complete = true,
    seenAt = 7002,
    items = { { itemID = 6889, link = eggLink, quantity = 2 } },
}))
assert(lateStore:command("lootClose", nil, 7002, lateActor))
lateSlotReadable = true
local lateSlots = assert(addon.Loot.open(_G))
assert(#lateSlots == 2, "The later snapshot should expose both same-item loot slots")
assert(lateStore:command("lootSourceProof", { slots = lateSlots }, 7003, lateActor))
local lateRecord = assert(lateStore:find("6889:0"))
local lateBreakdown = lateStore:breakdown("6889:0")
assert(lateRecord.firstSeenUnits == 0, "The late second slot must not leave a loot unit as initial stock")
assert(lateRecord.totalGained == 2, "The late second slot must settle the second measured loot unit")
assert(lateBreakdown.methods.Looted == 2, "Both units must remain Looted after late slot proof")
assert(lateBreakdown.sources["Young Thistle Boar"] == 2, "Both units must keep their proven mob source")
print("loot_gear_event_spec: passed")
