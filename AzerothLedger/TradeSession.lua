local _, addon = ...
addon.Sessions = addon.Sessions or {}

-- Items exchanged in the trade window. Both sides are recorded once both players
-- accept, and confirmed only by the client's trade-complete message. Any item
-- change after acceptance cancels the prepared intents.
local TradeSession = {}

-- The trade partner, read when the window opens.
local function partner(api, localRealm)
    local read = rawget(api, "GetUnitName")
    if type(read) ~= "function" then
        return nil
    end
    local ok, name = pcall(read, "NPC", true)
    return ok and addon.Exchange.player(name, nil, localRealm) or nil
end

local function isTradeComplete(api, messageID, message)
    local completed = rawget(api, "ERR_TRADE_COMPLETE")
    return type(completed) == "string" and (message == completed or messageID == completed)
end

---@param runtime ALRuntime
function TradeSession.new(runtime)
    local api = runtime.api
    local open, prepared = false, false
    local preparedIDs, peer

    local function cancel()
        runtime.command("exchangeCancel", "trade")
    end

    local function prepare()
        if not open or prepared then
            return
        end
        preparedIDs = {}
        for _, direction in ipairs({ "in", "out" }) do
            for _, intent in ipairs(addon.Exchange.trade(api, direction, peer) or {}) do
                local id = runtime.exchangeIntent(intent)
                if id then
                    preparedIDs[id] = true
                end
            end
        end
        prepared = true
    end

    local function itemChanged()
        if prepared then
            cancel()
        end
        prepared, preparedIDs = false, nil
    end

    return {
        events = {
            TRADE_SHOW = function()
                open, prepared, preparedIDs = true, false, nil
                cancel()
                runtime.inventory:check("bags")
                local _, realm = runtime.identity()
                peer = partner(api, realm)
            end,
            TRADE_PLAYER_ITEM_CHANGED = itemChanged,
            TRADE_TARGET_ITEM_CHANGED = itemChanged,
            TRADE_ACCEPT_UPDATE = function(playerAccepted, targetAccepted)
                if playerAccepted == 1 and targetAccepted == 1 then
                    prepare()
                end
            end,
            TRADE_CLOSED = function()
                open = false
            end,
            UI_INFO_MESSAGE = function(messageID, message)
                if prepared and isTradeComplete(api, messageID, message) then
                    runtime.exchangeConfirm("trade", "in", preparedIDs)
                    runtime.exchangeConfirm("trade", "out", preparedIDs)
                    prepared, preparedIDs = false, nil
                end
            end,
        },
    }
end

addon.Sessions.Trade = TradeSession
