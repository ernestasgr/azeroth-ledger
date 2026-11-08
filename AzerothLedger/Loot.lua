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

-- A client read as a plain value of the given Lua type, or nil. A secret
-- value throws when compared, measured or indexed, so it reads as nothing.
---@param api AzerothLedgerLootApi
---@param value any
---@param kind string
local function plain(api, value, kind)
    if type(api.issecretvalue) == "function" and api.issecretvalue(value) then
        return nil
    end
    return type(value) == kind and value or nil
end

-- An item opened from the bags is the source of its own loot.
local function itemSource(api, guid)
    local result = { kind = "item", guid = guid }
    local read = api.C_Item and api.C_Item.GetItemLinkByGUID
    local ok, link = false, nil
    if type(read) == "function" then
        ok, link = pcall(read, guid)
    end
    local text = ok and plain(api, link, "string") or nil
    if not text then
        return result
    end
    local itemID = tonumber(text:match("|Hitem:(%d+)"))
    local name = text:match("|h%[(.-)%]|h")
    if itemID and itemID > 0 and itemID == math.floor(itemID) then
        result.itemID = itemID
        if type(name) == "string" and name ~= "" and #name <= 128 then
            result.name = name
        end
    end
    return result
end

-- The creature entry a Creature or Vehicle GUID names. Every spawn of one
-- entry shares its name, so a name read from one spawn names the others.
local function creatureEntry(guid)
    local kind, entry = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    return (kind == "Creature" or kind == "Vehicle") and entry or nil
end

local function validName(name)
    return name and name ~= "" and #name <= 128 and name or nil
end

---@param creatureNames? table<string, string> Names read earlier, by creature entry
local function source(api, guid, creatureNames)
    guid = plain(api, guid, "string")
    local kind = guid and guid:match("^([^-]+)%-")
    if kind == "Item" then
        return itemSource(api, guid)
    end
    if kind ~= "Creature" and kind ~= "Vehicle" and kind ~= "GameObject" then
        return nil
    end
    local result = { kind = kind == "GameObject" and "container" or "mob", guid = guid }
    if type(api.UnitGUID) == "function" and type(api.UnitName) == "function" then
        for _, unit in ipairs({ "target", "npc", "mouseover", "softinteract" }) do
            local unitOK, unitGUID = pcall(api.UnitGUID, unit)
            if unitOK and plain(api, unitGUID, "string") == guid then
                local nameOK, name = pcall(api.UnitName, unit)
                name = nameOK and plain(api, name, "string")
                if name and name ~= "" and #name <= 128 then
                    result.name = name
                    return result
                end
            end
        end
    end
    -- In combat unit reads are secret, but a name read earlier still holds.
    local learned = creatureNames and creatureNames[creatureEntry(guid) or ""]
    if learned then
        result.name = learned
        return result
    end
    local tooltipInfo = api.C_TooltipInfo
    local objectType = api.Enum and api.Enum.TooltipDataType and api.Enum.TooltipDataType.Object
    if kind == "GameObject" and objectType and tooltipInfo and type(tooltipInfo.GetWorldCursor) == "function" then
        local tooltipOK, data = pcall(tooltipInfo.GetWorldCursor)
        -- A hovered name is evidence only when the tooltip proves this exact
        -- looted object, not merely something nearby under the cursor.
        if
            tooltipOK
            and plain(api, data, "table")
            and plain(api, data.type, "number") == objectType
            and plain(api, data.guid, "string") == guid
        then
            local lines = plain(api, data.lines, "table")
            local first = lines and plain(api, lines[1], "table")
            local name = first and plain(api, first.leftText, "string")
            if name and name ~= "" and #name <= 128 then
                result.name = name
            end
        end
    end
    return result
end

local function sourceShares(api, slot, key, slotQuantity, creatureNames)
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
        local guid, quantity = plain(api, values[index], "string"), plain(api, values[index + 1], "number")
        if not guid or not quantity or quantity <= 0 or quantity == math.huge or quantity ~= math.floor(quantity) then
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
            source = source(api, guid, creatureNames),
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
    if not plain(api, message, "string") then
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
---@param creatureNames? table<string, string> Names read earlier, by creature entry
---@return AzerothLedgerLootSlot[]?
function Loot.open(api, castName, creatureNames)
    if type(api.GetNumLootItems) ~= "function" or type(api.GetLootSlotLink) ~= "function" then
        return nil
    end
    local ok, read = pcall(api.GetNumLootItems)
    local count = ok and plain(api, read, "number") or nil
    if not count or count < 0 or count > 100 then
        return nil
    end
    local slots = {}
    for slot = 1, count do
        local linkOK, slotLink = pcall(api.GetLootSlotLink, slot)
        local link = linkOK and plain(api, slotLink, "string") or nil
        if link then
            local itemID = tonumber(link:match("|Hitem:(%d+)"))
            local key = itemID and addon.Item.key(link, itemID)
            if key then
                local slotQuantity
                if type(api.GetLootSlotInfo) == "function" then
                    local infoOK, _, _, info = pcall(api.GetLootSlotInfo, slot)
                    local quantity = infoOK and plain(api, info, "number") or nil
                    if quantity and quantity > 0 and quantity == math.floor(quantity) then
                        slotQuantity = quantity
                    end
                end
                local shares = sourceShares(api, slot, key, slotQuantity, creatureNames)
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

