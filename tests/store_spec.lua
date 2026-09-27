local addon = {}
assert(loadfile("AzerothLedger/Item.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Schema.lua"))("AzerothLedger", addon)

local saved
local function open(raw)
    saved = raw
    return addon.Schema.open(raw, function(value)
        saved = value
    end)
end

local fresh = open(nil)
assert(fresh:diagnostic().kind == "healthy")
assert(saved.schema == 2)
assert(fresh:setMarker("reload-1"))
assert(fresh:marker() == "reload-1")
assert(fresh:setEnvironment({ build = "1.60.1.70009", interface = "16001", locale = "enUS", revision = "0.2.0" }))
assert(fresh:environment().locale == "enUS")

local link = "|Hitem:2672::::::::|h[Meat]|h"
assert(fresh:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 1234,
    complete = true,
    items = { { itemID = 2672, link = link, quantity = 1 } },
}))
local key = addon.Item.key(link, 2672)
assert(fresh:find(key).itemID == 2672)
local found = fresh:find(key)
found.links[1] = "changed"
assert(fresh:find(key).links[1] == link)

local damaged = open({ schema = 2, records = { bad = { itemID = -1 } }, areas = {} })
assert(damaged:diagnostic().kind == "damaged")
assert(#damaged:list() == 0)
local legacy = open({
    schema = 2,
    records = {
        ["2672:0"] = {
            key = "2672:0",
            itemID = 2672,
            firstSeen = 1000,
            lastSeen = 1000,
            firstSeenUnits = 0,
            totalGained = 2,
            gains = {
                {
                    id = "legacy:1",
                    at = 1001,
                    quantity = 1,
                    character = "Ada",
                    realm = "Realm",
                    level = 1,
                    place = "Unknown",
                    method = "Looted",
                },
            },
            links = { link },
            characters = { { name = "Ada", realm = "Realm", firstSeen = 1000, lastSeen = 1000, firstSeenUnits = 0 } },
            observations = { { character = "Ada", realm = "Realm", area = "bags", quantity = 2, seenAt = 1000 } },
        },
    },
    areas = {},
})
assert(legacy:diagnostic().kind == "damaged")
assert(legacy:find("2672:0").gains[1].id == "legacy:1")
local vendorEvidence = { nextID = 2, actions = { "damaged action" }, journal = {} }
local damagedVendor = open({ schema = 2, records = {}, areas = {}, vendor = vendorEvidence })
assert(damagedVendor:diagnostic().kind == "damaged")
assert(damagedVendor:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 1234,
    complete = true,
    items = {},
}))
assert(saved.vendor == vendorEvidence)
assert(not damagedVendor:pruneJournal(0))
local future = { schema = 9, records = {}, areas = {} }
local unsupported = open(future)
assert(unsupported:diagnostic().kind == "unsupported")
assert(not unsupported:setMarker("overwrite"))
assert(not unsupported:scan({}))
assert(saved == future)
local malformed = open({ schema = 2, records = "broken", areas = {} })
assert(malformed:diagnostic().kind == "damaged")
assert(not malformed:scan({}))

print("store_spec: passed")
