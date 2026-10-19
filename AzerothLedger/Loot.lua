local _, addon = ...

-- The loot channel: the loot window, its slot sources, and loot chat receipts.
-- A receipt while a merchant window is open is a vendor purchase, not loot.
local Loot = {}

---@class AzerothLedgerLootApi
---@field LOOT_ITEM_SELF? string
---@field LOOT_ITEM_SELF_MULTIPLE? string
---@field LOOT_ITEM_PUSHED_SELF? string
---@field LOOT_ITEM_PUSHED_SELF_MULTIPLE? string
---@field LOOT_ITEM_CREATED_SELF? string
---@field LOOT_ITEM_CREATED_SELF_MULTIPLE? string
---@field GetNumLootItems? fun(): integer
---@field GetLootSlotLink? fun(slot: integer): string?
---@field GetLootSlotInfo? fun(slot: integer): any, any, integer?
---@field GetLootSourceInfo? fun(slot: integer): string?, integer?, string?
---@field UnitGUID? fun(unit: string): string?
---@field UnitName? fun(unit: string): string?
---@field C_TooltipInfo? {GetWorldCursor?: fun(): table?}
---@field C_Item? {GetItemLinkByGUID?: fun(guid: string): string?}
---@field Enum? {TooltipDataType?: {Object?: integer}}
---@field issecretvalue? fun(value: any): boolean

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

-- The player's own item receipts: loot taken, an item handed over (a purchase,
-- mail, a quest or an NPC), and an item made by a recipe or spell.
local receiptFormats = {
    { kind = "loot", single = "LOOT_ITEM_SELF", multiple = "LOOT_ITEM_SELF_MULTIPLE" },
    { kind = "pushed", single = "LOOT_ITEM_PUSHED_SELF", multiple = "LOOT_ITEM_PUSHED_SELF_MULTIPLE" },
    { kind = "created", single = "LOOT_ITEM_CREATED_SELF", multiple = "LOOT_ITEM_CREATED_SELF_MULTIPLE" },
}

local function pack(...)
    return { n = select("#", ...), ... }
end

-- An item opened from the bags is the source of its own loot.
local function itemSource(api, guid)
    local result = { kind = "item", guid = guid }
    local read = api.C_Item and api.C_Item.GetItemLinkByGUID
    local ok, link = false, nil
    if type(read) == "function" then
        ok, link = pcall(read, guid)
    end
    local itemID = ok and type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
    local name = itemID and link:match("|h%[(.-)%]|h")
    if itemID and itemID > 0 and itemID == math.floor(itemID) then
        result.itemID = itemID
        if type(name) == "string" and name ~= "" and #name <= 128 then
            result.name = name
        end
    end
    return result
end

local function source(api, guid)
    local kind = type(guid) == "string" and guid:match("^([^-]+)%-")
    if kind == "Item" then
        return itemSource(api, guid)
    end
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
    local link, quantity, kind
    for _, format in ipairs(receiptFormats) do
        local pattern = receiptPattern(api[format.multiple])
        if pattern then
            link, quantity = message:match(pattern)
        end
        if not link then
            pattern = receiptPattern(api[format.single])
            link = pattern and message:match(pattern) or nil
            quantity = 1
        end
        if link then
            kind = format.kind
            break
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
    return key and { key = key, itemID = itemID, link = link, quantity = quantity, kind = kind } or nil
end

-- A cast's object name names the loot only when one object is its only
-- unnamed GameObject source; two objects in one window cannot be told apart.
local function nameObject(slots, castName)
    local guid
    for _, slot in ipairs(slots) do
        local from = slot.source
        if from and from.kind == "container" then
            if guid and guid ~= from.guid then
                return
            end
            guid = from.guid
        end
    end
    for _, slot in ipairs(slots) do
        if slot.source and slot.source.guid == guid and not slot.source.name then
            slot.source.name = castName
        end
    end
end

---@param api AzerothLedgerLootApi
---@param castName? string The object a just-finished cast was aimed at
---@return AzerothLedgerLootSlot[]?
function Loot.open(api, castName)
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
    if castName then
        nameObject(slots, castName)
    end
    return slots
end

-- The store commands this channel writes through.
---@type ALCommandName[]
Loot.commands = { "lootOpen", "lootSourceProof", "lootClose", "lootReceipt", "vendorReceipt" }

