local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("BookWidgets")
AzerothLedger = addon
date = os.date
local native = assert(loadfile("tests/support/native_ui.lua"))().create()
CreateFrame = native.api.CreateFrame
local groups = {}
local assertions = {
    AreEqual = function(expected, actual)
        assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
    end,
    IsTrue = function(value)
        assert(value)
    end,
}
WoWUnit = setmetatable(assertions, {
    __call = function(_, name)
        groups[name] = groups[name] or {}
        return groups[name]
    end,
})
local companion = {}
for _, name in ipairs({ "CollectionFixture", "CollectionSources", "CollectionDetails", "Collection" }) do
    assert(loadfile("AzerothLedger_Tests/" .. name .. ".lua"))("AzerothLedger_Tests", companion)
end
for _, group in pairs(groups) do
    for name, test in pairs(group) do
        test(group)
        print(name .. ": passed")
    end
end
