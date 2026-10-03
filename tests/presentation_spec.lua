local addon = {}
for _, source in ipairs({ "Item", "Schema", "Collection", "Presentation", "Settings" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end

-- Exercise only the native boundary; all decisions still use the real store.
local native = assert(loadfile("tests/support/native_ui.lua"))().create()
local api = native.api
local postCall
api.Enum = { TooltipDataType = { Item = 0 } }
api.TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, callback)
        assert(kind == 0)
        postCall = callback
    end,
}
api.UnitName = function()
    return "Ada"
end
api.GetRealmName = function()
    return "Realm"
end
local store = addon.Schema.open(nil, function() end)
local link = "|Hitem:4540::::::::|h[Bread]|h"
local key = addon.Item.key(link, 4540)
local function bags(at, quantity)
    assert(store:scan({
        character = "Ada",
        realm = "Realm",
        area = "bags",
        complete = true,
        seenAt = at,
        items = quantity > 0 and { { itemID = 4540, link = link, quantity = quantity } } or {},
    }))
end
local function buy(at)
    assert(
        store:vendorAction(
            { kind = "purchase", key = key, itemID = 4540, link = link, quantity = 1 },
            at,
            { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
        )
    )
end
assert(addon.Presentation.register(api, store))
local regions, currentLink = {}, nil
local tooltip = {
    GetItem = function()
        return nil, currentLink
    end,
    GetRegions = function()
        return unpack(regions)
    end,
    IsForbidden = function()
        return false
    end,
    AddLine = function(_, text)
        regions[#regions + 1] = {
            GetText = function()
                return text
            end,
        }
    end,
}
bags(1000, 0)
buy(1001)
bags(1002, 1)
postCall(tooltip) -- Uncached item: no full link yet.
assert(#regions == 0)
currentLink = link
postCall(tooltip)
postCall(tooltip)
assert(#regions == 1)
regions = {} -- Native asynchronous ClearLines and rebuild.
postCall(tooltip)
postCall(tooltip)
assert(#regions == 1)
assert(store:setDisplay("tooltips", false))
regions = {}
postCall(tooltip)
assert(#regions == 0)
assert(store:setDisplay("tooltips", true))
postCall(tooltip)
assert(#regions == 1)
local driver, toast = native.controls[2], native.controls[3]
local update = driver.scripts.OnUpdate
assert(not toast.shown)
update(driver, 0.1)
assert(toast.shown)
local announced = false
for _, control in ipairs(native.controls) do
    announced = announced or control.text == link
end
assert(announced)
update(driver, 6)
assert(not toast.shown)
buy(1003)
bags(1004, 2)
update(driver, 0.1)
assert(not toast.shown)
assert(store:setDisplay("toasts", false))
update(driver, 0.1)
print("native presentation boundary: passed")
AzerothLedger = addon
date = os.date
local group
WoWUnit = setmetatable({
    AreEqual = function(expected, actual)
        assert(expected == actual, tostring(expected) .. " ~= " .. tostring(actual))
    end,
    IsTrue = function(value)
        assert(value)
    end,
}, {
    __call = function()
        group = {}
        return group
    end,
})
assert(loadfile("AzerothLedger_Tests/Presentation.lua"))()
for name, test in pairs(group) do
    test(group)
    print(name .. ": passed")
end
