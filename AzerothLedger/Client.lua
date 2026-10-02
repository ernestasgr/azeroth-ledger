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

---@param api table
---@param record {links: string[]}
---@return AzerothLedgerItemMetadata
function Client.itemMetadata(api, record)
    local read = api.C_Item and api.C_Item.GetItemInfo
    if type(read) ~= "function" then
        return { category = "Unknown", loading = true }
    end
    local ok, name, _, quality, _, _, _, _, _, _, _, _, classID = pcall(read, record.links[1])
    if not ok or type(name) ~= "string" or type(quality) ~= "number" or type(classID) ~= "number" then
        return { category = "Unknown", loading = true }
    end
    local categories = { [2] = "Weapons", [4] = "Armour", [9] = "Recipes", [7] = "Materials", [0] = "Consumables" }
    return { category = quality == 0 and "Junk" or categories[classID] or "Other" }
end

---@param api table
---@return string, 'zone'|'dungeon'|nil
function Client.place(api)
    if type(api.GetRealZoneText) ~= "function" then
        return "Unknown", nil
    end
    local ok, place = pcall(api.GetRealZoneText)
    if not ok or type(place) ~= "string" or place == "" then
        return "Unknown", nil
    end
    if type(api.IsInInstance) == "function" then
        local readable, inside, kind = pcall(api.IsInInstance)
        if readable and inside == false then
            return place, "zone"
        end
        if readable and inside == true and (kind == "party" or kind == "raid") then
            return place, "dungeon"
        end
    end
    return place, nil
end

addon.Client = Client
