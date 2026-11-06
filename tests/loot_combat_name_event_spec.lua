-- In combat the client hides unit names and GUIDs, but the loot window still
-- names each corpse by GUID. Every spawn of one creature shares its name, so a
-- name read earlier from the target, mouseover or a nameplate names the corpse.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70790 })
local addon = {}
local clock = 1000
local seed = { id = 257128, link = "|cnIQ1:|Hitem:257128::::::::12:1482:::::::::|h[Zephyrseed]|h|r" }
local bags = {}

-- Two spawns of Prideclaw (256092), one Ridge Stalker (256093), one Thornmaw (256094).
local prideclawA = "Creature-0-6846-2991-2-256092-00000000A1"
local prideclawB = "Creature-0-6846-2991-2-256092-00000000B2"
local stalkerA = "Creature-0-6846-2991-2-256093-00000000C3"
local stalkerB = "Creature-0-6846-2991-2-256093-00000000D4"
local thornmawA = "Creature-0-6846-2991-2-256094-00000000E5"
local thornmawB = "Creature-0-6846-2991-2-256094-00000000F6"
local unknownMob = "Creature-0-6846-2991-2-256095-0000000107"

-- A stand-in for a secret value: only issecretvalue tells it apart.
local secrets = setmetatable({}, { __mode = "k" })
local function secret()
    local value = setmetatable({}, {
        __index = function()
            error("attempt to index a secret value", 2)
        end,
    })
    secrets[value] = true
    return value
end
rawset(_G, "issecretvalue", function(value)
    return secrets[value] == true
end)

-- What each unit token reads as right now; `combat` hides every creature.
local units, combat = {}, false
UnitName = function(unit)
    if unit == "player" then
        return "Mara"
    end
    local read = units[unit]
    if not read then
        return nil
    end
    return combat and secret() or read.name
end
rawset(_G, "UnitGUID", function(unit)
    local read = units[unit]
    if not read then
        return nil
    end
    return combat and secret() or read.guid
end)
GetServerTime = function()
    return clock
end
GetRealmName = function()
    return "CAMWOW EU5 Realm 10 RP"
end
UnitLevel = function()
    return 12
end
GetRealZoneText = function()
    return "Zephras Isle"
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

local corpse
rawset(_G, "GetNumLootItems", function()
    return 1
end)
rawset(_G, "GetLootSlotLink", function()
    return seed.link
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Zephyrseed", 1
end)
rawset(_G, "GetLootSourceInfo", function()
    return corpse, 1
end)

load.addon("Main", addon)
local event = client.event
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")

local looted = 0
-- Loots one seed from the given corpse and returns its gain.
local function loot(guid)
    corpse = guid
    clock = clock + 100
    event("LOOT_READY", false)
    event("LOOT_OPENED", false, false)
    event("CHAT_MSG_LOOT", "You receive loot: " .. seed.link)
    event("LOOT_CLOSED")
    looted = looted + 1
    bags = { { item = seed, count = looted } }
    event("BAG_UPDATE_DELAYED")
    local record = addon.store:find("257128:0")
    return record and record.gains[looted]
end

-- Out of combat: the target, a mouseover and a nameplate each show a creature.
units.target = { guid = prideclawA, name = "Prideclaw" }
event("PLAYER_TARGET_CHANGED")
units.mouseover = { guid = stalkerA, name = "Ridge Stalker" }
event("UPDATE_MOUSEOVER_UNIT")
units.nameplate3 = { guid = thornmawA, name = "Thornmaw" }
event("NAME_PLATE_UNIT_ADDED", "nameplate3")

-- In combat, the other spawns are looted while every unit read is secret.
combat = true
local gain = loot(prideclawB)
assert(gain and gain.source and gain.source.guid == prideclawB, "the corpse was not kept as the source")
assert(gain.source.name == "Prideclaw", "a name read from the target did not name another spawn")
assert(loot(stalkerB).source.name == "Ridge Stalker", "a name read on mouseover did not name another spawn")
assert(loot(thornmawB).source.name == "Thornmaw", "a name read from a nameplate did not name another spawn")

-- A creature never seen readable keeps its entry label.
gain = loot(unknownMob)
assert(gain.source.guid == unknownMob and gain.source.name == nil, "an unseen creature was named")
assert(addon.LastSeen.gainSourceText(gain) == "Mob #256095", "an unseen creature did not read by its entry")

-- Secret unit reads teach nothing and do not throw.
units.target = { guid = unknownMob, name = "Should Not Learn" }
event("PLAYER_TARGET_CHANGED")
assert(loot(unknownMob).source.name == nil, "a secret target read named a creature")

-- A player's name never names a creature.
combat = false
units.target = { guid = "Player-6846-0ABCDEF1", name = "Kel" }
event("PLAYER_TARGET_CHANGED")
units.target = nil
assert(loot(unknownMob).source.name == nil, "a player's name named a creature")

assert(addon.StoreRecordCheck.validRecord("257128:0", addon.store:find("257128:0")), "the record was rejected")
print("loot_combat_name_event_spec: passed")