---@class ALLootDependencies
---@field api AzerothLedgerLootApi
---@field commands ALCommands Built from `Loot.commands`
---@field refresh fun(character: string, realm: string)
---@field merchantOpen fun(): boolean
---@field received fun(receipt: AzerothLedgerLootReceipt) An item handed over or made outside a merchant
---@field clock fun(): integer?

---@param deps ALLootDependencies
function Loot.new(deps)
    local api, commands, refresh = deps.api, deps.commands, deps.refresh
    -- Fast loot can finish at LOOT_READY; LOOT_OPENED must keep that pre-gain baseline.
    local captured = false
    -- Loot lines no window matched, by item key, for a roll reported after them.
    local unplaced = {}
    -- Mining, herb gathering and opening are casts aimed at the object, and
    -- UNIT_SPELLCAST_SENT names it. The cast must finish just before the loot.
    local pending, finished

    local function castTarget(name)
        if type(api.issecretvalue) == "function" and api.issecretvalue(name) then
            return nil
        elseif type(name) ~= "string" or name == "" or #name > 128 then
            return nil
        end
        if type(api.UnitName) == "function" then
            for _, unit in ipairs({ "player", "target", "focus", "mouseover" }) do
                local ok, unitName = pcall(api.UnitName, unit)
                if ok and unitName == name then
                    return nil
                end
            end
        end
        return name
    end

    local function castName()
        local at = finished and deps.clock()
        if at and at - finished.at >= 0 and at - finished.at <= 3 then
            return finished.name
        end
        return nil
    end

    local function castEnded(unit, castGUID)
        if unit == "player" and pending and pending.castGUID == castGUID then
            pending = nil
        end
    end

    local function proveSources(slots)
        local proven, context = commands.lootSourceProof({ slots = slots })
        if proven and context then
            refresh(context.character, context.realm)
        end
    end

    local function opened()
        local slots = Loot.open(api, castName())
        if not slots then
            return
        end
        if captured then
            proveSources(slots)
        elseif #slots > 0 then
            captured = commands.lootOpen({ slots = slots }) == true
        end
    end

    local function receipt(message)
        local parsed = Loot.receipt(api, message)
        if not parsed then
            return
        end
        local write
        if deps.merchantOpen() and parsed.kind ~= "created" then
            write = commands.vendorReceipt
        elseif parsed.kind == "loot" then
            write = commands.lootReceipt
        else
            deps.received(parsed)
            return
        end
        local accepted, context = write(parsed)
        if accepted and context then
            refresh(context.character, context.realm)
        elseif write == commands.lootReceipt then
            unplaced[parsed.key] = { receipt = parsed, at = deps.clock() }
        end
    end

    -- A roll you won proves the item as a loot window would, so it opens a
    -- one-slot cycle for the loot line that comes with it.
    local function rollWon(link, quantity)
        local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
        local key = itemID and addon.Item.key(link, itemID)
        if not key then
            return
        end
        if type(quantity) ~= "number" or quantity < 1 or quantity ~= math.floor(quantity) then
            quantity = nil
        end
        if not commands.lootOpen({ slots = { { key = key, quantity = quantity } } }) then
            return
        end
        local held, at = unplaced[key], deps.clock()
        unplaced[key] = nil
        if held and held.at and at and at - held.at <= 10 then
            local accepted, context = commands.lootReceipt(held.receipt)
            if accepted and context then
                refresh(context.character, context.realm)
            end
        end
    end

    return {
        events = {
            LOOT_READY = opened,
            LOOT_OPENED = opened,
            LOOT_SLOT_CHANGED = function()
                local slots = Loot.open(api, castName())
                if slots then
                    proveSources(slots)
                end
            end,
            LOOT_CLOSED = function()
                captured, finished = false, nil
                commands.lootClose()
            end,
            CHAT_MSG_LOOT = receipt,
            LOOT_ITEM_ROLL_WON = rollWon,
            UNIT_SPELLCAST_SENT = function(unit, target, castGUID)
                if unit == "player" then
                    local name = castTarget(target)
                    pending = name and { castGUID = castGUID, name = name } or nil
                end
            end,
            UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID)
                if unit == "player" and pending and pending.castGUID == castGUID then
                    local at = deps.clock()
                    finished = at and { name = pending.name, at = at } or nil
                    pending = nil
                end
            end,
            UNIT_SPELLCAST_FAILED = castEnded,
            UNIT_SPELLCAST_INTERRUPTED = castEnded,
        },
    }
end

addon.Loot = Loot
