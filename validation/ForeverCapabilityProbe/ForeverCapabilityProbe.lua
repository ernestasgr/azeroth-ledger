---@class ForeverCapabilityProbeState
---@field marker? string
---@field traces? ForeverCapabilityTraceRecord[]
---@field traceScenario? string
---@field snapshots? ForeverCapabilityBagSnapshot[]
---@field uiEnabled? boolean
---@field tooltipEnabled? boolean

---@type ForeverCapabilityProbeState
ForeverCapabilityProbeDB = type(ForeverCapabilityProbeDB) == "table" and ForeverCapabilityProbeDB or {}

local function printStatus()
    local version, build, date, interface = GetBuildInfo()
    print("Forever probe build:", version, build, date, interface)
    print("Forever probe Lua:", _VERSION, "project:", WOW_PROJECT_ID)

    local marker = ForeverCapabilityProbeDB and ForeverCapabilityProbeDB.marker
    print("Forever probe marker:", marker or "<absent>")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, addonName)
    if addonName ~= "ForeverCapabilityProbe" then
        return
    end

    printStatus()

    if WoWUnit then
        local tests = WoWUnit("ForeverCapabilityProbeSmoke")
        function tests:SavedVariablesTableExists()
            WoWUnit.IsTrue(type(ForeverCapabilityProbeDB) == "table")
        end
        function tests:AssertionsRun()
            WoWUnit.AreEqual(2, 1 + 1)
        end
        print("Forever probe WoWUnit group registered")
    else
        print("Forever probe WoWUnit unavailable")
    end
end)

SLASH_FOREVERCAPABILITYPROBE1 = "/fp"
SlashCmdList.FOREVERCAPABILITYPROBE = function(message)
    local marker = message:match("^mark%s+(.+)$")
    if marker then
        ForeverCapabilityProbeDB.marker = marker
        printStatus()
    elseif message == "status" then
        printStatus()
    else
        print("Forever probe: /fp mark <token> or /fp status")
    end
end
