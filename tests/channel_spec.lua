local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("Runtime")
-- Each channel is built from only the dependencies it declares: reaching for
-- any other dependency or store command fails the spec.
local bread = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local actor = { character = "Ada", realm = "Realm" }

local function strict(label, values)
    return setmetatable(values, {
        __index = function(_, name)
            error(label .. " has no " .. tostring(name), 2)
        end,
    })
end

-- Store commands that record each write and accept it as the acting character.
local function commands(names, calls)
    local list = {}
    for _, name in ipairs(names) do
        list[name] = function(payload, context)
            calls[#calls + 1] = { name = name, payload = payload, context = context }
            return #calls, context or actor
        end
    end
    return strict("store commands", list)
end

local function named(calls, name)
    for _, call in ipairs(calls) do
        if call.name == name then
            return call
        end
    end
end

local player = {
    GetServerTime = function()
        return 1000
    end,
    UnitName = function(unit)
        return unit == "player" and "Ada" or "Dermot Johns"
    end,
    GetRealmName = function()
        return "Realm"
    end,
    UnitLevel = function()
        return 12
    end,
    GetRealZoneText = function()
        return "Elwynn Forest"
    end,
}
local function client(reads)
    for name, value in pairs(player) do
        reads[name] = reads[name] or value
    end
    return reads
end
local function clock()
    return 1000
end

-- Loot: the loot window and its chat receipts.
local calls, refreshed, merchantOpen = {}, {}, false
local loot = addon.Loot.new(strict("loot dependencies", {
    api = client({
        GetNumLootItems = function()
            return 1
        end,
        GetLootSlotLink = function()
            return bread
        end,
        LOOT_ITEM_SELF = "You receive loot: %s.",
    }),
    commands = commands(addon.Loot.commands, calls),
    refresh = function(character, realm)
        refreshed[#refreshed + 1] = character .. "-" .. realm
    end,
    merchantOpen = function()
        return merchantOpen
    end,
}))
loot.events.LOOT_READY()
assert(named(calls, "lootOpen").payload.slots[1].key == "4540:0", "an opened loot window records its slots")
loot.events.CHAT_MSG_LOOT("You receive loot: " .. bread .. ".")
assert(named(calls, "lootReceipt") and refreshed[1] == "Ada-Realm", "a loot receipt refreshes the Collection")
merchantOpen = true
loot.events.CHAT_MSG_LOOT("You receive loot: " .. bread .. ".")
assert(named(calls, "vendorReceipt"), "a receipt while a merchant is open is a vendor purchase")
loot.events.LOOT_CLOSED()
assert(named(calls, "lootClose"), "closing the loot window ends the loot")

-- Quest and craft rewards.
local checks
calls, refreshed, checks = {}, {}, {}
local reward = addon.Reward.new(strict("reward dependencies", {
    api = client({
        C_TradeSkillUI = {
            GetRecipeInfo = function()
                return { name = "Bread" }
            end,
        },
    }),
    clock = clock,
    commands = commands(addon.Reward.commands, calls),
    check = function(area)
        checks[#checks + 1] = area
    end,
    refresh = function(character, realm)
        refreshed[#refreshed + 1] = character .. "-" .. realm
    end,
}))
reward.events.TRADE_SKILL_CRAFT_BEGIN(2963)
reward.events.TRADE_SKILL_ITEM_CRAFTED_RESULT({ itemID = 4540, hyperlink = bread, quantity = 1 })
local crafted = named(calls, "rewardReceipt").payload
assert(crafted.method == "Crafted" and crafted.context.name == "Bread", "a craft names its recipe")
assert(refreshed[1] == "Ada-Realm" and #checks == 0, "a craft refreshes the Collection; bags prove the gain later")
reward.events.QUEST_TURNED_IN(42)
assert(named(calls, "questTurnedIn").payload == 42 and checks[1] == "possessions", "a turn-in checks possessions")

-- Vendor actions while a merchant window is open.
calls, refreshed, checks = {}, {}, {}
local hooks, issues = {}, {}
local vendorApi = client({
    GetMerchantItemLink = function()
        return bread
    end,
    C_MerchantFrame = {
        GetItemInfo = function()
            return { stackCount = 1 }
        end,
    },
    BuyMerchantItem = function() end,
    hooksecurefunc = function(target, method, callback)
        hooks[method] = callback
        assert(target, "a vendor hook names the client table it hooks")
    end,
})
local vendor = addon.Vendor.new(strict("vendor dependencies", {
    api = vendorApi,
    clock = clock,
    issues = issues,
    commands = commands(addon.Vendor.commands, calls),
    check = function(area)
        checks[#checks + 1] = area
    end,
    refresh = function(character, realm)
        refreshed[#refreshed + 1] = character .. "-" .. realm
    end,
}))
vendor.events.MERCHANT_SHOW()
assert(vendor.isOpen() and checks[1] == "bags" and checks[2] == "equipped", "opening a merchant checks possessions")
hooks.BuyMerchantItem(1, 2)
local action = named(calls, "vendorAction")
assert(action.payload.quantity == 2 and action.context.vendorName == "Dermot Johns", "a purchase names its vendor")
assert(refreshed[1] == "Ada-Realm", "a recorded purchase refreshes the Collection")

-- Trade: both sides recorded on acceptance, confirmed by the trade-complete message.
calls, checks = {}, {}
local exchange = addon.Exchange.new(strict("exchange dependencies", {
    api = client({
        GetTradeTargetItemLink = function(slot)
            return slot == 1 and bread or nil
        end,
        GetTradeTargetItemInfo = function(slot)
            return nil, nil, slot == 1 and 2 or nil
        end,
        GetTradePlayerItemLink = function() end,
        GetTradePlayerItemInfo = function() end,
        ERR_TRADE_COMPLETE = "Trade complete.",
        C_Timer = {
            After = function(_, callback)
                callback()
            end,
        },
    }),
    issues = issues,
    commands = commands(addon.Exchange.commands, calls),
    mailProgress = function()
        return "complete"
    end,
    check = function(area)
        checks[#checks + 1] = area
    end,
}))
exchange.events.TRADE_SHOW()
assert(named(calls, "exchangeCancel").payload == "trade", "a new trade window ends the previous one")
exchange.events.TRADE_ACCEPT_UPDATE(1, 1)
assert(named(calls, "exchangeIntent").payload.quantity == 2, "an accepted trade records what the partner gives")
exchange.events.UI_INFO_MESSAGE(nil, "Trade complete.")
assert(named(calls, "exchangeConfirm").payload.channel == "trade", "a completed trade confirms the exchange")
assert(checks[#checks] == "bags", "a confirmed exchange checks bags for the traded items")

-- The server completes a trade when the second player accepts, so the client
-- may never report both accepted: one acceptance prepares the items.
local function count(name)
    local total = 0
    for _, call in ipairs(calls) do
        total = total + (call.name == name and 1 or 0)
    end
    return total
end
exchange.events.TRADE_SHOW()
local intents, confirms = count("exchangeIntent"), count("exchangeConfirm")
exchange.events.TRADE_ACCEPT_UPDATE(0, 1)
assert(count("exchangeIntent") > intents, "the partner's acceptance records the trade")
exchange.events.UI_INFO_MESSAGE(nil, "Trade complete.")
assert(count("exchangeConfirm") > confirms, "the trade completed on your acceptance")

-- An acceptance withdrawn ends the prepared items.
exchange.events.TRADE_SHOW()
local cancels = count("exchangeCancel")
exchange.events.TRADE_ACCEPT_UPDATE(1, 0)
exchange.events.TRADE_ACCEPT_UPDATE(0, 0)
assert(count("exchangeCancel") > cancels, "a withdrawn acceptance cancels the prepared trade")

-- A partner who cancels after your acceptance closes the window with no trade.
exchange.events.TRADE_SHOW()
cancels = count("exchangeCancel")
exchange.events.TRADE_ACCEPT_UPDATE(1, 0)
exchange.events.TRADE_CLOSED()
assert(count("exchangeCancel") > cancels, "a closed window with no completed trade cancels it")

print("channel_spec: passed")
