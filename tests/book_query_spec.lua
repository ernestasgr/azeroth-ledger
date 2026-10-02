local addon = {}
for _, source in ipairs({ "Item", "Schema", "Client", "Collection" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
AzerothLedger = addon
date = os.date
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
assert(loadfile("AzerothLedger_Tests/Collection.lua"))()
for _, group in pairs(groups) do
    for name, test in pairs(group) do
        test(group)
        print(name .. ": passed")
    end
end
