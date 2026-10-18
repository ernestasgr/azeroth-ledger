-- Replays the AzerothLedgerForever WoWUnit group against a booted addon with
-- the Forever client's enum and chat-string values. The group itself is the
-- in-client check; this keeps it runnable and honest between client sessions.
local load = assert(loadfile("tests/support/addon.lua"))()
local client = assert(loadfile("tests/support/client.lua"))().install()

local wowunit = assert(loadfile("tests/support/wowunit.lua"))()

rawset(_G, "Enum", {
    BagIndex = {
        Keyring = -1,
        Backpack = 0,
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
    },
})
rawset(_G, "Constants", { InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 } })
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
GetServerTime = function()
    return 1000
end
UnitName = function()
    return "Trise"
end
GetRealmName = function()
    return "Classic Beta PvE"
end
GetInventoryItemLink = function()
    return nil
end
C_Container = {
    GetContainerNumSlots = function()
        return 0
    end,
    GetContainerItemInfo = function()
        return nil
    end,
}

-- Every hooked native exists, as in the client, so registration reports nothing.
rawset(_G, "hooksecurefunc", function(target, method, callback)
    local original = target[method]
    target[method] = function(...)
        original(...)
        callback(...)
    end
end)
for _, name in ipairs({
    "BuyMerchantItem",
    "PickupMerchantItem",
    "BuybackItem",
    "TakeInboxItem",
    "AutoLootMailItem",
    "SendMail",
    "AutoStoreGuildBankItem",
    "SplitGuildBankItem",
    "PickupGuildBankItem",
}) do
    rawset(_G, name, function() end)
end
local containerHooks =
    { "UseContainerItem", "ContainerRefundItemPurchase", "PickupContainerItem", "SplitContainerItem" }
for _, name in ipairs(containerHooks) do
    C_Container[name] = function() end
end

local addon = client.boot({}, load)
AzerothLedger = addon
-- The fake client has no tooltip or AddOns Settings APIs; the real one does.
local fixtureGaps = "Item tooltip post-call unavailable, AddOns Settings: RegisterVerticalLayoutCategory unavailable"
assert(table.concat(addon.clientIssues, ", ") == fixtureGaps, table.concat(addon.clientIssues, ", "))
for index = #addon.clientIssues, 1, -1 do
    addon.clientIssues[index] = nil
end
load.companion("Forever", nil, "Smoke")
local group = assert(wowunit.named.AzerothLedgerForever, "the Forever group must register")
for name, test in pairs(group) do
    test(group)
    print(name .. ": passed")
end

-- A client that cannot register an event must fail the group.
addon.clientIssues[#addon.clientIssues + 1] = "LOOT_ITEM_ROLL_WON (unusable)"
assert(not pcall(group.EventsAndHooksRegistered, group), "an unusable event must fail the in-client check")

print("wowunit_forever_spec: passed")
