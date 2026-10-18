local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
-- The guild bank: your own deposits come back as your items, and anything
-- else you withdraw came from the guild.
local cloth = "|cnIQ1:|Hitem:2589::::::::5:1491:::::::::|h[Linen Cloth]|h|r"
local potion = "|cnIQ1:|Hitem:118::::::::5:1491:::::::::|h[Minor Healing Potion]|h|r"
local clock = 1000
local bag = {}
local guild = { [1] = { link = potion, quantity = 3 } }

GetServerTime = function()
    return clock
end
UnitName = function()
    return "Trise"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 20
end
GetRealZoneText = function()
    return "Stormwind City"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(id)
        return id == 0 and 4 or 0
    end,
    GetContainerItemInfo = function(id, slot)
        local stack = id == 0 and bag[slot]
        if not stack then
            return nil
        end
        local itemID = tonumber(stack.link:match("item:(%d+)"))
        return { itemID = itemID, hyperlink = stack.link, stackCount = stack.quantity }
    end,
    -- Right-clicking a bag stack with the guild bank open deposits it.
    UseContainerItem = function(_, slot)
        guild[#guild + 1] = bag[slot]
        bag[slot] = nil
    end,
    PickupContainerItem = function() end,
    SplitContainerItem = function() end,
}
rawset(_G, "GetCursorInfo", function()
    return nil
end)
rawset(_G, "GetCurrentGuildBankTab", function()
    return 1
end)
rawset(_G, "GetGuildBankItemLink", function(_, slot)
    return guild[slot] and guild[slot].link or nil
end)
rawset(_G, "GetGuildBankItemInfo", function(_, slot)
    return guild[slot] and 1 or nil, guild[slot] and guild[slot].quantity or 0, false
end)
rawset(_G, "AutoStoreGuildBankItem", function(_, slot)
    local stack = guild[slot]
    guild[slot] = nil
    for index = 1, 4 do
        if not bag[index] then
            bag[index] = stack
            return
        end
    end
end)
rawset(_G, "PickupGuildBankItem", function() end)
rawset(_G, "SplitGuildBankItem", function() end)
rawset(_G, "hooksecurefunc", function(target, method, callback)
    local original = target[method]
    target[method] = function(...)
        original(...)
        callback(...)
    end
end)

local addon = client.boot({}, load)
local event = client.event

local function gained(link)
    local record = addon.store:find(link:match("item:(%d+)") .. ":0")
    return record and record.totalGained or 0, record
end

local function settle()
    event("GUILDBANKBAGSLOTS_CHANGED")
    event("BAG_UPDATE", 0)
    event("BAG_UPDATE_DELAYED")
end

-- A stack someone else deposited is a gain from the guild.
clock = 1010
event("GUILDBANKFRAME_OPENED")
_G.AutoStoreGuildBankItem(1, 1)
settle()
local total, record = gained(potion)
assert(total == 3, "a withdrawal you never deposited is a confirmed gain")
assert(record.gains[1].method == "Obtained" and record.gains[1].channel == "guild", "it came from the guild bank")

-- Your own deposit taken back is not a new gain.
clock = 1100
bag[2] = { link = cloth, quantity = 20 }
settle()
local seen = gained(cloth)
C_Container.UseContainerItem(0, 2)
settle()
clock = 1110
_G.AutoStoreGuildBankItem(1, 2)
settle()
assert(gained(cloth) == seen, "your own deposit taken back is not a gain")
event("GUILDBANKFRAME_CLOSED")

-- Closed, a guild function call proves nothing.
clock = 1200
guild[3] = { link = potion, quantity = 1 }
_G.AutoStoreGuildBankItem(1, 3)
settle()
assert(gained(potion) == 3, "no guild bank window, no guild bank gain")

-- An alt's deposit taken by another of your characters is a transfer.
local saved = AzerothLedgerDB
local store = addon.Schema.open(saved, function(value)
    saved = value
end)
local nora = { character = "Nora", realm = "Classic Beta PvE", level = 12, place = "Stormwind City" }
local trise = { character = "Trise", realm = "Classic Beta PvE", level = 20, place = "Stormwind City" }
assert(store:setCharacter("Trise", "Classic Beta PvE"))
local function scan(actor, at, units)
    assert(store:scan({
        character = actor.character,
        realm = actor.realm,
        area = "bags",
        seenAt = at,
        complete = true,
        items = units > 0 and { { itemID = 2589, link = cloth, quantity = units } } or {},
    }))
end
local deposit = { channel = "guild", direction = "out", key = "2589:0", itemID = 2589, link = cloth, quantity = 20 }
scan(trise, 2000, 20)
local id = store:command("exchangeIntent", deposit, 2001, trise)
assert(store:command("exchangeConfirm", { channel = "guild", direction = "out", ids = { [id] = true } }, 2001, trise))
scan(trise, 2002, 0)

store = addon.Schema.open(saved, function(value)
    saved = value
end)
assert(store:setCharacter("Nora", "Classic Beta PvE"))
scan(nora, 3000, 0)
local withdrawal = { channel = "guild", direction = "in", key = "2589:0", itemID = 2589, link = cloth, quantity = 20 }
id = store:command("exchangeIntent", withdrawal, 3001, nora)
assert(store:command("exchangeConfirm", { channel = "guild", direction = "in", ids = { [id] = true } }, 3001, nora))
local before = store:find("2589:0").totalGained
scan(nora, 3002, 20)
assert(store:find("2589:0").totalGained == before, "an alt's deposit is not a new gain")
local moved
for _, row in ipairs(addon.Journal.query(store)) do
    moved = moved or (row.action == "Alt guild bank" and row) or nil
end
assert(moved and moved.sourceText:find("Trise"), "the Journal shows the move from Trise")

print("guild_bank_event_spec: passed")
