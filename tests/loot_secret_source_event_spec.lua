-- The client can hand back secret values: comparing, measuring, joining or
-- indexing one throws, and only issecretvalue tells it apart. A loot window
-- whose reads come back secret still records the loot, just without the part
-- that could not be read.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install({ build = 70790 })
local addon = {}
local clock = 1000
local seed = { id = 257128, link = "|cnIQ1:|Hitem:257128::::::::12:1482:::::::::|h[Zephyrseed]|h|r" }
local coneGUID = "GameObject-0-6846-2991-2-613238-AB571EFF7C"
local corpseGUID = "Creature-0-6846-2991-2-256092-54E001E475"
local bags = {}

-- A stand-in for a secret value: type() reports what it hides, and every
-- operation that would reveal it throws.
local secrets = setmetatable({}, { __mode = "k" })
local function secret(kind)
    local value = {}
    local function refuse()
        error("attempt to use a secret " .. kind .. " value", 2)
    end
    setmetatable(value, {
        __index = refuse,
        __lt = refuse,
        __le = refuse,
        __eq = refuse,
        __len = refuse,
        __concat = refuse,
        __add = refuse,
        __sub = refuse,
        __tostring = refuse,
    })
    secrets[value] = kind
    return value
end
local plainType = type
rawset(_G, "type", function(value)
    return secrets[value] or plainType(value)
end)
rawset(_G, "issecretvalue", function(value)
    return secrets[value] ~= nil
end)

GetServerTime = function()
    return clock
end
local targetName, targetGUID = nil, nil
UnitName = function(unit)
    if unit == "target" then
        return targetName
    end
    return "Mara"
end
rawset(_G, "UnitGUID", function(unit)
    return unit == "target" and targetGUID or nil
end)
GetRealmName = function()
    return "CAMWOW EU5 Realm 10 RP"
end
UnitLevel = function()
    return 12
end
GetRealZoneText = function()
    return "Zephras Isle"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(container)
        return container == 0 and 2 or 0
    end,
    GetContainerItemInfo = function(container, slot)
        local entry = container == 0 and bags[slot]
        return entry and { itemID = entry.item.id, hyperlink = entry.item.link, stackCount = entry.count } or nil
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"

local slotLink, slotQuantity, sources
rawset(_G, "GetNumLootItems", function()
    return 1
end)
rawset(_G, "GetLootSlotLink", function()
    return slotLink
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Zephyrseed", slotQuantity
end)
rawset(_G, "GetLootSourceInfo", function()
    return unpack(sources)
end)

load.addon("Main", addon)
local event = client.event
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
event("BAG_UPDATE_DELAYED")

local looted = 0
-- Opens a one-slot window with the given reads, takes the seed and returns its gain.
local function loot(reads)
    slotLink = reads.link or seed.link
    slotQuantity = reads.quantity or 1
    sources = reads.sources or { coneGUID, 1 }
    targetName, targetGUID = reads.targetName, reads.targetGUID
    clock = clock + 100
    event("LOOT_READY", false)
    event("LOOT_OPENED", false, false)
    event("LOOT_SLOT_CHANGED", 1)
    event("CHAT_MSG_LOOT", "You receive loot: " .. seed.link)
    event("LOOT_CLOSED")
    looted = looted + 1
    bags = { { item = seed, count = looted } }
    event("BAG_UPDATE_DELAYED")
    local record = addon.store:find("257128:0")
    return record and record.gains[looted]
end

local function unknown(gain, what)
    assert(gain, what .. " lost the gain")
    assert(gain.method == "Looted", what .. " was not recorded as loot")
    assert(gain.source == nil, what .. " recorded a source it could not read")
    assert(addon.LastSeen.gainSourceText(gain) == "Unknown source", what .. " did not read as an unknown source")
end

-- Every read readable: the cone is the source, as before.
local gain = loot({})
assert(gain and gain.source and gain.source.guid == coneGUID, "a readable source was not kept")

-- A secret source GUID cannot name the source, but the loot is still recorded.
unknown(loot({ sources = { secret("string"), 1 } }), "a secret source GUID")

-- A secret share count cannot split the slot, but the loot is still recorded.
unknown(loot({ sources = { coneGUID, secret("number") } }), "a secret share count")

-- A secret slot quantity cannot bound the slot, but the loot is still recorded.
gain = loot({ quantity = secret("number") })
assert(gain and gain.method == "Looted", "a secret slot quantity lost the gain")

-- A secret unit name or GUID only costs the source its name.
gain = loot({ sources = { corpseGUID, 1 }, targetName = secret("string"), targetGUID = corpseGUID })
assert(gain and gain.source and gain.source.guid == corpseGUID, "a secret unit name lost the source")
assert(gain.source.name == nil, "a secret unit name was recorded")
gain = loot({ sources = { corpseGUID, 1 }, targetName = "Prideclaw", targetGUID = secret("string") })
assert(gain and gain.source and gain.source.guid == corpseGUID, "a secret unit GUID lost the source")
assert(gain.source.name == nil, "a unit whose GUID was secret named the source")

assert(addon.StoreRecordCheck.validRecord("257128:0", addon.store:find("257128:0")), "the record was rejected")
rawset(_G, "type", plainType)
print("loot_secret_source_event_spec: passed")
