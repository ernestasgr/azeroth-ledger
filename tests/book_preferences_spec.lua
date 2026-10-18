local load = assert(loadfile("tests/support/addon.lua"))()
local function session(saved)
    local addon = {}
    load.addon("Settings", addon)
    local native = assert(loadfile("tests/support/native_ui.lua"))().create()
    local store = addon.Schema.open(saved, function(value)
        saved = value
    end)
    local frame = addon.Book.open(native.api, store, "Ada", "A")
    local function find(text)
        for index = #native.controls, 1, -1 do
            local control = native.controls[index]
            if control.text == text and control.kind == "Button" and control:IsVisible() then
                return control
            end
        end
        error("Missing button: " .. text)
    end
    return addon, native, store, frame, find, function()
        return saved
    end
end

date = os.date
local _, native, _, frame, find, saved = session(nil)
local addon, store
find("Got it"):Click()
for _, control in ipairs(native.controls) do
    if control.text == "?" and control.kind == "Button" then
        assert(control:GetFontString().width >= 16, "Help labels need readable positive width")
    end
end
find("Journal"):Click()
find("Collection"):Click()
find("Gallery"):Click()
find("Name A-Z"):Click()
find("Quantity: largest"):Click()
find("+"):Click()
-- Drag to a new position, then persist it on close.
for _, control in ipairs(native.controls) do
    if control.scripts.OnDragStop then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", native.api.UIParent, "CENTER", 80, -40)
        control.scripts.OnDragStop()
    end
end
frame:Hide()
local data = saved()
assert(data.book.filter.view == "Gallery" and data.book.filter.sort == "quantity")
assert(data.book.scale > 1)
assert(math.abs(data.book.x - 88) < 0.01 and math.abs(data.book.y + 44) < 0.01)
local records, areas = data.records, data.areas
addon, native, store, frame, find = session(data)
find("Quantity: largest")
assert(frame:GetScale() > 1)
assert(math.abs(frame.points[1].x - 80) < 0.01)
frame.scripts.OnKeyDown(frame, "F1")
find("Got it"):Click()
find("Settings"):Click() -- Safe when native Settings are unavailable.
addon.Book.toggle(native.api, store, "Ada", "A")
assert(not frame:IsShown())
addon.Book.toggle(native.api, store, "Ada", "A")
assert(frame:IsShown())
native.api.UIParent:SetSize(700, 500)
frame.scripts.OnEvent(frame, "DISPLAY_SIZE_CHANGED")
assert(frame:GetScale() * frame:GetWidth() <= 700)
assert(frame:GetScale() * frame:GetHeight() <= 500)
assert(data.records == records and data.areas == areas)

-- Corrupt fields fall back independently, without touching Collection data.
data.book = {
    version = 1,
    scale = 0 / 0,
    x = math.huge,
    y = "bad",
    filter = { view = "Bad", sort = "quantity", quality = 99, search = {} },
}
_, _, _, frame, find, saved = session(data)
find("Got it"):Click()
find("Quantity: largest")
assert(frame:GetScale() <= 1)
frame:Hide()
assert(saved().records == records)
-- Unknown preference versions stay untouched, even when the player closes the book.
data.book = { version = 99, precious = "keep" }
_, _, _, frame, _, saved = session(data)
frame:Hide()
assert(saved() == data and saved().book.precious == "keep")
print("book_preferences_spec: restoration, validation, display, toggle and help passed")

-- Native Settings buttons use the registered category and retain item facts.
addon, native, store, frame, find, saved = session({
    schema = 2,
    records = {},
    areas = {},
    book = {
        version = 1,
        guided = true,
        scale = 0.8,
        x = 100,
        y = 50,
        filter = { view = "Gallery", sort = "quantity" },
    },
})
local buttons, opened, registeredSettings = {}, nil, {}
local category = {
    GetID = function()
        return 59
    end,
}
native.api.UnitName = function()
    return "Ada"
end
native.api.GetRealmName = function()
    return "A"
end
native.api.Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    CreateColorSwatch = function() end,
    RegisterVerticalLayoutSubcategory = function()
        return {}, { AddInitializer = function() end }
    end,
    RegisterVerticalLayoutCategory = function()
        return category, { AddInitializer = function() end }
    end,
    RegisterProxySetting = function(_, name, _, _, _, get, set)
        registeredSettings[name] = { get = get, set = set }
        return {}
    end,
    CreateSliderOptions = function()
        return {}
    end,
    CreateSlider = function() end,
    CreateCheckbox = function() end,
    RegisterAddOnCategory = function(value)
        assert(value == category)
    end,
    OpenToCategory = function(id)
        opened = id
    end,
}
native.api.CreateSettingsButtonInitializer = function(name, _, callback)
    buttons[name] = callback
    return {}
end
assert(addon.Settings.register(native.api, store))
local developerSetting = assert(registeredSettings.AzerothLedger_developerMode)
assert(developerSetting.get() == false, "Developer mode should be off by default")
developerSetting.set(true)
assert(developerSetting.get() == true and saved().book.developerMode == true)
find("Settings"):Click()
assert(opened == 59)
assert(not frame:IsShown(), "Opening native Settings should uncover the Settings panel")
frame:Hide()
buttons["Open Ledger"]()
assert(frame:IsShown())
buttons["Reset book layout"]()
assert(frame:GetScale() == 1 and frame.points[1].x == 0 and frame.points[1].y == 0)
buttons["Reset browsing preferences"]()
find("Name A-Z")
frame:Hide()
assert(saved().book.filter.sort == nil)
assert(next(saved().records) == nil and next(saved().areas) == nil)
local _, _, restoredDeveloperStore = session(saved())
assert(restoredDeveloperStore:book().developerMode, "Developer mode should persist across reload")
local unknown = { schema = 99, records = {}, areas = {}, book = { version = 1, scale = 0.8 } }
_, _, _, frame, _, saved = session(unknown)
frame:Hide()
assert(saved() == unknown and unknown.book.scale == 0.8)
print("book_preferences_spec: native Settings navigation, resets and unsupported ledger protection passed")

-- Journal action values and a keybinding pressed during first-use help survive the native boundary.
local reloadData = { schema = 2, records = {}, areas = {} }
local _, _, _, firstFrame = session(reloadData)
firstFrame.scripts.OnKeyDown(firstFrame, "L")
assert(firstFrame.propagate, "Help must allow the player's assigned Ledger binding to reach WoW")
for _, action in ipairs({
    "Looted",
    "Quest reward",
    "Crafted",
    "Purchase",
    "Auction purchase",
    "Mail",
    "Trade",
    "Obtained (way unknown)",
    "Alt mail",
    "Alt trade",
    "Sale",
    "Refund",
    "Buyback",
}) do
    local _, _, _, actionFrame, actionFind, actionSaved = session({
        schema = 2,
        records = {},
        areas = {},
        book = { version = 1, guided = true, filter = { view = "Journal" } },
    })
    actionFind("All activity"):Click()
    while not pcall(actionFind, action) do
        actionFind("Next"):Click()
    end
    actionFind(action):Click()
    actionFrame:Hide()
    local _, _, _, _, restoredFind = session(actionSaved())
    restoredFind(action)
end
print("book_preferences_spec: all Journal action filters and help key propagation passed")
