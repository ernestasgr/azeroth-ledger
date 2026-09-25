ForeverCapabilityProbeDB.uiEnabled = ForeverCapabilityProbeDB.uiEnabled ~= false
ForeverCapabilityProbeDB.tooltipEnabled = ForeverCapabilityProbeDB.tooltipEnabled == true

local function registerSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Forever Capability Probe")
    local setting = Settings.RegisterAddOnSetting(
        category,
        "ForeverCapabilityProbeEnabled",
        "uiEnabled",
        ForeverCapabilityProbeDB,
        "boolean",
        "Probe checkbox",
        true
    )
    Settings.CreateCheckbox(category, setting, "Temporary test of an account SavedVariables setting")
    Settings.RegisterAddOnCategory(category)
    print("Forever probe Settings category registered")
end

local function registerTooltip()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if ForeverCapabilityProbeDB.tooltipEnabled then
            tooltip:AddLine("Forever capability probe")
        end
    end)
    print("Forever probe item tooltip hook registered")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting then
        local ok, failure = pcall(registerSettings)
        if not ok then
            print("Forever probe Settings error:", failure)
        end
    else
        print("Forever probe Settings API unavailable")
    end

    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        local ok, failure = pcall(registerTooltip)
        if not ok then
            print("Forever probe tooltip error:", failure)
        end
    else
        print("Forever probe tooltip API unavailable")
    end
end)

SLASH_FOREVERCAPABILITYUI1 = "/fpu"
SlashCmdList.FOREVERCAPABILITYUI = function(message)
    if message == "tooltip on" then
        ForeverCapabilityProbeDB.tooltipEnabled = true
    elseif message == "tooltip off" then
        ForeverCapabilityProbeDB.tooltipEnabled = false
    elseif message ~= "status" then
        print("Forever probe UI: /fpu tooltip on, /fpu tooltip off, or /fpu status")
        return
    end
    print("Forever probe UI checkbox:", tostring(ForeverCapabilityProbeDB.uiEnabled))
    print("Forever probe tooltip line:", tostring(ForeverCapabilityProbeDB.tooltipEnabled))
end
