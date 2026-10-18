local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("BookRender")
local detailText = assert(loadfile("tests/support/detail_text.lua"))()
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
local model = addon.Collection.inspect(store, "2672:0", "Ada", "Realm")
assert(store:area("Ada", "Realm", "bags").complete, "the latest bags check must be complete")
assert(model.checks[1].area == "bags" and model.checks[1].at == 2050, "the bags check keeps its date")
assert(model.checks[2].area == "bank" and model.checks[2].at == 2100, "the bank check keeps its date")
assert(model.characterOverall == 400 and model.allCharactersOverall == 400, "first-check units count overall")
assert(not detailText(addon, model):find("2672:0", 1, true), "Internal item keys should stay hidden by default")
assert(
    detailText(addon, model, true):find("Internal item key: 2672:0", 1, true),
    "Developer mode shows the internal item key"
)
assert(
    detailText(addon, model):find("First confirmed gain: Unknown", 1, true),
    "Units only seen in storage have no confirmed gain"
)
local nobody = addon.Collection.query(store, "Ada", "Realm", { character = "Nobody", realm = "Realm" })
assert(#nobody.rows == 0, "a character with no items has an empty Collection")

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
