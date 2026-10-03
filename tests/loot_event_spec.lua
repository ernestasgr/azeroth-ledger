local addon = {}
local frame = { registered = {} }
local clock, units = 1000, 0
local linkReadable = true
local link = "|cnIQ0:|Hitem:7098::::::::1:1485:::::::::|h[Splintered Tusk]|h|r"
local eggLink = "|cnIQ1:|Hitem:6889::::::::1:1485:::::::::|h[Small Egg]|h|r"
local eggUnits, eggReadable, twoSlots, sameItemSlots, separateSource, splitSource = 0, false, false, false, false, false
local sourceReadable = true
function frame:RegisterEvent(event)
    self.registered[event] = true
end
function frame:SetScript(name, handler)
    if name == "OnEvent" then
        self.onEvent = handler
    end
end
CreateFrame = function()
    return frame
end
GetBuildInfo = function()
    return "1.60.1", 70205, "date", 16001
end
GetLocale = function()
    return "enUS"
end
GetServerTime = function()
    return clock
end
UnitName = function(unit)
    return unit == "player" and "Mindria" or "Young Thistle Boar"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 1
end
GetRealZoneText = function()
    return "Teldrassil"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and (twoSlots and 2 or 1) or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 2 and eggUnits > 0 then
            return { itemID = 6889, hyperlink = eggLink, stackCount = eggUnits }
        end
        return bag == 0 and units > 0 and { itemID = 7098, hyperlink = link, stackCount = units } or nil
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
_G.GetNumLootItems = function()
    return twoSlots and 2 or 1
end
_G.GetLootSlotLink = function(slot)
    if slot == 2 then
        return eggReadable and (sameItemSlots and link or eggLink) or nil
    end
    return linkReadable and link or nil
end
_G.GetLootSlotInfo = function(slot)
    return nil, "Loot item", (slot == 2 or splitSource) and 3 or 1
end
_G.GetLootSourceInfo = function(slot)
    if not sourceReadable then
        return nil
    elseif splitSource then
        return "Creature-0-6783-1-118-1984-000040D7BC", 1, "Creature-0-6783-1-118-1984-000040D7BD", 2
    end
    if slot == 2 and separateSource then
        return "Creature-0-6783-1-118-1984-000040D7BD", 3
    end
    return "Creature-0-6783-1-118-1984-000040D7BC", slot == 2 and 3 or 1
end
_G.UnitGUID = function()
    return "Creature-0-6783-1-118-1984-000040D7BC"
end
SlashCmdList = {}
for _, source in ipairs({
    "Item",
    "Work", -- Frame work and profiling precede consumers.
    "Schema",
    "Client",
    "Scan",
    "Loot",
    "Reward",
    "Vendor",
    "Collection",
    "Main",
}) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
local function event(name, ...)
    if frame.registered[name] then
        frame.onEvent(frame, name, ...)
    end
end
event("ADDON_LOADED", "AzerothLedger")
event("PLAYER_LOGIN")
clock = 1010
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
event("LOOT_CLOSED")
clock, units = 1011, 1
event("BAG_UPDATE_DELAYED")
local record = addon.store:find("7098:0")
assert(record and record.totalGained == 1, "Splintered Tusk: checked units 1, Total gained 0")

