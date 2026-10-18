local _, addon = ...
local SettingsPanel = {}
local registeredCategory

function SettingsPanel.open(api)
    if registeredCategory and api.Settings and type(api.Settings.OpenToCategory) == "function" then
        api.Settings.OpenToCategory(registeredCategory:GetID())
        return true
    end
    return false
end

local function hex(color)
    return string.format(
        "ff%02x%02x%02x",
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5)
    )
end

local function fromHex(value)
    if type(value) ~= "string" or not value:match("^ff%x%x%x%x%x%x$") then
        return nil
    end
    return {
        tonumber(value:sub(3, 4), 16) / 255,
        tonumber(value:sub(5, 6), 16) / 255,
        tonumber(value:sub(7, 8), 16) / 255,
        1,
    }
end

local themes = {
    {
        name = "Alliance blue",
        description = "Royal blue panels with gold accents and bright ivory text.",
        colors = {
            canvas = "0c1424",
            panel = "142039",
            raised = "1c2d4b",
            edge = "435a7b",
            text = "f4f1e8",
            muted = "b3c3d9",
            gold = "efc76b",
            selected = "293e60",
            green = "94d7a4",
        },
    },
    {
        name = "Horde crimson",
        description = "Charcoal and deep crimson with warm red highlights.",
        colors = {
            canvas = "170c0e",
            panel = "251216",
            raised = "361b20",
            edge = "6f3c44",
            text = "f8ece5",
            muted = "d0aaa9",
            gold = "ff9784",
            selected = "51272e",
            green = "a5d99c",
        },
    },
    {
        name = "Druid grove",
        description = "Forest green backgrounds with soft leaf and amber accents.",
        colors = {
            canvas = "0d1710",
            panel = "15231a",
            raised = "203328",
            edge = "496951",
            text = "edf5df",
            muted = "b7cbb0",
            gold = "e3c777",
            selected = "2e4837",
            green = "9fe2ac",
        },
    },
    {
        name = "Arcane violet",
        description = "Deep violet panels with lavender highlights and cool text.",
        colors = {
            canvas = "140f20",
            panel = "21182f",
            raised = "30233f",
            edge = "66527b",
            text = "f3edff",
            muted = "c8b6df",
            gold = "d6acff",
            selected = "47315c",
            green = "93ded0",
        },
    },
    {
        name = "Fel green",
        description = "Dark stone backgrounds with vivid fel-green highlights.",
        colors = {
            canvas = "10140c",
            panel = "1b2113",
            raised = "29321d",
            edge = "53683a",
            text = "f0f7e7",
            muted = "bfcea8",
            gold = "b6ed63",
            selected = "394929",
            green = "7ee4b2",
        },
    },
    {
        name = "Parchment",
        description = "Warm paper, dark ink and bronze accents. Uses ink-colored item names for readability.",
        inkItems = true,
        colors = {
            canvas = "f2e6cb",
            panel = "eadec1",
            raised = "fff4dc",
            edge = "9b8159",
            text = "2c2319",
            muted = "5a472e",
            gold = "74401e",
            selected = "d8c39a",
            green = "285539",
        },
    },
    {
        name = "Midnight",
        description = "Neutral black and slate with silver highlights and clear white text.",
        colors = {
            canvas = "090b0f",
            panel = "12161c",
            raised = "202630",
            edge = "505b6c",
            text = "f2f5fa",
            muted = "b6c0ce",
            gold = "d4e0f2",
            selected = "343f50",
            green = "a0d9bd",
        },
    },
}

