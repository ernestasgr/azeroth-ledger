---@class ForeverCapabilityTraceRecord
---@field scenario string
---@field elapsed number
---@field event string
---@field arguments string[]

local events = {
    "BAG_UPDATE",
    "BAG_UPDATE_DELAYED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_TRADESKILLS",
    "ITEM_DATA_LOAD_RESULT",
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "MAIL_INBOX_UPDATE",
    "MAIL_SUCCESS",
    "MAIL_SEND_SUCCESS",
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "MERCHANT_UPDATE",
    "PLAYERBANKSLOTS_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_MONEY",
    "PLAYERREAGENTBANKSLOTS_CHANGED",
    "QUEST_TURNED_IN",
    "QUEST_LOOT_RECEIVED",
    "TRADE_ACCEPT_UPDATE",
    "TRADE_CLOSED",
    "TRADE_PLAYER_ITEM_CHANGED",
    "TRADE_SHOW",
    "TRADE_TARGET_ITEM_CHANGED",
    "UNIT_INVENTORY_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
}

local function safeString(value)
    local ok, result = pcall(tostring, value)
    if not ok then
        return "<inaccessible>"
    end
    return result:sub(1, 240)
end

local frame = CreateFrame("Frame")
for _, event in ipairs(events) do
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        print("Forever trace unsupported event:", event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local scenario = ForeverCapabilityProbeDB.traceScenario
    if not scenario then
        return
    end

    local arguments = {}
    for index = 1, select("#", ...) do
        arguments[index] = safeString(select(index, ...))
    end

    local traces = ForeverCapabilityProbeDB.traces or {}
    ForeverCapabilityProbeDB.traces = traces
    traces[#traces + 1] = {
        scenario = scenario,
        elapsed = GetTime(),
        event = event,
        arguments = arguments,
    }
    if #traces > 500 then
        table.remove(traces, 1)
    end
end)

SLASH_FOREVERCAPABILITYTRACE1 = "/fpt"
SlashCmdList.FOREVERCAPABILITYTRACE = function(message)
    local scenario = message:match("^start%s+([%w_-]+)$")
    if scenario then
        ForeverCapabilityProbeDB.traceScenario = scenario
        print("Forever trace started:", scenario)
    elseif message == "stop" then
        ForeverCapabilityProbeDB.traceScenario = nil
        print("Forever trace stopped; records:", #(ForeverCapabilityProbeDB.traces or {}))
    elseif message == "status" then
        print("Forever trace scenario:", ForeverCapabilityProbeDB.traceScenario or "<stopped>")
        print("Forever trace records:", #(ForeverCapabilityProbeDB.traces or {}))
    else
        print("Forever trace: /fpt start <scenario>, /fpt stop, or /fpt status")
    end
end