-- READY can repeat and OPENED can follow the bag increase. Neither may
-- replace the original baseline or create competing sessions for this loot.
clock = 1080
event("LOOT_READY", true, false)
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
units = 2
event("BAG_UPDATE_DELAYED")
event("LOOT_OPENED", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
event("BAG_UPDATE_DELAYED")
assert(addon.store:find("7098:0").totalGained == 2, "Repeated loot notifications changed the confirmed total")
event("LOOT_CLOSED")

-- The real client trace closed twice before the last item's receipt.
clock = 1150
event("LOOT_READY", false, false)
event("LOOT_OPENED", false, false)
units = 3
event("LOOT_CLOSED")
event("LOOT_CLOSED")
event("BAG_UPDATE_DELAYED")
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
assert(addon.store:find("7098:0").totalGained == 3, "Receipt after close was lost")

-- An unreadable READY must allow a later readable OPENED to capture loot.
clock, linkReadable = 1220, false
event("LOOT_READY", false, false)
linkReadable = true
event("LOOT_OPENED", false, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
units = 4
event("BAG_UPDATE_DELAYED")
assert(addon.store:find("7098:0").totalGained == 4, "Readable OPENED did not recover an empty READY")
event("LOOT_CLOSED")

-- A bag change alone remains an observation, even after a loot cycle.
clock, units = 1290, 5
event("BAG_UPDATE_DELAYED")
assert(addon.store:find("7098:0").totalGained == 4, "A bag observation invented a gain")

-- A partially readable READY must preserve the whole pre-gain bag baseline
-- when another item becomes readable after a bag scan.
twoSlots, eggUnits = true, 2
event("BAG_UPDATE_DELAYED")
clock = 1360
event("LOOT_READY", true, false)
units, eggUnits = 6, 3
event("BAG_UPDATE_DELAYED")
event("CHAT_MSG_LOOT", "You receive loot: " .. eggLink .. "x3")
assert(addon.store:find("6889:0").totalGained == 0, "Receipt without a readable slot was credited")
eggReadable = true
event("LOOT_OPENED", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
assert(addon.store:find("7098:0").totalGained == 5, "Late slot capture replaced the first item's baseline")
assert(addon.store:find("6889:0").totalGained == 1, "Later-readable item did not use the original measured increase")
for _, entry in ipairs(addon.store:unresolved()) do
    assert(entry.detail.key ~= "6889:0", "Matched same-cycle receipt remained unresolved")
end
event("LOOT_CLOSED")

-- A later-readable second slot of the same item also extends the candidate
-- quantity once; repeated OPENED cannot add its quantity again.
clock, eggReadable, sameItemSlots = 1430, false, true
event("LOOT_READY", true, false)
eggReadable = true
event("LOOT_OPENED", true, false)
event("LOOT_OPENED", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link .. "x4")
units = 8
event("BAG_UPDATE_DELAYED")
assert(addon.store:find("7098:0").totalGained == 7, "Later-readable same-item slot was lost or counted twice")
event("LOOT_CLOSED")

-- A proven first-slot gain must retain its source when a later slot introduces
-- another source. Partial additional units stay unknown until all shares match.
clock, eggReadable, separateSource = 1500, false, true
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
units = 9
event("BAG_UPDATE_DELAYED")
eggReadable = true
event("LOOT_OPENED", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link)
units = 10
event("BAG_UPDATE_DELAYED")
local known, unknown = 0, 0
for _, gain in ipairs(addon.store:find("7098:0").gains) do
    if gain.at == 1500 then
        if gain.source and gain.source.name == "Young Thistle Boar" then
            known = known + gain.quantity
        elseif not gain.source then
            unknown = unknown + gain.quantity
        end
    end
end
assert(known == 1 and unknown == 1, "Late slot discovery erased proven units or assigned ambiguous units a source")
event("CHAT_MSG_LOOT", "You receive loot: " .. link .. "x2")
units = 12
event("BAG_UPDATE_DELAYED")
local firstSource, secondSource = 0, 0
for _, gain in ipairs(addon.store:find("7098:0").gains) do
    if gain.at == 1500 and gain.source then
        if gain.source.guid == "Creature-0-6783-1-118-1984-000040D7BC" then
            firstSource = firstSource + gain.quantity
        elseif gain.source.guid == "Creature-0-6783-1-118-1984-000040D7BD" then
            secondSource = secondSource + gain.quantity
        end
    end
end
assert(firstSource == 1 and secondSource == 3, "Complete late shares did not preserve the measured source split")
assert(addon.store:find("7098:0").totalGained == 11, "Source enrichment changed the confirmed quantity")
event("LOOT_CLOSED")

-- A later complete source decomposition must improve an unknown aggregate
-- without adding units, even when the gain was already recorded at READY.
clock, twoSlots, splitSource, sourceReadable = 1570, false, true, false
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. link .. "x3")
units = 15
event("BAG_UPDATE_DELAYED")
sourceReadable = true
event("LOOT_OPENED", true, false)
firstSource, secondSource = 0, 0
for _, gain in ipairs(addon.store:find("7098:0").gains) do
    if gain.at == 1570 and gain.source then
        if gain.source.guid == "Creature-0-6783-1-118-1984-000040D7BC" then
            firstSource = firstSource + gain.quantity
        elseif gain.source.guid == "Creature-0-6783-1-118-1984-000040D7BD" then
            secondSource = secondSource + gain.quantity
        end
    end
end
assert(firstSource == 1 and secondSource == 2, "Complete later source proof left the aggregate unknown")
assert(addon.store:find("7098:0").totalGained == 14, "Later source decomposition changed the confirmed quantity")
event("LOOT_CLOSED")

-- A pending receipt cannot cross the correlation deadline or another loot
-- cycle. Its unresolved evidence remains available rather than being repaired.
clock, twoSlots, splitSource, eggReadable, sameItemSlots = 1640, true, false, false, false
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. eggLink)
eggUnits = 4
event("BAG_UPDATE_DELAYED")
clock, eggReadable = 1700, true
event("LOOT_OPENED", true, false)
assert(addon.store:find("6889:0").totalGained == 1, "Expired pending receipt became a gain")
event("LOOT_CLOSED")
clock, eggReadable = 1710, false
event("LOOT_READY", true, false)
eggReadable = true
event("LOOT_OPENED", true, false)
event("BAG_UPDATE_DELAYED")
assert(addon.store:find("6889:0").totalGained == 1, "Old pending receipt crossed into a new loot cycle")
local retained = false
for _, entry in ipairs(addon.store:unresolved()) do
    if entry.kind == "lootReceipt" and entry.detail.key == "6889:0" and entry.at == 1640 then
        retained = true
    end
end
assert(retained, "Expired unmatched receipt was discarded by a later slot proof")
event("LOOT_CLOSED")

clock, eggReadable = 1760, true
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. eggLink)
eggUnits = 5
event("BAG_UPDATE_DELAYED")
event("LOOT_CLOSED")
clock, eggReadable = 1770, false
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. eggLink)
eggUnits = 6
event("BAG_UPDATE_DELAYED")
eggReadable = true
event("LOOT_OPENED", true, false)
assert(addon.store:find("6889:0").totalGained == 3, "Exhausted older loot cycle swallowed a new pending receipt")
event("LOOT_CLOSED")

