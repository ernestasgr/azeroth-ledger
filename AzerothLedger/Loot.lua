local _, addon = ...

local Loot = {}

---@class AzerothLedgerLootApi
---@field LOOT_ITEM_SELF? string
---@field LOOT_ITEM_SELF_MULTIPLE? string
---@field GetNumLootItems? fun(): integer
---@field GetLootSlotLink? fun(slot: integer): string?
---@field GetLootSlotInfo? fun(slot: integer): any, any, integer?
---@field GetLootSourceInfo? fun(slot: integer): string?, integer?, string?
---@field UnitGUID? fun(unit: string): string?
---@field UnitName? fun(unit: string): string?
---@field C_TooltipInfo? {GetWorldCursor?: fun(): table?}
---@field Enum? {TooltipDataType?: {Object?: integer}}

local function escape(text)
    return (text:gsub("([^%w])", "%%%1"))
end

local function receiptPattern(formatString)
    if type(formatString) ~= "string" then
        return nil
    end
    local pattern = escape(formatString)
    pattern = pattern:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function source(api, guid)
    local kind = type(guid) == "string" and guid:match("^([^-]+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" and kind ~= "GameObject" then
        return nil
    end
    local result = { kind = kind == "GameObject" and "container" or "mob", guid = guid }
    if type(api.UnitGUID) == "function" and type(api.UnitName) == "function" then
        for _, unit in ipairs({ "target", "npc", "mouseover" }) do
            local unitOK, unitGUID = pcall(api.UnitGUID, unit)
            if unitOK and unitGUID == guid then
                local nameOK, name = pcall(api.UnitName, unit)
                if nameOK and type(name) == "string" and name ~= "" and #name <= 128 then
                    result.name = name
                    return result
                end
            end
        end
    end
    local tooltipInfo = api.C_TooltipInfo
    local objectType = api.Enum and api.Enum.TooltipDataType and api.Enum.TooltipDataType.Object
    if kind == "GameObject" and objectType and tooltipInfo and type(tooltipInfo.GetWorldCursor) == "function" then
        local tooltipOK, data = pcall(tooltipInfo.GetWorldCursor)
        -- A hovered name is evidence only when the tooltip proves this exact
        -- looted object, not merely something nearby under the cursor.
        if tooltipOK and type(data) == "table" and data.type == objectType and data.guid == guid then
            local first = type(data.lines) == "table" and data.lines[1]
            local name = type(first) == "table" and first.leftText
            if type(name) == "string" and name ~= "" and #name <= 128 then
                result.name = name
            end
        end
    end
    return result
end

local function sourceShares(api, slot, key, slotQuantity)
    if type(api.GetLootSourceInfo) ~= "function" then
        return nil
    end
    local ok, values = pcall(function()
        return pack(api.GetLootSourceInfo(slot))
    end)
    if not ok or values.n == 0 or values.n > 200 or values.n % 2 ~= 0 then
        return nil
    end
    local result = {}
    local total = 0
    local commonGUID, sameSource = nil, true
    for index = 1, values.n, 2 do
        local guid, quantity = values[index], values[index + 1]
        if
            type(guid) ~= "string"
            or type(quantity) ~= "number"
            or quantity <= 0
            or quantity == math.huge
            or quantity ~= math.floor(quantity)
        then
            return nil
        end
        total = total + quantity
        if commonGUID == nil then
            commonGUID = guid
        elseif commonGUID ~= guid then
            sameSource = false
        end
        result[#result + 1] = {
            key = key,
            quantity = quantity,
            source = source(api, guid),
            slot = slot,
            sourceIndex = (index + 1) / 2,
        }
    end
    if slotQuantity and slotQuantity ~= total then
        local onlySource = result[1] and result[1].source
        -- A count mismatch cannot split the stack safely, but it can retain
        -- provenance when every listed share names the same source.
        if sameSource and onlySource then
            return {
                {
                    key = key,
                    quantity = slotQuantity,
                    source = onlySource,
                    slot = slot,
                    sourceIndex = 1,
                },
            }
        end
        return nil
    end
    return result
end

---@param api AzerothLedgerLootApi
---@param message string
---@return AzerothLedgerLootReceipt?
function Loot.receipt(api, message)
    if type(message) ~= "string" then
        return nil
    end
    local link, quantity
    local multiple = receiptPattern(api.LOOT_ITEM_SELF_MULTIPLE)
    if multiple then
        link, quantity = message:match(multiple)
    end
    if not link then
        local single = receiptPattern(api.LOOT_ITEM_SELF)
        if single then
            link = message:match(single)
            quantity = 1
        end
    end
    if not link then
        return nil
    end
    local itemID = tonumber(link:match("|Hitem:(%d+)"))
    quantity = tonumber(quantity)
    if not itemID or not quantity or quantity < 1 or quantity ~= math.floor(quantity) then
        return nil
    end
    local key = addon.Item.key(link, itemID)
    return key and { key = key, itemID = itemID, link = link, quantity = quantity } or nil
end

---@param api AzerothLedgerLootApi
---@return AzerothLedgerLootSlot[]?
function Loot.open(api)
    if type(api.GetNumLootItems) ~= "function" or type(api.GetLootSlotLink) ~= "function" then
        return nil
    end
    local ok, count = pcall(api.GetNumLootItems)
    if not ok or type(count) ~= "number" or count < 0 or count > 100 then
        return nil
    end
    local slots = {}
    for slot = 1, count do
        local linkOK, link = pcall(api.GetLootSlotLink, slot)
        if linkOK and type(link) == "string" then
            local itemID = tonumber(link:match("|Hitem:(%d+)"))
            local key = itemID and addon.Item.key(link, itemID)
            if key then
                local slotQuantity
                if type(api.GetLootSlotInfo) == "function" then
                    local infoOK, _, _, quantity = pcall(api.GetLootSlotInfo, slot)
                    if infoOK and type(quantity) == "number" and quantity > 0 and quantity == math.floor(quantity) then
                        slotQuantity = quantity
                    end
                end
                local shares = sourceShares(api, slot, key, slotQuantity)
                if shares then
                    for _, share in ipairs(shares) do
                        slots[#slots + 1] = share
                    end
                else
                    slots[#slots + 1] = { key = key, quantity = slotQuantity, slot = slot, sourceIndex = 1 }
                end
            end
        end
    end
    return slots
end

addon.Loot = Loot
