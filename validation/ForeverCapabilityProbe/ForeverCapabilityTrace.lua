---@class ForeverCapabilityTraceRecord
---@field scenario string
---@field elapsed number
---@field event string
---@field arguments string[]

---@class ForeverCapabilityBagSnapshot
---@field scenario string
---@field label string
---@field elapsed number
---@field quantities table<string, number>

---@class ForeverCapabilityBankSnapshot
---@field scenario string
---@field label string
---@field elapsed number
---@field slots table<string, number>
---@field quantities table<string, number>

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
    "QUEST_TURNED_IN",
    "QUEST_LOOT_RECEIVED",
    "TRADE_ACCEPT_UPDATE",
    "TRADE_CLOSED",
    "TRADE_PLAYER_ITEM_CHANGED",
    "TRADE_REQUEST_CANCEL",
    "TRADE_SHOW",
    "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_UPDATE",
    "TRADE_SKILL_ITEM_CRAFTED_RESULT",
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

local function safeArguments(...)
    local arguments = {}
    for index = 1, select("#", ...) do
        arguments[index] = safeString(select(index, ...))
    end
    return arguments
end

local function safeField(data, field)
    local ok, value = pcall(function()
        return data[field]
    end)
    if not ok then
        return field .. "=<inaccessible>"
    end
    return field .. "=" .. safeString(value)
end

local function appendTrace(scenario, event, arguments)
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

    if event == "CHAT_MSG_TRADESKILLS" and not scenario:match("^craft") then
        return
    end

    appendTrace(scenario, event, safeArguments(...))

    if event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        local data = ...
        local fields = { "itemID", "itemGUID", "quantity", "hyperlink", "operationID", "firstCraftReward", "isEnchant", "multicraft" }
        local arguments = {}
        for _, field in ipairs(fields) do
            arguments[#arguments + 1] = safeField(data, field)
        end
        appendTrace(scenario, "CRAFT_RESULT_FIELDS", arguments)
    end

    if event == "LOOT_OPENED" and type(GetNumLootItems) == "function" then
        local countOk, slotCount = pcall(GetNumLootItems)
        if countOk and type(slotCount) == "number" then
            for slot = 1, slotCount do
                local linkOk, link = pcall(GetLootSlotLink, slot)
                local sourceOk, sources = pcall(function()
                    return safeArguments(GetLootSourceInfo(slot))
                end)
                local arguments = { tostring(slot), linkOk and safeString(link) or "<link inaccessible>" }
                if sourceOk then
                    for _, source in ipairs(sources) do
                        arguments[#arguments + 1] = source
                    end
                else
                    arguments[#arguments + 1] = "<source inaccessible>"
                end
                appendTrace(scenario, "LOOT_SOURCE_SLOT", arguments)
            end
        end
    end
end)

local function scanContainer(container, quantities)
    local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, container)
    if not slotsOk or type(slots) ~= "number" then
        return nil
    end

    for slot = 1, slots do
        local itemOk, itemID, stackCount = pcall(function()
            local item = C_Container.GetContainerItemInfo(container, slot)
            if item then
                return item.itemID, item.stackCount
            end
        end)
        if itemOk and type(itemID) == "number" and type(stackCount) == "number" then
            local key = tostring(itemID)
            quantities[key] = (quantities[key] or 0) + stackCount
        end
    end
    return slots
end

local function captureBags(label)
    if not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then
        print("Forever trace bag API unavailable")
        return
    end

    local quantities = {}
    for bag = 0, 4 do
        scanContainer(bag, quantities)
    end

    local snapshots = ForeverCapabilityProbeDB.snapshots or {}
    ForeverCapabilityProbeDB.snapshots = snapshots
    snapshots[#snapshots + 1] = {
        scenario = ForeverCapabilityProbeDB.traceScenario or "<stopped>",
        label = label,
        elapsed = GetTime(),
        quantities = quantities,
    }
    local itemKinds = 0
    for _ in pairs(quantities) do
        itemKinds = itemKinds + 1
    end
    print("Forever trace bag snapshot:", label, "items:", itemKinds)
end

local function captureBank(label)
    if not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then
        print("Forever trace bank API unavailable")
        return
    end

    local quantities = {}
    local slots = {}
    local mainSlots = scanContainer(-1, quantities)
    if mainSlots then
        slots["-1"] = mainSlots
    end
    for container = 5, 11 do
        local containerSlots = scanContainer(container, quantities)
        if containerSlots then
            slots[tostring(container)] = containerSlots
        end
    end
    local snapshots = ForeverCapabilityProbeDB.bankSnapshots or {}
    ForeverCapabilityProbeDB.bankSnapshots = snapshots
    snapshots[#snapshots + 1] = {
        scenario = ForeverCapabilityProbeDB.traceScenario or "<stopped>",
        label = label,
        elapsed = GetTime(),
        slots = slots,
        quantities = quantities,
    }
    print("Forever trace bank snapshot:", label, "main slots:", slots["-1"] or "<unreadable>")
    print("Forever trace bank bag 6 slots:", slots["6"] or "<unreadable>")
end

SLASH_FOREVERCAPABILITYTRACE1 = "/fpt"
SlashCmdList.FOREVERCAPABILITYTRACE = function(message)
    local scenario = message:match("^start%s+([%w_-]+)$")
    local snapshotLabel = message:match("^snap%s+([%w_-]+)$")
    local bankLabel = message:match("^bank%s+([%w_-]+)$")
    if scenario then
        ForeverCapabilityProbeDB.traceScenario = scenario
        print("Forever trace started:", scenario)
    elseif snapshotLabel then
        captureBags(snapshotLabel)
    elseif bankLabel then
        captureBank(bankLabel)
    elseif message == "stop" then
        ForeverCapabilityProbeDB.traceScenario = nil
        print("Forever trace stopped; records:", #(ForeverCapabilityProbeDB.traces or {}))
    elseif message == "clear" then
        ForeverCapabilityProbeDB.traceScenario = nil
        ForeverCapabilityProbeDB.traces = {}
        ForeverCapabilityProbeDB.snapshots = {}
        ForeverCapabilityProbeDB.bankSnapshots = {}
        print("Forever trace records cleared")
    elseif message == "status" then
        print("Forever trace scenario:", ForeverCapabilityProbeDB.traceScenario or "<stopped>")
        print("Forever trace records:", #(ForeverCapabilityProbeDB.traces or {}))
    else
        print("Forever trace: /fpt start <scenario>, /fpt snap <label>, /fpt bank <label>, /fpt stop, /fpt clear, or /fpt status")
    end
end