local function craftEgg(recipeID)
    assert(
        addon.store:rewardReceipt(
            {
                key = "6889:0",
                quantity = 1,
                method = "Crafted",
                context = { kind = "recipe", id = recipeID or 7 },
            },
            clock,
            { character = "Mindria", realm = "Classic Beta PvE", level = 1, place = "Teldrassil", placeKind = "zone" }
        )
    )
end
clock, eggReadable = 1840, false
event("LOOT_READY", true, false)
clock = 1841
craftEgg(8)
clock = 1842
event("CHAT_MSG_LOOT", "You receive loot: " .. eggLink)
clock, eggReadable = 1843, true
event("LOOT_OPENED", true, false)
clock, eggUnits = 1844, 7
event("BAG_UPDATE_DELAYED")
assert(addon.store:breakdown("6889:0").methods.Crafted == 1, "Pending loot receipt stole a confirmed craft")
event("LOOT_CLOSED")

clock, eggReadable = 1910, false
event("LOOT_READY", true, false)
clock = 1911
event("CHAT_MSG_LOOT", "You receive loot: " .. eggLink)
clock = 1912
craftEgg()
clock, eggReadable = 1913, true
event("LOOT_OPENED", true, false)
clock, eggUnits = 1914, 8
event("BAG_UPDATE_DELAYED")
assert(
    addon.store:breakdown("6889:0").methods.Crafted == 2,
    "Replayed pending loot receipt stole a later-confirmed craft"
)
assert(addon.store:breakdown("6889:0").methods.Looted == 3, "Reward arbitration changed proven loot totals")
event("LOOT_CLOSED")

-- A newer reward must win arbitration even when an older matching reward is
-- still inside the evidence window.
clock, eggReadable = 1920, true
event("LOOT_READY", true, false)
clock = 1921
event("CHAT_MSG_LOOT", "You receive loot: " .. eggLink)
clock = 1922
craftEgg(9)
clock, eggReadable = 1923, true
event("LOOT_OPENED", true, false)
clock, eggUnits = 1924, 9
event("BAG_UPDATE_DELAYED")
assert(addon.store:breakdown("6889:0").methods.Crafted == 3, "Older reward masked a newer confirmed craft")
assert(addon.store:breakdown("6889:0").methods.Looted == 3, "Newest reward arbitration changed proven loot totals")
event("LOOT_CLOSED")
-- Native timer boundary: an event burst reads only its changed container once.
local timers, reads = {}, {}
_G.C_Timer = {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end,
}
local slots = C_Container.GetContainerNumSlots
C_Container.GetContainerNumSlots = function(bag)
    reads[bag] = (reads[bag] or 0) + 1
    return slots(bag)
end
clock = 1930
event("BAG_UPDATE", 0)
event("BAG_UPDATE_DELAYED")
event("BAG_UPDATE", 0)
event("BAG_UPDATE_DELAYED")
assert(#timers == 1 and next(reads) == nil, "Inventory burst must wait and coalesce")
timers[1]()
assert(reads[0] == 1 and reads[1] == nil and reads[-1] == nil, "Unchanged containers must use checked snapshots")
assert(addon.store:area("Mindria", "Classic Beta PvE", "bags").seenAt == 1930)
_G.C_Timer = nil
print("loot_event_spec: passed")
