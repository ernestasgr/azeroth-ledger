-- Forever numbers its containers like the mainline client: the reagent bag (5)
-- and keyring (-1) are carried, and character bank tabs start at 6.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()
local addon = {}
local clock = 1000
local herb = "|cnIQ1:|Hitem:765::::::::1:1485:::::::::|h[Silverleaf]|h|r"
local key = "|cnIQ1:|Hitem:5396::::::::1:1485:::::::::|h[Key to Searing Gorge]|h|r"
local banked = "|cnIQ1:|Hitem:2589::::::::1:1485:::::::::|h[Linen Cloth]|h|r"
local herbs, keys = 0, 1
local bankOpen = false

_G.Enum = {
    BagIndex = {
        Accountbanktab = -3,
        Characterbanktab = -2,
        Keyring = -1,
        Backpack = 0,
        Bag_1 = 1,
        Bag_2 = 2,
        Bag_3 = 3,
        Bag_4 = 4,
        ReagentBag = 5,
        CharacterBankTab_1 = 6,
        CharacterBankTab_2 = 7,
        CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9,
        CharacterBankTab_5 = 10,
        CharacterBankTab_6 = 11,
        CharacterBankTab_7 = 12,
        CharacterBankTab_8 = 13,
        CharacterBankTab_9 = 14,
        AccountBankTab_1 = 15,
    },
}
_G.Constants = { InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 } }

local Scan = load.addon("Scan").Scan
local function ids(area)
    local result = {}
    for _, id in ipairs(Scan.containers(_G, area)) do
        result[#result + 1] = tostring(id)
    end
    return table.concat(result, ",")
end
assert(ids("bags") == "0,1,2,3,4,5,-1", "carried bags include the reagent bag and keyring: " .. ids("bags"))
assert(ids("bank") == "6,7,8,9,10,11,12,13,14", "the bank is every character bank tab: " .. ids("bank"))
assert(
    Scan.containers({}, "bank")[1] == -1 and #Scan.containers({}, "bags") == 5,
    "clients without the enums keep the Classic layout"
)

GetServerTime = function()
    return clock
end
UnitName = function(unit)
    return unit == "player" and "Mindria" or "Silverleaf"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
UnitLevel = function()
    return 10
end
GetRealZoneText = function()
    return "Teldrassil"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function(bag)
        if bag == 0 or bag == 5 or bag == -1 then
            return 1
        end
        return bag == 12 and bankOpen and 1 or 0
    end,
    GetContainerItemInfo = function(bag)
        if bag == 5 and herbs > 0 then
            return { itemID = 765, hyperlink = herb, stackCount = herbs }
        elseif bag == -1 and keys > 0 then
            return { itemID = 5396, hyperlink = key, stackCount = keys }
        elseif bag == 12 and bankOpen then
            return { itemID = 2589, hyperlink = banked, stackCount = 20 }
        end
        return nil
    end,
}
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
rawset(_G, "GetNumLootItems", function()
    return 1
end)
rawset(_G, "GetLootSlotLink", function()
    return herb
end)
rawset(_G, "GetLootSlotInfo", function()
    return nil, "Silverleaf", 2
end)
rawset(_G, "GetLootSourceInfo", function()
    return "GameObject-0-6783-1-118-1617-000040D7BC", 2
end)

client.boot(addon, load)
local event = client.event
local keyRecord = addon.store:find("5396:0")
assert(keyRecord and keyRecord.firstSeenUnits == 1, "a key on the keyring is a carried item")
assert(addon.store:area("Mindria", "Classic Beta PvE", "bags").complete, "the carried bags are read whole")

clock = 1010
event("LOOT_READY", true, false)
event("CHAT_MSG_LOOT", "You receive loot: " .. herb .. "x2.")
herbs = 2
event("BAG_UPDATE", 5)
event("BAG_UPDATE_DELAYED")
event("LOOT_CLOSED")
local herbRecord = addon.store:find("765:0")
assert(herbRecord and herbRecord.totalGained == 2, "loot that lands in the reagent bag is a confirmed gain")

clock = 1020
bankOpen = true
event("BANKFRAME_OPENED")
local bank = addon.store:area("Mindria", "Classic Beta PvE", "bank")
assert(bank and bank.complete, "an open bank is read whole")
assert(addon.store:find("2589:0").firstSeenUnits == 20, "the seventh bank tab is read")
for _, observation in ipairs(addon.store:find("765:0").observations) do
    assert(observation.area == "bags", "reagent bag items are never counted as banked")
end

print("container_layout_spec: passed")
