local addon = {}
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
    return unit == "player" and "FreshCharacter" or nil
end)
setGlobal("GetRealmName", function()
    return "Forever Realm"
end)
-- A new character's starting gear is equipped before the client has cached it:
-- the slot reports an item ID, but no link until the item data loads.
setGlobal("GetInventoryItemID", function(_, slot)
    return slot == 4 and startingID or nil
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
        if bag == 0 and slot == 1 then
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

local function runTimers()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do
        callback()
    end
end

event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
clock = clock + 1
event("PLAYER_ENTERING_WORLD", true, false)

local key = addon.Item.key(startingLink, startingID)
assert(addon.store:find(addon.Item.key(bagLink, 990003)), "Starting bag item was not recorded")
assert(not addon.store:find(key), "Uncached gear cannot be recorded before its link exists")
local equipped = addon.store:area("FreshCharacter", "Forever Realm", "equipped")
assert(equipped and equipped.complete == false, "Occupied slots without a link must make the gear check incomplete")
assert(requested[1] == startingID, "Uncached starting gear should request its item data")

-- Item data arrives; the occupied slot is read again and recorded as starting stock.
cached = true
clock = clock + 1
assert(frame.registered.ITEM_DATA_LOAD_RESULT, "Item data loads should be observed")
event("ITEM_DATA_LOAD_RESULT", startingID, true)
local seen = addon.store:find(key)
assert(seen, "Starting equipment was not recorded after its item data loaded")
assert(seen.firstSeenUnits == 1, "Starting equipment quantity was wrong")
assert(seen.totalGained == 0, "Starting equipment was counted as a new gain")
equipped = addon.store:area("FreshCharacter", "Forever Realm", "equipped")
assert(equipped.complete == true, "Gear check stayed incomplete after the link became readable")

-- A later load event must not duplicate the record or its quantity.
clock = clock + 1
event("GET_ITEM_INFO_RECEIVED", startingID, true)
seen = addon.store:find(key)
assert(seen.firstSeenUnits == 1 and seen.totalGained == 0, "Repeated load event changed starting gear")
assert(#addon.store:list() == 2, "Repeated load event created a duplicate Collection record")

-- Without any item-data event, a later inventory update still retries unreadable slots.
local otherAddon = {}
frame.registered = {}
cached = false
timers = {}
setGlobal("UnitName", function(unit)
    return unit == "player" and "SecondCharacter" or nil
end)
for _, source in ipairs(sources) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", otherAddon)
end
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
local store = otherAddon.store
assert(#store:find(key).characters == 1, "Unreadable gear was recorded before its link existed")
cached = true
clock = clock + 1
event("BAG_UPDATE", 0)
event("BAG_UPDATE_DELAYED")
runTimers()
seen = store:find(key)
local second
for _, character in ipairs(seen.characters) do
    if character.name == "SecondCharacter" then
        second = character
    end
end
assert(second and second.firstSeenUnits == 1, "A later inventory update did not retry unreadable starting gear")
assert(seen.totalGained == 0, "Retried starting gear was counted as a new gain")

print("uncached_equipment_spec: uncached starting equipment passed")