---@param api table
---@param store ALStore
---@return boolean, string?
function SettingsPanel.register(api, store)
    local settings = api.Settings
    for _, name in ipairs({
        "RegisterVerticalLayoutCategory",
        "RegisterVerticalLayoutSubcategory",
        "RegisterProxySetting",
        "CreateSliderOptions",
        "CreateSlider",
        "CreateCheckbox",
        "CreateColorSwatch",
        "RegisterAddOnCategory",
    }) do
        if type(settings) ~= "table" or type(settings[name]) ~= "function" then
            return false, "AddOns Settings: " .. name .. " unavailable"
        end
    end
    local category, layout = settings.RegisterVerticalLayoutCategory("Azeroth Ledger")
    registeredCategory = category
    local categories, layouts = {}, {}
    for _, name in ipairs({ "Appearance", "Notifications", "Tooltips" }) do
        categories[name], layouts[name] = settings.RegisterVerticalLayoutSubcategory(category, name)
    end
    local variables = {}
    local function notify()
        if type(settings.NotifyUpdate) == "function" then
            for _, variable in ipairs(variables) do
                settings.NotifyUpdate(variable)
            end
        end
    end
    local function changed()
        if addon.Book then
            addon.Book.applyPreferences(store)
        end
        if addon.Presentation then
            addon.Presentation.refresh(store)
        end
    end
    local function proxy(target, key, name, default, get, set)
        local variable = "AzerothLedger_" .. key
        local kind = type(default) == "boolean" and "Boolean" or type(default) == "number" and "Number" or "String"
        variables[#variables + 1] = variable
        return settings.RegisterProxySetting(target, variable, settings.VarType[kind], name, default, get, set)
    end
    local function button(targetLayout, name, callback, explanation)
        if targetLayout and type(api.CreateSettingsButtonInitializer) == "function" then
            targetLayout:AddInitializer(api.CreateSettingsButtonInitializer(name, name, callback, explanation, true))
        end
    end
    local function heading(targetLayout, name)
        if targetLayout and type(api.CreateSettingsListSectionHeaderInitializer) == "function" then
            targetLayout:AddInitializer(api.CreateSettingsListSectionHeaderInitializer(name))
        end
    end
    local function slider(target, setting, minimum, maximum, step, explanation)
        local options = settings.CreateSliderOptions(minimum, maximum, step)
        if options.SetLabelFormatter and api.MinimalSliderWithSteppersMixin then
            options:SetLabelFormatter(api.MinimalSliderWithSteppersMixin.Label.Right, function(value)
                return tostring(math.floor(value * 100 + 0.5) / 100)
            end)
        end
        settings.CreateSlider(target, setting, options, explanation)
    end
    button(layout, "Open Ledger", function()
        addon.Book.open(api, store, api.UnitName("player"), api.GetRealmName())
    end, "Open your Collection and Journal.")
    heading(layout, "Window and browsing")
    button(layout, "Reset book layout", function()
        addon.Book.reset(store, "layout")
        notify()
    end, "Center the book and reset its size. Item records are kept.")
    button(layout, "Reset browsing preferences", function()
        addon.Book.reset(store, "browse")
    end, "Reset the view, search, filters and sort. Item records are kept.")
    local scale = proxy(categories.Appearance, "windowScale", "Window size", 1, function()
        return store:book().scale
    end, function(value)
        addon.Book.setScale(store, value)
    end)
    slider(categories.Appearance, scale, 0.6, 1.1, 0.05, "The window fits within your screen, even at larger sizes.")
    for _, definition in ipairs(addon.StorePreferences.displayOptions()) do
        local target = categories[definition.section]
        local setting = proxy(target, definition.key, definition.name, definition.default, function()
            return store:display()[definition.key]
        end, function(value)
            if store:setDisplay(definition.key, value) then
                changed()
            end
        end)
        local explanation = "Changes apply immediately and are saved for all characters."
        if definition.key == "toastCombat" then
            explanation = "When disabled, discoveries wait until combat ends. Collection recording continues."
        elseif definition.key == "tooltipDetails" then
            explanation = "Include dated last-seen storage quantities. Status, totals and source remain visible."
        elseif definition.key == "reducedMotion" then
            explanation = "Disable Ledger fades and stop any animation already playing."
        end
        if type(definition.default) == "boolean" then
            settings.CreateCheckbox(target, setting, explanation)
        else
            slider(target, setting, definition.minimum, definition.maximum, definition.step, explanation)
        end
    end
    heading(layouts.Appearance, "Colors")
    for _, definition in ipairs(addon.StorePreferences.colorOptions()) do
        local setting = proxy(
            categories.Appearance,
            definition.key,
            definition.name,
            hex(definition.default),
            function()
                return hex(store:display()[definition.key])
            end,
            function(value)
                local color = fromHex(value)
                if color and store:setDisplay(definition.key, color) then
                    changed()
                end
            end
        )
        settings.CreateColorSwatch(
            categories.Appearance,
            setting,
            "Choose a color with WoW's color picker. Cancel restores the previous color."
        )
    end
    local function palette(overrides)
        for _, definition in ipairs(addon.StorePreferences.colorOptions()) do
            store:setDisplay(definition.key, overrides[definition.key] or definition.default)
        end
        changed()
        notify()
    end
    heading(layouts.Appearance, "Theme presets")
    button(layouts.Appearance, "Classic gold", function()
        palette({})
    end, "Restore the original dark and gold colors. Other settings are kept.")
    button(layouts.Appearance, "Frost blue", function()
        palette({ gold = { 0.45, 0.78, 1, 1 }, selected = { 0.12, 0.23, 0.32, 1 }, edge = { 0.23, 0.35, 0.45, 1 } })
    end, "A cool blue accent on the dark Ledger background.")
    button(layouts.Appearance, "High contrast", function()
        palette({
            canvas = { 0.02, 0.02, 0.02, 1 },
            panel = { 0.04, 0.04, 0.04, 1 },
            raised = { 0.09, 0.09, 0.09, 1 },
            text = { 1, 1, 1, 1 },
            muted = { 0.82, 0.82, 0.82, 1 },
            edge = { 0.55, 0.55, 0.55, 1 },
            gold = { 1, 0.85, 0.3, 1 },
        })
        store:setDisplay("backgroundOpacity", 1)
        changed()
        notify()
    end, "Brighter text and borders on an opaque dark background.")
    for _, theme in ipairs(themes) do
        button(layouts.Appearance, theme.name, function()
            local colors = {}
            for key, value in pairs(theme.colors) do
                colors[key] = fromHex("ff" .. value)
            end
            if theme.inkItems then
                store:setDisplay("qualityColors", false)
            end
            palette(colors)
        end, theme.description)
    end
    for _, section in ipairs({ "Appearance", "Notifications", "Tooltips" }) do
        button(layouts[section], "Reset " .. section:lower(), function()
            for _, definition in ipairs(addon.StorePreferences.displayOptions()) do
                if definition.section == section then
                    store:setDisplay(definition.key, definition.default)
                end
            end
            if section == "Appearance" then
                palette({})
                addon.Book.setScale(store, 1)
            end
            changed()
            notify()
        end, "Restore this section's defaults. Collection and Journal records are kept.")
    end
    if addon.Presentation then
        button(layouts.Notifications, "Preview notification", function()
            addon.Presentation.preview(store)
        end, "Show a sample notification at your chosen size and position. This records no item discovery.")
    end
    heading(layout, "Journal history")
    for _, definition in ipairs(addon.StoreJournal.retentionOptions()) do
        local setting = proxy(category, definition.key, definition.name, definition.default, function()
            return store:retention()[definition.key]
        end, function(value)
            if store:setRetention(definition.key, value) and addon.Book then
                addon.Book.refresh(store)
            end
        end)
        slider(
            category,
            setting,
            0,
            definition.maximum,
            1,
            "Maximum recent rows. Lowering this limit removes older Journal rows immediately. "
                .. "0 keeps no rows in this category. Lifetime Collection facts and totals are kept."
        )
    end
    heading(layout, "Advanced")
    local developer = proxy(category, "developerMode", "Developer mode", false, function()
        return store:book().developerMode
    end, function(value)
        addon.Book.setDeveloperMode(store, value)
    end)
    settings.CreateCheckbox(category, developer, "Show internal item keys and recording details in item pages.")
    settings.RegisterAddOnCategory(category)
    return true
end

addon.Settings = SettingsPanel
