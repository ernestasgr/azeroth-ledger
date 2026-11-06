local load = assert(loadfile("tests/support/addon.lua"))()
-- An item an NPC handed over, or one taken from an NPC by interacting with it,
-- is Obtained, and its Source can name that NPC. Loot never names an NPC this way:
-- its source is the looted creature, object or item.
local addon = load.addon("StoreRecordCheck")
local validRecord = addon.StoreRecordCheck.validRecord

local link = "|cnIQ1:|Hitem:266434::::::::8:1482:::::::::|h[Resaan's Heirloom]|h|r"
local function record(method, source)
    return {
        key = "266434:0",
        itemID = 266434,
        firstSeen = 100,
        lastSeen = 100,
        firstSeenUnits = 0,
        totalGained = 1,
        firstGained = 100,
        lastGained = 100,
        links = { link },
        characters = { { name = "Mara", realm = "Realm", firstSeen = 100, lastSeen = 100, firstSeenUnits = 0 } },
        observations = { { character = "Mara", realm = "Realm", area = "bags", seenAt = 100, quantity = 1 } },
        gains = {
            {
                id = "npc:1",
                at = 100,
                quantity = 1,
                character = "Mara",
                realm = "Realm",
                level = 8,
                place = "Zephras Isle",
                placeKind = "zone",
                method = method,
                source = source,
            },
        },
    }
end

local npc = { kind = "npc", name = "Resaan Nimbuswalker" }
assert(validRecord("266434:0", record("Obtained", npc)), "an Obtained gain may name the NPC")
assert(not validRecord("266434:0", record("Obtained", { kind = "npc" })), "an NPC source needs a name")
assert(
    not validRecord("266434:0", record("Obtained", { kind = "npc", name = "Resaan", guid = "Creature-0-1-2-3-4-5" })),
    "an NPC source carries only its name"
)
assert(not validRecord("266434:0", record("Looted", npc)), "loot names the looted creature, not an NPC")

print("obtained_npc_source_spec: passed")
