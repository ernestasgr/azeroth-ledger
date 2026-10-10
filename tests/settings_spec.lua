local addon = {}
_G.date = os.date
for _, name in ipairs({
    "Item",
    "Work",
    "Schema",
    "Client",
    "LastSeen",
    "Collection",
    "Journal",
    "BookWidgets",
    "BookQuery",
    "Book",
    "Presentation",
    "Settings",
}) do
    assert(loadfile("AzerothLedger/" .. name .. ".lua"))("AzerothLedger", addon)
end
local native = assert(loadfile("tests/support/native_ui.lua"))().create()
local api = native.api
local controls, buttons, swatches, sections, notifications = {}, {}, {}, {}, 0
local category = {
    GetID = function()
        return 51
    end,
}
api.UnitName = function()
    return "Ada"
end
api.GetRealmName = function()
    return "Realm"
end
api.Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    RegisterVerticalLayoutCategory = function()
        return category, { AddInitializer = function() end }
    end,
    RegisterVerticalLayoutSubcategory = function(parent, name)
        assert(parent == category)
        sections[name] = true
        return { name = name }, { AddInitializer = function() end }
    end,
    RegisterProxySetting = function(_, variable, kind, name, default, get, set)
        controls[variable] = { kind = kind, name = name, default = default, get = get, set = set }
        return variable
    end,
    CreateCheckbox = function() end,
    CreateSliderOptions = function(minimum, maximum, step)
        assert(minimum < maximum and step > 0)
        return {}
    end,
    CreateSlider = function() end,
    CreateColorSwatch = function(_, variable)
        assert(controls[variable].kind == "string")
        swatches[#swatches + 1] = variable
    end,
    NotifyUpdate = function(variable)
        assert(controls[variable])
        notifications = notifications + 1
    end,
    RegisterAddOnCategory = function(value)
        assert(value == category)
    end,
}
api.CreateSettingsButtonInitializer = function(name, _, callback)
    buttons[name] = callback
    return {}
end
api.CreateSettingsListSectionHeaderInitializer = function()
    return {}
