local addon = {}
assert(loadfile("AzerothLedger/Client.lua"))("AzerothLedger", addon)

local frame = {
    -- Stands in for the client's event registration method.
    RegisterEvent = function() end,
    -- Stands in for the client's script binding method.
    SetScript = function() end,
}

local api = {
    -- Provides a minimal frame for client inspection tests.
    CreateFrame = function()
        return frame
    end,
    -- Provides the target Forever build identity.
    GetBuildInfo = function()
        return "1.60.1", 70009, "date", 16001
    end,
    -- Provides the test locale.
    GetLocale = function()
        return "enUS"
    end,
    -- Provides a stable test timestamp.
    GetServerTime = function()
        return 1234
    end,
}

local healthy = addon.Client.inspect(api)
assert(#healthy.issues == 0)
assert(healthy.build == "1.60.1.70009")
assert(healthy.interface == "16001")
assert(healthy.locale == "enUS")
assert(healthy.frame == frame)

local missing = addon.Client.inspect({})
assert(#missing.issues == 4)
assert(missing.build == "<unavailable>")

local automaticIcon = addon.Client.itemMetadata({
    C_Item = {
        GetItemInfo = function()
            return nil
        end,
        GetItemIconByID = function(itemID)
            assert(itemID == 2672)
            return 133970
        end,
    },
}, { itemID = 2672, links = { "|Hitem:2672::::::::|h[Meat]|h" } })
assert(automaticIcon.icon == 133970, "an uncached item name must not hide its automatically available icon")
assert(automaticIcon.loading == true)
print("client_spec: passed")
