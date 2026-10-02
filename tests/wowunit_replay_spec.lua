local addon = {}
for _, source in ipairs({ "Item", "Schema", "Scan", "Reward", "Vendor", "Exchange", "Collection" }) do
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

local function frame()
    ---@type table<string, any>
    local result = { TitleText = { SetText = function() end }, shown = false }
    for _, method in ipairs({
        "SetSize",
        "SetPoint",
        "EnableMouse",
        "SetMovable",
        "RegisterForDrag",
        "SetScript",
        "SetFontObject",
        "SetJustifyH",
        "SetMaxLines",
        "SetFading",
        "EnableMouseWheel",
        "Clear",
        "AddMessage",
    }) do
        result[method] = function() end
    end
    function result:Show()
        self.shown = true
    end
    function result:Hide()
        self.shown = false
    end
    function result:IsShown()
        return self.shown
    end
    return result
end
CreateFrame = function()
    return frame()
end
UIParent = frame()
GameFontNormal = {}

assert(loadfile("AzerothLedger_Tests/Smoke.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Vendor.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Exchange.lua"))("AzerothLedger_Tests", {})
assert(loadfile("AzerothLedger_Tests/Evidence.lua"))("AzerothLedger_Tests", {})
for _, group in ipairs(groups) do
    for name, test in pairs(group) do
        test(group)
        print(name .. ": passed")
    end
end
