local load = assert(loadfile("tests/support/addon.lua"))()
-- An item's evidence summary says its gain has a specific source exactly when
-- its Source reads as something other than Unknown.
local addon = load.addon("Collection")
date = os.date

local link = "|cnIQ1:|Hitem:2455::::::::15:1482:::::::::|h[Minor Mana Potion]|h|r"
local function saved(gain)
    gain.id, gain.at, gain.quantity = "gain:1", 100, 1
    gain.character, gain.realm, gain.level, gain.place, gain.placeKind = "Mara", "Realm", 15, "Stormwind City", "zone"
    return {
        schema = 2,
        areas = {},
        records = {
            ["2455:0"] = {
                key = "2455:0",
                itemID = 2455,
                firstSeen = 100,
                lastSeen = 100,
                firstSeenUnits = 0,
                totalGained = 1,
                firstGained = 100,
                lastGained = 100,
                links = { link },
                characters = {
                    { name = "Mara", realm = "Realm", firstSeen = 100, lastSeen = 100, firstSeenUnits = 0 },
                },
                observations = { { character = "Mara", realm = "Realm", area = "bags", seenAt = 100, quantity = 1 } },
                gains = { gain },
            },
        },
    }
end

local function evidence(gain)
    local store = addon.Schema.open(saved(gain), function() end)
    local detail = assert(addon.Collection.inspect(store, "2455:0", "Mara", "Realm"), "the record must load")
    return detail.evidence
end

local specific = "Confirmed gain with specific source"
assert(
    evidence({ method = "Obtained", channel = "mail", mailKind = "auction-purchase" }) == specific,
    "an auction purchase names its source"
)
assert(evidence({ method = "Obtained", source = { kind = "npc", name = "Advisor Emerson" } }) == specific)
assert(evidence({ method = "Obtained" }) == "Confirmed Obtained gain; source Unknown")

print("collection_source_strength_spec: passed")
