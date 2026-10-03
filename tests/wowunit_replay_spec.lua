local addon = {}
for _, source in ipairs({
    "Item",
    "Schema",
    "Client",
    "Scan",
    "Loot",
    "Reward",
    "Vendor",
    "Exchange",
    "Collection",
    "Journal",
    "BookWidgets",
    "Book",
    "Settings",
}) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
AzerothLedger = addon
date = os.date

local groups = {}
WoWUnit = setmetatable({}, {
    __call = function()
        local group = {}
        groups[#groups + 1] = group
        return group
    end,
})
WoWUnit.AreEqual = function(expected, actual)
    assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
end
WoWUnit.IsTrue = function(value)
    assert(value)
end

local native = assert(loadfile("tests/support/native_ui.lua"))().create()
CreateFrame = native.api.CreateFrame
UIParent = native.api.UIParent
GameFontNormal = {}

assert(loadfile("AzerothLedger_Tests/Smoke.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Vendor.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Exchange.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Evidence.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Collection.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Journal.lua"))("AzerothLedger_Tests", {})
for _, group in ipairs(groups) do
    for name, test in pairs(group) do
        test(group)
        print(name .. ": passed")
    end
end
