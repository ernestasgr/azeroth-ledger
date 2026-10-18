-- A WoWUnit stand-in for replaying the companion's groups offline. Groups are
-- kept by name in registration order; assertions raise like WoWUnit's.
local groups = {}
local named = {}

WoWUnit = setmetatable({}, {
    __call = function(_, name)
        local group = {}
        groups[#groups + 1] = { name = name, tests = group }
        named[name] = group
        return group
    end,
})
WoWUnit.AreEqual = function(expected, actual)
    assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
end
WoWUnit.IsTrue = function(value)
    assert(value)
end

return { groups = groups, named = named }
