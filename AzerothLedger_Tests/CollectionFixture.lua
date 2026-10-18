local _, companion = ...
local addon = AzerothLedger

-- Shared Collection test items and stores for the AzerothLedgerCollection group.
local meat = "|Hitem:2672::::::::|h[Meat]|h"
local bear = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h"
local enchanted = "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h"
local wolf = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h"

-- Ada on realm A plays unless a test logs in as another character.
local function fixture(playing, playingRealm)
    local writes = 0
    local store = addon.Schema.open(nil, function()
        writes = writes + 1
    end)
    WoWUnit.IsTrue(store:setCharacter(playing or "Ada", playingRealm or "A"))
    local function scan(character, realm, area, at, items, complete)
        WoWUnit.IsTrue(store:scan({
            character = character,
            realm = realm,
            area = area,
            seenAt = at,
            complete = complete ~= false,
            items = items,
        }))
    end
    scan("Ada", "A", "bags", 1000, { { itemID = 2672, link = meat, quantity = 400 } })
    scan("Ada", "A", "equipped", 1000, { { itemID = 100, link = bear, quantity = 1 } })
    scan("Ben", "B", "bags", 1001, {
        { itemID = 100, link = enchanted, quantity = 1 },
        { itemID = 100, link = wolf, quantity = 1 },
    })
    return store, scan, function()
        return writes
    end
end

local function metadata(record)
    return { category = record.itemID == 100 and "Weapons" or "Materials" }
end

companion.collection = {
    meat = meat,
    bear = bear,
    enchanted = enchanted,
    wolf = wolf,
    fixture = fixture,
    metadata = metadata,
}
