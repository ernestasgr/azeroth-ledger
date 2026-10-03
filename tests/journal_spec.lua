local addon = {}
for _, source in ipairs({ "Item", "Schema", "Client", "Collection", "Journal", "Settings" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
AzerothLedger = addon
local groups = {}
WoWUnit = setmetatable({
    AreEqual = function(expected, actual)
        assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
    end,
    IsTrue = function(value)
        assert(value)
    end,
}, {
    __call = function(_, name)
        groups[name] = groups[name] or {}
        return groups[name]
    end,
})
assert(loadfile("AzerothLedger_Tests/Journal.lua"))()
for _, group in pairs(groups) do
    for name, test in pairs(group) do
        test(group)
        print(name .. ": passed")
    end
end
