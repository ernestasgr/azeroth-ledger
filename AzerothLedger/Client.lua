local _, addon = ...

local Client = {}
local required = { "CreateFrame", "GetBuildInfo", "GetLocale", "GetServerTime" }

---@class AzerothLedgerClientApi
---@field CreateFrame? fun(frameType: string): table
---@field GetBuildInfo? fun(): string, string|number, string, number
---@field GetLocale? fun(): string
---@field GetServerTime? fun(): number

---@class AzerothLedgerClientInspection
---@field issues string[]
---@field build string
---@field interface string
---@field locale string
---@field frame? table

---@param api AzerothLedgerClientApi
---@return AzerothLedgerClientInspection
-- Checks required APIs and captures the current client identity.
function Client.inspect(api)
    local result = { issues = {}, build = "<unavailable>", interface = "<unavailable>", locale = "<unavailable>" }
    for _, name in ipairs(required) do
        if type(api[name]) ~= "function" then
            result.issues[#result.issues + 1] = name
        end
    end

    if type(api.GetBuildInfo) == "function" then
        local ok, version, buildNumber, _, interfaceNumber = pcall(api.GetBuildInfo)
        if
            ok
            and type(version) == "string"
            and (type(buildNumber) == "string" or type(buildNumber) == "number")
            and type(interfaceNumber) == "number"
        then
            result.build = version .. "." .. tostring(buildNumber)
            result.interface = tostring(interfaceNumber)
        else
            result.issues[#result.issues + 1] = "GetBuildInfo (unusable)"
        end
    end

    if type(api.GetLocale) == "function" then
        local ok, value = pcall(api.GetLocale)
        if ok and type(value) == "string" then
            result.locale = value
        else
            result.issues[#result.issues + 1] = "GetLocale (unusable)"
        end
    end

    if type(api.GetServerTime) == "function" then
        local ok, value = pcall(api.GetServerTime)
        if not ok or type(value) ~= "number" then
            result.issues[#result.issues + 1] = "GetServerTime (unusable)"
        end
    end

    if type(api.CreateFrame) == "function" then
        local ok, frame = pcall(api.CreateFrame, "Frame")
        if ok and frame and type(frame.RegisterEvent) == "function" and type(frame.SetScript) == "function" then
            result.frame = frame
        else
            result.issues[#result.issues + 1] = "CreateFrame (unusable)"
        end
    end

    return result
end

addon.Client = Client
