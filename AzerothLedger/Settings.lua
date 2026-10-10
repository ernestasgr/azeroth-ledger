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

---@param api table
---@param store ALStore
---@return boolean, string?
function SettingsPanel.register(api, store)
    local settings = api.Settings
    for _, name in ipairs({
        "RegisterVerticalLayoutCategory",
        "RegisterProxySetting",
        "CreateSliderOptions",
        "CreateSlider",
        "CreateCheckbox",
        "RegisterAddOnCategory",
    }) do
        if type(settings) ~= "table" or type(settings[name]) ~= "function" then
            return false, "AddOns Settings: " .. name .. " unavailable"
        end
    end
    local category, layout = settings.RegisterVerticalLayoutCategory("Azeroth Ledger")
    registeredCategory = category
    if layout and type(api.CreateSettingsButtonInitializer) == "function" then
        local function button(name, callback, explanation)
            layout:AddInitializer(api.CreateSettingsButtonInitializer(name, name, callback, explanation, true))
        end
        button("Open Ledger", function()
            local character, realm = api.UnitName("player"), api.GetRealmName()
            addon.Book.open(api, store, character, realm)
        end, "Open your Collection and Journal.")
        button("Reset book layout", function()
            addon.Book.reset(store, "layout")
        end, "Center the book and reset its size. Item records are kept.")
        button("Reset browsing preferences", function()
            addon.Book.reset(store, "browse")
        end, "Reset the view, search, filters and sort. Item records are kept.")
    end
    for _, definition in ipairs({
        { key = "tooltips", name = "Show Collection facts in item tooltips" },
        { key = "toasts", name = "Show first-discovery toasts" },
    }) do
        local setting = settings.RegisterProxySetting(
            category,
            "AzerothLedger_" .. definition.key,
            settings.VarType.Boolean,
            definition.name,
            true,
            function()
                return store:display()[definition.key]
            end,
            function(value)
                store:setDisplay(definition.key, value)
            end
        )
        settings.CreateCheckbox(category, setting, "Affects the next interaction. Collection facts are kept.")
    end
    local developerMode = settings.RegisterProxySetting(
        category,
        "AzerothLedger_developerMode",
        settings.VarType.Boolean,
        "Developer mode",
        false,
        function()
            return store:book().developerMode
        end,
        function(value)
            if addon.Book then
                addon.Book.setDeveloperMode(store, value)
            end
        end
    )
    settings.CreateCheckbox(category, developerMode, "Show internal item keys and recording details in item pages.")
    for _, definition in ipairs(addon.Schema.retentionOptions()) do
        local setting = settings.RegisterProxySetting(
            category,
            "AzerothLedger_" .. definition.key,
            settings.VarType.Number,
            definition.name,
            definition.default,
            function()
                return store:retention()[definition.key]
            end,
            function(value)
                if store:setRetention(definition.key, value) and addon.Book then
                    addon.Book.refresh(store)
                end
            end
        )
        local options = settings.CreateSliderOptions(0, definition.maximum, 1)
        settings.CreateSlider(
            category,
            setting,
            options,
            "Maximum recent rows. 0 keeps no rows in this category. Lifetime Collection facts and totals are kept."
        )
    end
    settings.RegisterAddOnCategory(category)
    return true
end

addon.Settings = SettingsPanel
