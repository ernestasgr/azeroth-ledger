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
    return unit == "player" and "TraceCharacter" or nil
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

event("ADDON_LOADED", "AzerothLedger")
assert(type(AzerothLedgerTraceDB) == "table" and AzerothLedgerTraceDB.enabled == false, "Trace must start off")
SlashCmdList.AZEROTHLEDGER("trace on")
event("PLAYER_LOGIN")
cached = true
event("ITEM_DATA_LOAD_RESULT", startingID, true)
SlashCmdList.AZEROTHLEDGER("trace dump")

local text = table.concat(AzerothLedgerTraceDB.lines, "\n")
local function has(pattern)
    assert(text:find(pattern), "Trace is missing " .. pattern .. "\n" .. text)
end
has("trace%-on revision=")
has("event PLAYER_LOGIN")
has("slot%-pending slot=4 id=990002 requested=true")
has("capture area=equipped complete=false items=0")
has("retry area=equipped ids=4")
has("stored%-item slot=4 key=990002:0 record=true")
has("state%-slot slot=4 id=990002")
has("state%-area area=equipped complete=true")
has("state%-record key=990002:0 first=1 gained=0")
has("state%-filter")

SlashCmdList.AZEROTHLEDGER("trace off")
local count = #AzerothLedgerTraceDB.lines
event("BAG_UPDATE_DELAYED")
assert(#AzerothLedgerTraceDB.lines == count, "Trace kept logging after it was turned off")
SlashCmdList.AZEROTHLEDGER("trace clear")
assert(#AzerothLedgerTraceDB.lines == 0, "Trace clear kept lines")

print("trace_spec: trace commands passed")
