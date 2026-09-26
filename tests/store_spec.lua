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
