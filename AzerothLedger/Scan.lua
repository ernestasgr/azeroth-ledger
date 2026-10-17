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
---@field GetInventoryItemID? fun(unit: string, slot: integer): integer?
---@field C_Item? {RequestLoadItemDataByID?: fun(itemID: integer)}
---@field C_Container? AzerothLedgerContainerApi

local requestedItems = {}

-- Trace only reads of the live client; the test companion scans mock APIs.
local tracedApi

local function trace(...)
    if tracedApi and addon.Trace and addon.Trace.enabled then
        addon.Trace.log(...)
    end
end

-- A slot can hold an item whose data is not cached yet, as with a new
-- character's starting gear. It has an ID but no link until the data loads.
local function equippedPending(api, slot)
    if type(api.GetInventoryItemID) ~= "function" then
        return false
    end
    local itemID = api.GetInventoryItemID("player", slot)
    if type(itemID) ~= "number" then
        return false
    end
    local request = api.C_Item and api.C_Item.RequestLoadItemDataByID
    local requested = false
    if type(request) == "function" and not requestedItems[itemID] then
        requestedItems[itemID] = true
        requested = pcall(request, itemID)
    end
    trace("slot-pending", "slot=" .. slot, "id=" .. itemID, "requested=" .. tostring(requested))
    return true
end

local function add(items, itemID, link, quantity, location)
    if type(itemID) ~= "number" or type(quantity) ~= "number" or quantity < 1 then
        return false
    end
    items[#items + 1] = { itemID = itemID, link = link, quantity = quantity, location = location }
    return addon.Item.key(link, itemID) ~= nil
end

local function appendCached(snapshot, cached)
    for _, item in ipairs(cached.items) do
        snapshot.items[#snapshot.items + 1] = item
    end
    snapshot.complete = snapshot.complete and cached.complete
end

local function retainCapture(cache, id, snapshot, first, complete)
    if not cache then
        return
    end
    local items = {}
    for index = first + 1, #snapshot.items do
        items[#items + 1] = snapshot.items[index]
    end
    cache[id] = { items = items, complete = complete }
end

---@param api AzerothLedgerScanApi
---@param area 'bags'|'bank'|'equipped'
---@param bankOpen boolean
---@return AzerothLedgerSnapshot?
-- Reads what the client exposes now; failed or closed scopes are explicitly incomplete.
function Scan.capture(api, area, bankOpen, cache, affected)
    if
        type(api.UnitName) ~= "function"
        or type(api.GetRealmName) ~= "function"
        or type(api.GetServerTime) ~= "function"
    then
        return nil
    end
    tracedApi = api == _G
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
        trace(
            "capture-skipped",
            "area=" .. tostring(area),
            "character=" .. tostring(character),
            "realm=" .. tostring(realm)
        )
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
            trace("capture", "area=equipped", "GetInventoryItemLink unavailable")
            snapshot.complete = false
            return snapshot
        end
        for slot = 1, 19 do
            local cached = cache and cache[slot]
            if cached and cached.complete and affected and not affected[slot] then
                appendCached(snapshot, cached)
                if #cached.items > 0 then
                    trace("slot-cached", "slot=" .. slot, cached.items[1].link)
                end
            else
                local first = #snapshot.items
                local ok, readable = pcall(function()
                    local link = api.GetInventoryItemLink("player", slot)
                    if not link then
                        return not equippedPending(api, slot)
                    end
                    local added = add(snapshot.items, tonumber(link:match("item:(%d+)")), link, 1, tostring(slot))
                    trace("slot", "slot=" .. slot, "added=" .. tostring(added), link)
                    return added
                end)
                if not ok then
                    trace("slot-error", "slot=" .. slot, readable)
                end
                if not ok then
                    snapshot.complete = false
                elseif not readable then
                    snapshot.complete = false
                end
                retainCapture(cache, slot, snapshot, first, ok and readable == true)
            end
        end
        trace("capture", "area=equipped", "complete=" .. tostring(snapshot.complete), "items=" .. #snapshot.items)
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
        local cached = cache and cache[bag]
        if cached and cached.complete and affected and not affected[bag] then
            appendCached(snapshot, cached)
        else
            local first, complete = #snapshot.items, true
            local slotsOK, slots = pcall(function()
                local count = containers.GetContainerNumSlots(bag)
                if type(count) ~= "number" or count < 0 then
                    error("unreadable container")
                end
                return count
            end)
            if not slotsOK then
                snapshot.complete = false
                complete = false
            else
                for slot = 1, slots do
                    local itemOK, readable = pcall(function()
                        local info = containers.GetContainerItemInfo(bag, slot)
                        if not info then
                            return true
                        end
                        return add(snapshot.items, info.itemID, info.hyperlink, info.stackCount, bag .. ":" .. slot)
                    end)
                    if not itemOK or not readable then
                        snapshot.complete = false
                        complete = false
                    end
                end
            end
            retainCapture(cache, bag, snapshot, first, complete)
            if not complete then
                trace("container-incomplete", "area=" .. area, "bag=" .. bag)
            end
        end
    end
    trace("capture", "area=" .. area, "complete=" .. tostring(snapshot.complete), "items=" .. #snapshot.items)
    return snapshot
end

-- Cache container snapshots, never item facts. Every returned area is assembled
-- from all its containers; unreadable containers and slots are read again.
function Scan.reader(api)
    local caches = { bags = {}, bank = {}, equipped = {} }
    local reader = {}
    function reader.capture(_self, area, bankOpen, affected)
        return Scan.capture(api, area, bankOpen, caches[area], affected)
    end
    function reader.unreadable(_self, area)
        local result = {}
        for id, cached in pairs(caches[area]) do
            if not cached.complete then
                result[id] = true
            end
        end
        return next(result) and result or nil
    end
    return reader
end

addon.Scan = Scan
