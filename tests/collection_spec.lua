local addon = {}
assert(loadfile("AzerothLedger/Item.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Schema.lua"))("AzerothLedger", addon)

local function equal(expected, actual)
    assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
end

local saved
local store = addon.Schema.open(nil, function(value)
    saved = value
end)

local plain = "|cff00ff00|Hitem:2672::::::::|h[Meat]|h|r"
local enchanted = "|cff00ff00|Hitem:2672:123:456::::::|h[Meat]|h|r"
local bear = "|cffa335ee|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword]|h|r"
local bearGemmed = "|cffa335ee|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword]|h|r"
local wolf = "|cffa335ee|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword]|h|r"

local function scan(character, realm, area, seenAt, complete, items)
    assert(store:scan({
        character = character,
        realm = realm,
        area = area,
        seenAt = seenAt,
        complete = complete,
        items = items,
    }))
end

scan("Ada", "Realm A", "bags", 1000, true, { { itemID = 2672, link = plain, quantity = 400 } })
equal(1, #store:list())
local meat = store:list()[1]
equal(400, meat.firstSeenUnits)
equal(0, meat.totalGained)
equal(nil, meat.firstGained)
equal(nil, meat.lastGained)
equal(1000, meat.firstSeen)
equal(400, meat.observations[1].quantity)
scan("Ada", "Realm A", "bags", 1000, true, { { itemID = 2672, link = plain, quantity = 400 } })
equal(1, #store:list()[1].observations)
scan("Ada", "Realm A", "bank", 1100, false, {})
equal(false, store:area("Ada", "Realm A", "bank").complete)
equal(1, #store:list()[1].observations)
scan("Ada", "Realm A", "bags", 1200, true, { { itemID = 2672, link = enchanted, quantity = 399 } })
meat = store:list()[1]
equal(2, #meat.links)
equal(1200, meat.lastSeen)
equal(2, #meat.observations)

scan("Ada", "Realm A", "equipped", 1300, true, { { itemID = 100, link = bear, quantity = 1 } })
scan("Ben", "Realm B", "equipped", 1400, true, {
    { itemID = 100, link = bearGemmed, quantity = 1 },
    { itemID = 100, link = wolf, quantity = 1 },
})
equal(3, #store:list())
local variants = {}
for _, record in ipairs(store:list()) do
    if record.itemID == 100 then
        variants[#variants + 1] = record
    end
end
equal(2, #variants)
local shared = variants[1].firstSeen == 1300 and variants[1] or variants[2]
equal(2, #shared.links)
equal(2, #shared.characters)
equal(1, shared.firstSeenUnits)
equal(0, shared.totalGained)

local restored = addon.Schema.open(saved, function(value)
    saved = value
end)
equal(3, #restored:list())
equal(2, #restored:find(shared.key).characters)
equal(false, restored:area("Ada", "Realm A", "bank").complete)

print("collection_spec: passed")
