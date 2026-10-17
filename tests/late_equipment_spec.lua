local addon
local frame = { registered = {} }
local timers = {}
local clock = 1000
local cached = false
local requested = {}
local startingID = 990002
local startingLink = "|Hitem:990002::::::::|h[Recruit's Shirt]|h"
local bagLink = "|Hitem:990003::::::::|h[Hearthstone]|h"

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
    return unit == "player" and "LateCharacter" or nil
end)
setGlobal("GetRealmName", function()
    return "Forever Realm"
end)
-- Forever 1.60.1.70450 trace: at login and world entry every slot and bag is empty;
-- the inventory arrives a moment later with bag updates but no equipment event.
setGlobal("GetInventoryItemID", function(_, slot)
    return slot == 4 and cached and startingID or nil
end)
setGlobal("GetInventoryItemLink", function(_, slot)
    return slot == 4 and cached and startingLink or nil
end)
setGlobal("C_Item", {
    RequestLoadItemDataByID = function(itemID)
        requested[#requested + 1] = itemID
    end,
})
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
        if cached and bag == 0 and slot == 1 then
            return { itemID = 990003, hyperlink = bagLink, stackCount = 1 }
        end
        return nil
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

local function event(name, ...)
    if frame.registered[name] then
        frame.onEvent(frame, name, ...)
    end
end

local function runTimers()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do
        callback()
    end
end

local function loadAddon(target)
    for _, source in ipairs(sources) do
        assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", target)
    end
end
addon = {}
loadAddon(addon)

local key = addon.Item.key(startingLink, startingID)

event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
clock = clock + 1
event("PLAYER_ENTERING_WORLD", true, false)
assert(not addon.store:find(key), "Gear cannot be recorded before the client exposes it")

-- The inventory arrives together; only bags announce it.
cached = true
clock = clock + 1
event("BAG_UPDATE", 0)
event("BAG_UPDATE_DELAYED")
runTimers()
local seen = addon.store:find(key)
assert(addon.store:find(addon.Item.key(bagLink, 990003)), "Starting bag item was not recorded")
assert(seen, "Starting gear that arrived with the first inventory update was not recorded")
assert(seen.firstSeenUnits == 1 and seen.totalGained == 0, "Starting gear was not recorded as starting stock")

-- Later bag-only updates keep targeted reads.
local reads = 0
local readLink = GetInventoryItemLink
setGlobal("GetInventoryItemLink", function(unit, slot)
    reads = reads + 1
    return readLink(unit, slot)
end)
clock = clock + 1
event("BAG_UPDATE", 0)
event("BAG_UPDATE_DELAYED")
runTimers()
assert(reads == 0, "A later bag update re-read every equipment slot")
setGlobal("GetInventoryItemLink", readLink)

-- A second new character whose gear arrives without bag updates relies on UNIT_INVENTORY_CHANGED.
cached = false
frame.registered = {}
timers = {}
setGlobal("UnitName", function(unit)
    return unit == "player" and "QuietCharacter" or nil
end)
local second = {}
loadAddon(second)
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
clock = clock + 1
event("PLAYER_ENTERING_WORLD", true, false)
cached = true
clock = clock + 1
assert(frame.registered.UNIT_INVENTORY_CHANGED, "Player inventory changes should be observed")
event("UNIT_INVENTORY_CHANGED", "target")
runTimers()
local quiet
for _, character in ipairs(second.store:find(key).characters) do
    quiet = quiet or character.name == "QuietCharacter"
end
assert(not quiet, "Another unit's inventory change re-read the player's gear")
event("UNIT_INVENTORY_CHANGED", "player")
runTimers()
for _, character in ipairs(second.store:find(key).characters) do
    quiet = quiet or character.name == "QuietCharacter"
end
assert(quiet, "UNIT_INVENTORY_CHANGED did not record gear that arrived silently")

print("late_equipment_spec: starting gear that appears after world entry passed")
