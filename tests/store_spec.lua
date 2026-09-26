local addon = {}
assert(loadfile("AzerothLedger/Schema.lua"))("AzerothLedger", addon)

-- Compares a test result with an independent expected value.
local function equal(expected, actual)
    assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
end

local saved
-- Opens the schema store with a test persistence callback.
local function open(raw)
    saved = raw
    return addon.Schema.open(raw, function(nextValue)
        saved = nextValue
    end)
end

local fresh = open(nil)
equal("healthy", fresh:diagnostic().kind)
equal(1, saved.schema)
assert(fresh:setMarker("reload-1"))
equal("reload-1", saved.marker)
equal(1, saved.schema)
assert(fresh:setEnvironment({ build = "1.60.1.70009", interface = "16001", locale = "enUS", revision = "0.1.0" }))
equal("enUS", fresh:environment().locale)
assert(fresh:recordSeen(2672, 1234))
equal(2672, fresh:find(2672).itemID)
equal(1234, fresh:find(2672).firstSeen)
equal(1, #fresh:list())

local original = {
    schema = 1,
    marker = "saved",
    records = {
        ["2672"] = { itemID = 2672, firstSeen = 1234 },
        ["bad"] = { itemID = -1, firstSeen = "wrong" },
    },
}
local damaged = open(original)
equal("damaged", damaged:diagnostic().kind)
equal(1, damaged:diagnostic().damagedCount)
equal(1, #damaged:list())
assert(damaged:recordSeen(4865, 2345))
equal(original.records.bad, saved.records.bad)
equal(2, #damaged:list())
equal(nil, damaged:find(9999))
local found = damaged:find(2672)
found.firstSeen = 9999
equal(1234, damaged:find(2672).firstSeen)

local future = { schema = 9, marker = "future", records = {} }
local unsupported = open(future)
equal("unsupported", unsupported:diagnostic().kind)
equal(false, unsupported:setMarker("overwrite"))
equal(false, unsupported:recordSeen(2672, 1234))
equal(future, saved)

local malformed = open({ schema = 1, records = "broken" })
equal("damaged", malformed:diagnostic().kind)
equal(false, malformed:recordSeen(2672, 1234))

local invalidNumbers = open({ schema = 1, records = { ["2672"] = { itemID = math.huge, firstSeen = 1 } } })
equal("damaged", invalidNumbers:diagnostic().kind)
equal(0, #invalidNumbers:list())

local emptyMarker = open({ schema = 1, marker = "", records = {} })
equal("damaged", emptyMarker:diagnostic().kind)
equal(nil, emptyMarker:marker())

local futureEnvironment = open({
    schema = 9,
    environment = { build = "future", interface = "99999", locale = "enUS", revision = "9.0.0" },
    records = {},
})
equal(nil, futureEnvironment:environment())

print("store_spec: passed")
