local addon = {}
assert(loadfile("AzerothLedger/Item.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Work.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Schema.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Scan.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/LastSeen.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Collection.lua"))("AzerothLedger", addon)
date = os.date

local timestamp = 2000
local bankOpen = false
local link = "|Hitem:2672::::::::|h[Meat]|h"
local api = {
    UnitName = function()
        return "Ada"
    end,
    GetRealmName = function()
        return "Realm"
    end,
    GetServerTime = function()
        return timestamp
    end,
    GetInventoryItemLink = function()
        return nil
    end,
    C_Container = {
        GetContainerNumSlots = function(bag)
            if bag == 0 then
                return 1
            end
            if bag == -1 and bankOpen then
                return 1
            end
            return 0
        end,
        GetContainerItemInfo = function(bag)
            if bag == 0 then
                return { itemID = 2672, hyperlink = link, stackCount = 400 }
            end
            return nil
        end,
    },
}
local saved
local store = addon.Schema.open(nil, function(value)
    saved = value
end)
assert(store:scan(addon.Scan.capture(api, "bags", bankOpen)))
assert(store:list()[1].firstSeenUnits == 400)
assert(#store:list()[1].observations == 1)
assert(store:scan(addon.Scan.capture(api, "bags", bankOpen)))
assert(#store:list()[1].observations == 1)
timestamp = 2050
assert(store:scan(addon.Scan.capture(api, "bags", bankOpen)))
assert(#store:list()[1].observations == 1)
assert(store:list()[1].observations[1].seenAt == 2050)
assert(store:scan(addon.Scan.capture(api, "bank", bankOpen)))
assert(store:area("Ada", "Realm", "bank").complete == false)
assert(#store:list()[1].observations == 1)

bankOpen = true
timestamp = 2100
assert(store:scan(addon.Scan.capture(api, "bank", bankOpen)))
assert(store:area("Ada", "Realm", "bank").complete == true)
local lines = addon.Collection.lines(store, "Ada", "Realm")
assert(lines[1]:find("checked"))
assert(lines[2]:find("checked"))
assert(lines[4]:find("first scan 400 Seen", 1, true))
assert(lines[7]:find("confirmed gain unknown", 1, true))
local filtered = addon.Collection.lines(store, "Ada", "Realm", "Nobody", "Realm")
assert(filtered[4] == "No items Seen yet.")

timestamp = 2200
api.C_Container.GetContainerItemInfo = function()
    return nil
end
assert(store:scan(addon.Scan.capture(api, "bags", bankOpen)))
local meat = store:list()[1]
assert(meat.observations[#meat.observations].quantity == 0)
assert(meat.observations[#meat.observations].seenAt == 2200)
assert(meat.lastSeen == 2050)
bankOpen = false
assert(store:scan(addon.Scan.capture(api, "bank", bankOpen)))
assert(store:area("Ada", "Realm", "bank").complete == false)
assert(#store:list()[1].observations == #meat.observations)

local restored = addon.Schema.open(saved, function(value)
    saved = value
end)
assert(restored:list()[1].firstSeenUnits == 400)
assert(restored:area("Ada", "Realm", "bank").complete == false)

print("scan_spec: passed")
