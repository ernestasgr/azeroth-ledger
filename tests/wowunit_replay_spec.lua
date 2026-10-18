local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("Settings")
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

SlashCmdList = {}
load.companion("Performance")
for _, group in ipairs(groups) do
    for name, test in pairs(group) do
        test(group)
        print(name .. ": passed")
    end
end
