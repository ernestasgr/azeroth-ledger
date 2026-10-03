local _, addon = ...
local SettingsPanel = {}
local definitions = {
    { key = "gains", name = "Recent gains", default = 1000, maximum = 5000 },
    { key = "transfers", name = "Alt transfers", default = 250, maximum = 2000 },
    { key = "vendor", name = "Vendor sales, refunds and buybacks", default = 250, maximum = 2000 },
}

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
        "RegisterAddOnCategory",
    }) do
        if type(settings) ~= "table" or type(settings[name]) ~= "function" then
            return false, "AddOns Settings: " .. name .. " unavailable"
        end
    end
    local category = settings.RegisterVerticalLayoutCategory("Azeroth Ledger")
    for _, definition in ipairs(definitions) do
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
