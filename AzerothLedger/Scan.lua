local _, addon = ...

local Scan = {}
local containerIDs = {
    bags = { 0, 1, 2, 3, 4 },
    bank = { -1, 5, 6, 7, 8, 9, 10, 11 },
}

---@class AzerothLedgerContainerItemInfo
---@field itemID integer
---@field hyperlink string
---@field stackCount integer

---@class AzerothLedgerContainerApi
---@field GetContainerNumSlots fun(bag: integer): integer?
---@field GetContainerItemInfo fun(bag: integer, slot: integer): AzerothLedgerContainerItemInfo?

---@class AzerothLedgerScanApi
---@field UnitName? fun(unit: string): string?
---@field GetRealmName? fun(): string?
---@field GetServerTime? fun(): integer
---@field GetInventoryItemLink? fun(unit: string, slot: integer): string?
---@field C_Container? AzerothLedgerContainerApi

local function add(items, itemID, link, quantity)
    if
        type(itemID) ~= "number"
        or type(link) ~= "string"
        or type(quantity) ~= "number"
        or quantity < 1
        or not addon.Item.key(link, itemID)
    then
        return false
    end
    items[#items + 1] = { itemID = itemID, link = link, quantity = quantity }
    return true
end

---@param api AzerothLedgerScanApi
---@param area 'bags'|'bank'|'equipped'
---@param bankOpen boolean
---@return AzerothLedgerSnapshot?
-- Reads what the client exposes now; failed or closed scopes are explicitly incomplete.
function Scan.capture(api, area, bankOpen)
    if
        type(api.UnitName) ~= "function"
        or type(api.GetRealmName) ~= "function"
        or type(api.GetServerTime) ~= "function"
    then
        return nil
    end
    local identityOK, character = pcall(api.UnitName, "player")
    local realmOK, realm = pcall(api.GetRealmName)
    local timeOK, seenAt = pcall(api.GetServerTime)
    if
        not identityOK
        or not realmOK
        or not timeOK
        or type(character) ~= "string"
        or type(realm) ~= "string"
        or type(seenAt) ~= "number"
    then
        return nil
    end
    local snapshot = {
        character = character,
        realm = realm,
        area = area,
        seenAt = seenAt,
        complete = true,
        items = {},
    }
    if area == "bank" and not bankOpen then
        snapshot.complete = false
        return snapshot
    end
    if area == "equipped" then
        if type(api.GetInventoryItemLink) ~= "function" then
            snapshot.complete = false
            return snapshot
        end
        for slot = 1, 19 do
            local ok, readable = pcall(function()
                local link = api.GetInventoryItemLink("player", slot)
                if not link then
                    return true
                end
                return add(snapshot.items, tonumber(link:match("item:(%d+)")), link, 1)
            end)
            if not ok then
                snapshot.complete = false
            elseif not readable then
                snapshot.complete = false
            end
        end
        return snapshot
    end
    local containers = api.C_Container
    if
        type(containers) ~= "table"
        or type(containers.GetContainerNumSlots) ~= "function"
        or type(containers.GetContainerItemInfo) ~= "function"
    then
        snapshot.complete = false
        return snapshot
    end
    for _, bag in ipairs(containerIDs[area] or {}) do
        local slotsOK, slots = pcall(function()
            local count = containers.GetContainerNumSlots(bag)
            if type(count) ~= "number" or count < 0 then
                error("unreadable container")
            end
            return count
        end)
        if not slotsOK then
            snapshot.complete = false
        else
            for slot = 1, slots do
                local itemOK, readable = pcall(function()
                    local info = containers.GetContainerItemInfo(bag, slot)
                    if not info then
                        return true
                    end
                    return add(snapshot.items, info.itemID, info.hyperlink, info.stackCount)
                end)
                if not itemOK or not readable then
                    snapshot.complete = false
                end
            end
        end
    end
    return snapshot
end

addon.Scan = Scan
