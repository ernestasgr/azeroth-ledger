local _, addon = ...
local SettingsPanel = {}

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
    local category = settings.RegisterVerticalLayoutCategory("Azeroth Ledger")
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
