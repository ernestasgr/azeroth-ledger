local addon = {}
_G.date = os.date
for _, source in ipairs({
    "Item",
    "Work",
    "Client",
    "Schema",
    "LastSeen",
    "Collection",
    "Presentation",
    "BookWidgets",
    "BookQuery",
    "Book",
    "Settings",
}) do
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
api.TooltipUtil = {
    GetDisplayedItem = function(tooltip)
        return nil, tooltip:GetPrimaryTooltipData().hyperlink
    end,
}
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
    -- Native comparison tooltips have TooltipDataHandlerMixin, without GetItem.
    GetPrimaryTooltipData = function()
        return { hyperlink = currentLink }
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
assert(toast.scripts.OnClick, "A new-discovery toast should open its Collection entry when clicked")
local announced = false
for _, control in ipairs(native.controls) do
    announced = announced or control.text == link
end
assert(announced)
toast.scripts.OnClick(toast, "LeftButton")
local book
for _, control in ipairs(native.controls) do
    if control.name == "AzerothLedgerCollection" then
        book = control
        break
    end
end
assert(book and book:IsShown(), "Clicking the discovery toast should open the Ledger")
book.scripts.OnUpdate(book, 0)
local discoveryTab, selectedItem
for _, control in ipairs(native.controls) do
    if control.text == "Discoveries" and control.kind == "Button" then
        discoveryTab = control
    elseif control.key == key and control.kind == "Button" then
        selectedItem = control
    end
end
assert(discoveryTab and discoveryTab.selected, "Clicking the discovery toast should open Discoveries")
assert(selectedItem and selectedItem.selected, "Clicking the discovery toast should select the discovered item")
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

-- Combat pauses a committed discovery; previewing never creates a ledger fact.
local second = assert(loadfile("tests/support/native_ui.lua"))().create()
local secondApi = second.api
local secondStore = addon.Schema.open(nil, function() end)
secondApi.UnitName, secondApi.GetRealmName = api.UnitName, api.GetRealmName
secondApi.Enum, secondApi.TooltipUtil = api.Enum, api.TooltipUtil
secondApi.TooltipDataProcessor = { AddTooltipPostCall = function() end }
local combat, sounds = true, 0
secondApi.InCombatLockdown = function()
    return combat
end
secondApi.SOUNDKIT = { UI_EPICLOOT_TOAST = 31578 }
secondApi.PlaySound = function(sound, channel)
    assert(sound == 31578 and channel == "SFX")
    sounds = sounds + 1
end
assert(secondStore:setDisplay("toastCombat", false))
assert(secondStore:setDisplay("toastSound", true))
assert(secondStore:setDisplay("toastDuration", 9))
assert(secondStore:setDisplay("toastScale", 1.4))
assert(secondStore:setDisplay("toastX", 800))
assert(secondStore:setDisplay("toastY", 800))
assert(secondStore:setDisplay("qualityColors", false))
assert(addon.Presentation.register(secondApi, secondStore))
local secondDriver, secondToast = second.controls[2], second.controls[3]
local tick = secondDriver.scripts.OnUpdate
local function scanSecond(quantity, at)
    assert(secondStore:scan({
        character = "Ada",
        realm = "Realm",
        area = "bags",
        complete = true,
        seenAt = at,
        items = quantity > 0 and { { itemID = 4540, link = "|cffffffff" .. link .. "|r", quantity = quantity } } or {},
    }))
end
scanSecond(0, 1000)
assert(
    secondStore:vendorAction(
        { kind = "purchase", key = key, itemID = 4540, link = link, quantity = 1 },
        1001,
        { character = "Ada", realm = "Realm", level = 12, place = "Elwynn" }
    )
)
scanSecond(1, 1002)
tick(secondDriver, 30)
assert(not secondToast:IsShown() and sounds == 0)
combat = false
tick(secondDriver, 0.1)
assert(secondToast:IsShown() and sounds == 1 and secondToast:GetScale() == 1.4)
local inkName
for _, region in ipairs(second.controls) do
    if region.parent == secondToast and region.kind == "FontString" and region.text == link then
        inkName = region
    end
end
assert(inkName, "Notification item names should use the theme's text color when quality colors are disabled")
tick(secondDriver, 6)
assert(secondToast:IsShown(), "The customized duration must exceed the default five seconds")
combat = true
tick(secondDriver, 20)
assert(not secondToast:IsShown())
combat = false
tick(secondDriver, 0.1)
assert(secondToast:IsShown() and sounds == 1, "Resuming a notification must not repeat its sound")
tick(secondDriver, 3)
assert(not secondToast:IsShown())
assert(secondStore:setDisplay("toasts", false))
addon.Presentation.preview(secondStore)
assert(secondToast:IsShown())
local before = secondStore:describe(key).totalGained
tick(secondDriver, 0.1)
assert(secondToast:IsShown(), "Preview must work while actual notifications are muted")
secondToast.scripts.OnClick()
assert(not secondToast:IsShown() and secondStore:describe(key).totalGained == before)
assert(#secondStore:takeDiscoveries() == 0)
secondApi.UIParent:SetSize(700, 500)
secondDriver.scripts.OnEvent()
assert(math.abs(secondToast.points[1].x) <= (700 - 340 * 1.4) / 2)
assert(-secondToast.points[1].y <= 500 - 64 * 1.4)
print("presentation_spec: notification duration, sound, combat pause, preview and screen bounds passed")
