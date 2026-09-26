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
                local source
                local slotQuantity
                if type(api.GetLootSlotInfo) == "function" then
                    local infoOK, _, _, quantity = pcall(api.GetLootSlotInfo, slot)
                    if infoOK and type(quantity) == "number" and quantity > 0 and quantity == math.floor(quantity) then
                        slotQuantity = quantity
                    end
                end
                if type(api.GetLootSourceInfo) == "function" then
                    local sourceOK, guid, quantity, other = pcall(api.GetLootSourceInfo, slot)
                    if sourceOK and type(guid) == "string" and type(quantity) == "number" and other == nil then
                        if not slotQuantity and quantity > 0 and quantity == math.floor(quantity) then
                            slotQuantity = quantity
                        end
                        local kind = guid:match("^([^-]+)%-")
                        if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
                            source = { kind = kind == "GameObject" and "container" or "mob", guid = guid }
                            if
                                kind ~= "GameObject"
                                and type(api.UnitGUID) == "function"
                                and type(api.UnitName) == "function"
                            then
                                local targetOK, targetGUID = pcall(api.UnitGUID, "target")
                                if targetOK and targetGUID == guid then
                                    local nameOK, name = pcall(api.UnitName, "target")
                                    if nameOK and type(name) == "string" and name ~= "" then
                                        source.name = name
                                    end
                                end
                            end
                        end
                    end
                end
                slots[#slots + 1] = { key = key, source = source, quantity = slotQuantity }
            end
        end
    end
    return slots
end

addon.Loot = Loot
