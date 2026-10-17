local addon = {}
local frame = { registered = {} }
local timers = {}
local clock = 1000
local equippedLink
local bagItem
local startingLink = "|Hitem:990001::::::::|h[Starting Blade]|h"

local function setGlobal(name, value)
    rawset(_G, name, value)
end

function frame:RegisterEvent(event)
    self.registered[event] = true
end

function frame:SetScript(name, handler)
    if name == "OnEvent" then
        self.onEvent = handler
    end
end

setGlobal("CreateFrame", function()
    return frame
end)
setGlobal("GetBuildInfo", function()
    return "1.60.1", 70205, "date", 16001
end)
setGlobal("GetLocale", function()
    return "enUS"
end)
setGlobal("GetServerTime", function()
    return clock
end)
setGlobal("UnitName", function(unit)
    return unit == "player" and "NewCharacter" or nil
end)
setGlobal("GetRealmName", function()
    return "Forever Realm"
end)
setGlobal("GetInventoryItemLink", function(_, slot)
    return slot == 16 and equippedLink or nil
end)
setGlobal("C_Timer", {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end,
})
setGlobal("C_Container", {
    GetContainerNumSlots = function(bag)
        return bag == 0 and 1 or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        return bag == 0 and slot == 1 and bagItem or nil
    end,
})
setGlobal("SlashCmdList", {})

local sources = {
    "Item",
    "Work",
    "Trace",
    "SchemaValidate",
    "StoreKernel",
    "StorePreferences",
    "StoreJournal",
    "StoreEvidence",
    "StoreRecords",
    "StoreLoot",
    "StoreExchange",
    "StoreVendor",
    "StoreReward",
    "StoreScan",
    "Schema",
    "Client",
    "Scan",
    "LastSeen",
    "Collection",
    "Inventory",
    "Events",
    "Runtime",
    "MerchantSession",
    "MailSession",
    "TradeSession",
    "LootSession",
    "QuestSession",
    "CraftSession",
    "Diagnostics",
    "Commands",
    "MinimapButton",
    "Main",
}
for _, source in ipairs(sources) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end

local function event(name, ...)
    if frame.registered[name] then
        frame.onEvent(frame, name, ...)
    end
end

event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")

-- Model a new character whose starting equipment becomes visible as the world loads.
equippedLink = startingLink
clock = clock + 1
event("PLAYER_ENTERING_WORLD", true, false)
local key = addon.Item.key(startingLink, 990001)
local seenAtWorldEntry = addon.store:find(key)

-- A repeated initial entry scan must not add duplicate Collection records or gained units.
clock = clock + 1
event("PLAYER_ENTERING_WORLD", true, false)
local seenAfterRepeatedEntry = addon.store:find(key)
assert(seenAfterRepeatedEntry, "Starting equipment was not recorded on world entry")
assert(seenAfterRepeatedEntry.firstSeenUnits == 1, "Repeated world entry changed initial item quantity")
assert(seenAfterRepeatedEntry.totalGained == 0, "Initial equipment was counted as a new gain")
assert(#addon.store:list() == 1, "Repeated world entry created a duplicate Collection record")
assert(#seenAfterRepeatedEntry.observations == 1, "Repeated world entry duplicated an unchanged observation")

-- The item remains one initial holding after it moves from equipment to bags.
equippedLink = nil
bagItem = { itemID = 990001, hyperlink = startingLink, stackCount = 1 }
clock = clock + 1
event("BAG_UPDATE", 0)
event("BAG_UPDATE_DELAYED")
event("PLAYER_EQUIPMENT_CHANGED", 16)
assert(#timers == 1, "Bag and equipment updates should share one deferred scan")
timers[1]()
local seenAfterUnequip = addon.store:find(key)
assert(seenAtWorldEntry, "Starting equipment was missed until unequip")
assert(seenAfterUnequip and seenAfterUnequip.firstSeenUnits == 1, "Unequipping changed initial item quantity")
assert(seenAfterUnequip.totalGained == 0, "Unequipping counted initial equipment as a gain")
assert(#addon.store:list() == 1, "Moving initial equipment to bags created a duplicate Collection record")

print("new_character_equipment_spec: startup equipment and repeat scans passed")