end
local saved
local store = addon.Schema.open(nil, function(value)
    saved = value
end)
assert(store:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    complete = true,
    seenAt = 1000,
    items = { { itemID = 4540, link = "|Hitem:4540::::::::|h[Bread]|h", quantity = 2 } },
}))
local records, areas, journal = saved.records, saved.areas, saved.journal
assert(addon.Settings.register(api, store))
assert(sections.Appearance and sections.Notifications and sections.Tooltips and #swatches == 9)
local frame = addon.Book.open(api, store, "Ada", "Realm")
local function set(key, value)
    controls["AzerothLedger_" .. key].set(value)
end
local function get(key)
    return controls["AzerothLedger_" .. key].get()
end
local title
for _, region in ipairs(native.controls) do
    if region.kind == "FontString" and region.text == "Azeroth Ledger" then
        title = region
    end
end
assert(title)
local old = get("gold")
set("gold", "ff3377cc")
assert(math.abs(title.textColor[1] - 0.2) < 0.001, "The existing window should recolor without rebuilding")
set("gold", old) -- The native picker delivers the previous color on Cancel.
assert(get("gold") == old)
set("gold", "invalid")
assert(get("gold") == old)
set("windowScale", 0.75)
assert(frame:GetScale() == 0.75)
local moves = 0
frame.StartMoving = function()
    moves = moves + 1
end
local drag
for _, region in ipairs(native.controls) do
    if region.scripts.OnDragStart then
        drag = region.scripts.OnDragStart
    end
end
set("lockWindow", true)
drag()
assert(moves == 0)
set("lockWindow", false)
drag()
assert(moves == 1)
set("reducedMotion", true)
assert(frame.alpha == 1)
local group = frame.ledgerFade
if group then
    assert(not group.playing)
end
addon.Book.toggle(api, store, "Ada", "Realm")
addon.Book.toggle(api, store, "Ada", "Realm")
if group then
    assert(not group.playing)
end
set("backgroundOpacity", 0.5)
for _, region in ipairs(native.controls) do
    if region.parent == frame and region.kind == "Texture" and region.width == 1100 and region.height == 700 then
        assert(region.color[4] == 0.5)
    end
end
set("qualityColors", false)
assert(
    addon.BookWidgets.quality({ ITEM_QUALITY_COLORS = { [4] = { r = 0.8, g = 0, b = 1 } } }, 4)
        == addon.BookWidgets.colors.text
)
buttons["Frost blue"]()
assert(get("gold") == "ff73c7ff")
set("toastDuration", 12)
set("tooltipDetails", false)
buttons["High contrast"]()
assert(get("backgroundOpacity") == 1 and get("text") == "ffffffff")
assert(get("toastDuration") == 12 and get("tooltipDetails") == false)
local function luminance(color)
    local channels = {}
    for index = 1, 3 do
        local value = color[index]
        channels[index] = value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
    end
    return channels[1] * 0.2126 + channels[2] * 0.7152 + channels[3] * 0.0722
end
for _, name in ipairs({
    "Alliance blue",
    "Horde crimson",
    "Druid grove",
    "Arcane violet",
    "Fel green",
    "Parchment",
    "Midnight",
}) do
    set("qualityColors", true)
    buttons[name]()
    local values = store:display()
    for _, background in ipairs({ "canvas", "panel", "raised", "selected" }) do
        for _, foreground in ipairs({ "text", "muted", "gold", "green" }) do
            local light, dark = luminance(values[foreground]), luminance(values[background])
            local contrast = (math.max(light, dark) + 0.05) / (math.min(light, dark) + 0.05)
            assert(contrast >= 4.5, name .. " needs readable " .. foreground .. " on " .. background)
        end
    end
    assert(values.qualityColors == (name ~= "Parchment"))
    assert(get("toastDuration") == 12 and get("tooltipDetails") == false and get("backgroundOpacity") == 1)
end
buttons["Reset appearance"]()
assert(get("windowScale") == 1 and get("reducedMotion") == false and get("gold") == old)
assert(get("toastDuration") == 12)
buttons["Reset notifications"]()
assert(get("toastDuration") == 5 and get("tooltipDetails") == false)
assert(not addon.Presentation.line(store, "|Hitem:4540::::::::|h[Bread]|h", "Ada", "Realm"):find("\n", 1, true))
buttons["Reset tooltips"]()
assert(get("tooltipDetails") == true and notifications > 0)
set("gold", "ff123456")
set("toastScale", 1.3)
frame:Hide()
local restored = addon.Schema.open(saved, function() end)
assert(restored:display().gold[1] == 18 / 255 and restored:display().toastScale == 1.3)
assert(saved.records == records and saved.areas == areas and saved.journal.gains == journal.gains)
assert(saved.journal.nextSequence == journal.nextSequence)
local display = restored:display()
display.gold[1] = 1
assert(restored:display().gold[1] == 18 / 255, "Display reads must not expose mutable saved colors")
for _, pair in ipairs({
    { "toastDuration", 0 / 0 },
    { "toastScale", math.huge },
    { "backgroundOpacity", 0 },
    { "gold", { 1, 0, 0, 0.5 } },
    { "toasts", "yes" },
    { "bogus", true },
}) do
    assert(not restored:setDisplay(pair[1], pair[2]))
end
local oldSave = {
    schema = 2,
    records = {},
    areas = {},
    display = { tooltips = false, toasts = false, toastScale = "bad", gold = { 0 / 0, 0, 0, 1 } },
}
local normalized = addon.Schema.open(oldSave, function() end):display()
assert(
    normalized.tooltips == false
        and normalized.toasts == false
        and normalized.toastScale == 1
        and normalized.gold[1] == 0.87
)
local future = { schema = 99, display = { gold = { 1, 0, 0, 1 } } }
assert(not addon.Schema
    .open(future, function()
        error("Unsupported saves must stay untouched")
    end)
    :setDisplay("gold", { 0, 1, 0, 1 }))
print("settings_spec: live colors, presets, resets, layout, motion, reload and validation passed")
