local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("Settings")
AzerothLedger = addon
date = os.date

local wowunit = assert(loadfile("tests/support/wowunit.lua"))()

local native = assert(loadfile("tests/support/native_ui.lua"))().create()
CreateFrame = native.api.CreateFrame
UIParent = native.api.UIParent
GameFontNormal = {}

SlashCmdList = {}
load.companion("Performance")
for _, group in ipairs(wowunit.groups) do
    -- The Forever group needs a booted client; wowunit_forever_spec replays it.
    if group.name ~= "AzerothLedgerForever" then
        for name, test in pairs(group.tests) do
            test(group.tests)
            print(name .. ": passed")
        end
    end
end
