local addon = {}
local frame = { registered = {} }
local link = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"

function frame:RegisterEvent(event)
    self.registered[event] = true
end

function frame:SetScript(script, handler)
    if script == "OnEvent" then
        self.onEvent = handler
    end
end

for _, source in ipairs({ "Item", "Work", "Schema" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end

addon.Client = {
    inspect = function()
        return { frame = frame, issues = {}, build = "1.60.1.70009", interface = "16001", locale = "enUS" }
    end,
}
addon.Scan = {
    reader = function()
        return { capture = function() end }
    end,
}
addon.Collection = {
    refresh = function() end,
    open = function() end,
}
SlashCmdList = {}

local key = assert(addon.Item.key(link, 4540))
local saved = {
    schema = 2,
    areas = {},
    records = {
        [key] = {
            key = key,
            itemID = 4540,
            firstSeen = 100,
            lastSeen = 101,
            firstSeenUnits = 0,
            totalGained = 1,
            firstGained = 101,
            lastGained = 101,
            links = { link },
            characters = { { name = "Ada", realm = "Realm", firstSeen = 100, lastSeen = 101, firstSeenUnits = 0 } },
            observations = { { character = "Ada", realm = "Realm", area = "bags", quantity = 1, seenAt = 101 } },
            gains = {
                {
                    id = "vendor:1:" .. key,
                    at = 101,
                    quantity = 1,
                    character = "Ada",
                    realm = "Realm",
                    level = 12,
                    place = "Elwynn Forest",
                    method = "Vendor",
                    source = { kind = "vendor", name = "Dermot Johns" },
                },
            },
        },
    },
}

AzerothLedgerDB = nil
assert(loadfile("AzerothLedger/Inventory.lua"))("AzerothLedger", addon)
assert(loadfile("AzerothLedger/Main.lua"))("AzerothLedger", addon)
assert(frame.registered.ADDON_LOADED)
assert(AzerothLedgerDB == nil, "addon must not initialize SavedVariables while Lua files load")
frame.onEvent(frame, "ADDON_LOADED", "AnotherAddon")
assert(addon.store == nil, "another addon's load event must not initialize the ledger")

AzerothLedgerDB = saved
frame.onEvent(frame, "ADDON_LOADED", "AzerothLedger")
local restored = assert(addon.store:find(key), "saved record must load when ADDON_LOADED fires")
assert(restored.totalGained == 1)
assert(restored.gains[1].source.name == "Dermot Johns")
assert(AzerothLedgerDB.records[key].gains[1].source.name == "Dermot Johns")

print("saved_variables_event_spec: passed")
