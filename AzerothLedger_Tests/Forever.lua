local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerForever")

-- Facts about the Forever client that the item gain rules depend on. Run in
-- the client after /reload: they read its own enums, chat strings and event
-- registration, so a passing run confirms the live build, not a fixture.

local link = "|cnIQ1:|Hitem:2589::::::::5:1491:::::::::|h[Linen Cloth]|h|r"

local function has(list, value)
    for _, entry in ipairs(list) do
        if entry == value then
            return true
        end
    end
    return false
end

-- The reagent bag and keyring are carried; the bank is the character tabs.
function tests.ContainerLayout(_self)
    local index = _G.Enum.BagIndex
    WoWUnit.AreEqual(5, index.ReagentBag)
    WoWUnit.AreEqual(-1, index.Keyring)
    WoWUnit.AreEqual(6, index.CharacterBankTab_1)
    local bags = addon.Scan.containers(_G, "bags")
    WoWUnit.IsTrue(has(bags, 0) and has(bags, 4) and has(bags, 5) and has(bags, -1))
    local bank = addon.Scan.containers(_G, "bank")
    WoWUnit.AreEqual(6, bank[1])
    WoWUnit.IsTrue(not has(bank, 5) and not has(bank, -1))
end

-- Each of the player's own item lines is read as the kind of receipt it is.
function tests.ReceiptFormats(_self)
    local cases = {
        { LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, "loot" },
        { LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, "pushed" },
        { LOOT_ITEM_CREATED_SELF, LOOT_ITEM_CREATED_SELF_MULTIPLE, "created" },
    }
    for _, case in ipairs(cases) do
        local single = addon.Loot.receipt(_G, case[1]:format(link))
        WoWUnit.AreEqual(case[3], single and single.kind)
        WoWUnit.AreEqual(1, single and single.quantity)
        local multiple = addon.Loot.receipt(_G, case[2]:format(link, 4))
        WoWUnit.AreEqual(case[3], multiple and multiple.kind)
        WoWUnit.AreEqual(4, multiple and multiple.quantity)
    end
end

-- Every event and hook the gain rules use registered on this client:
-- LOOT_ITEM_ROLL_WON, QUEST_FINISHED, the guild bank and Black Market events,
-- and the guild bank, vendor and mail hooks.
function tests.EventsAndHooksRegistered(_self)
    WoWUnit.AreEqual("", table.concat(addon.clientIssues or { "clientIssues missing" }, ", "))
end