-- What one window says about each item's source: the source, `false` when its
-- shares disagree or only some are readable, and nothing when none is readable.
local function windowSources(slots)
    local read = {}
    for _, slot in ipairs(slots) do
        ---@type {unreadable: boolean, source?: AzerothLedgerLootSource|false}
        local entry = read[slot.key] or { unreadable = false }
        read[slot.key] = entry
        if not slot.source then
            entry.unreadable = true
        elseif entry.source == nil or (entry.source and entry.source.guid == slot.source.guid) then
            entry.source = slot.source
        else
            entry.source = false
        end
    end
    local result = {}
    for key, entry in pairs(read) do
        if entry.source ~= nil then
            result[key] = not entry.unreadable and entry.source
        end
    end
    return result
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
---@field spellGave fun(): boolean Whether your cast just finished, so a handed-over item is the spell's
---@field clock fun(): integer?

---@param deps ALLootDependencies
function Loot.new(deps)
    local api, commands, refresh = deps.api, deps.commands, deps.refresh
    -- Fast loot can finish at LOOT_READY; LOOT_OPENED must keep that pre-gain baseline.
    local captured = false
    -- Loot lines no window matched, by item key, for a roll reported after them.
    local unplaced = {}
    -- The source each item key showed in recent loot windows, for a roll won
    -- later. `false` marks a key two different sources showed.
    local shown = {}
    -- Mining, herb gathering and opening are casts aimed at the object, and
    -- UNIT_SPELLCAST_SENT names it. The cast must finish just before the loot.
    local pending, finished
    -- Creature names read while unit reads were plain, by creature entry.
    local creatureNames = {}

    local function learnName(unit)
        if type(api.UnitGUID) ~= "function" or type(api.UnitName) ~= "function" then
            return
        end
        local guidOK, guid = pcall(api.UnitGUID, unit)
        guid = guidOK and plain(api, guid, "string") or nil
        local entry = guid and creatureEntry(guid)
        if not entry then
            return
        end
        local nameOK, name = pcall(api.UnitName, unit)
        name = validName(nameOK and plain(api, name, "string") or nil)
        if name then
            creatureNames[entry] = name
        end
    end

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

    -- Group loot rolls end within a few minutes of the window that showed them.
    local ROLL_SOURCE_SECONDS = 300

    local function remember(slots)
        local at = deps.clock()
        if not at then
            return
        end
        for key, entry in pairs(shown) do
            if at - entry.at > ROLL_SOURCE_SECONDS then
                shown[key] = nil
            end
        end
        -- A slot locked for its roll reads no source, so a window with nothing
        -- readable leaves what an earlier window proved.
        for key, from in pairs(windowSources(slots)) do
            local entry = shown[key]
            local agrees = from and (not entry or (entry.source and entry.source.guid == from.guid))
            shown[key] = { at = at, source = agrees and from or false }
        end
    end

    local function rollSource(key)
        local entry, at = shown[key], deps.clock()
        shown[key] = nil
        if entry and entry.source and at and at - entry.at >= 0 and at - entry.at <= ROLL_SOURCE_SECONDS then
            return entry.source
        end
        return nil
    end

    local function opened()
        local slots = Loot.open(api, castName(), creatureNames)
        if not slots then
            return
        end
        remember(slots)
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
        -- A purchase never casts, so an item handed over right after your
        -- cast is the spell's even beside an open merchant.
        if deps.merchantOpen() and parsed.kind ~= "created" and not deps.spellGave() then
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
        local slot = { key = key, quantity = quantity, source = rollSource(key) }
        if not commands.lootOpen({ slots = { slot }, won = true }) then
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
                local slots = Loot.open(api, castName(), creatureNames)
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
            PLAYER_TARGET_CHANGED = function()
                learnName("target")
            end,
            UPDATE_MOUSEOVER_UNIT = function()
                learnName("mouseover")
            end,
            NAME_PLATE_UNIT_ADDED = function(unit)
                if type(unit) == "string" and unit:match("^nameplate%d+$") then
                    learnName(unit)
                end
            end,
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
