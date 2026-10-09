local _, addon = ...
local Inventory = {}

-- This client adapter owns scan order, comparable dates, coalescing, and retries.
-- The consumer receives normalized snapshots; only the store persists them.
---@param api table
---@param publish fun(snapshot: AzerothLedgerSnapshot)
---@param afterFlush? fun()
function Inventory.new(api, publish, afterFlush)
    local reader = addon.Scan.reader(api)
    local bankOpen, queued = false, false
    local pendingBags, pendingEquipment = {}, {}
    local inventory = {}

    local function now()
        return type(api.GetServerTime) == "function" and api.GetServerTime() or nil
    end

    local function capture(area, at, affected)
        local snapshot = reader:capture(area, bankOpen, affected)
        if snapshot then
            snapshot.seenAt = at or snapshot.seenAt
            publish(snapshot)
        end
    end

    ---@param scope 'bags'|'bank'|'equipped'|'possessions'|'all'
    ---@return integer? checkedAt
    function inventory.check(_self, scope)
        local at = now()
        if scope == "possessions" or scope == "all" then
            capture("bags", at)
            capture("equipped", at)
            if scope == "all" then
                capture("bank", at)
            end
        else
            capture(scope, at)
        end
        return at
    end

    local function flush()
        addon.Work.measure(api, "Inventory update", function()
            queued = false
            local bags, equipment = pendingBags, pendingEquipment
            pendingBags, pendingEquipment = {}, {}
            local at = now()
            local affected = next(bags) and bags or nil
            capture("bags", at, affected)
            capture("equipped", at, equipment)
            local bankChanged = not affected or affected[-1]
            for bag = 5, 11 do
                bankChanged = bankChanged or (affected and affected[bag])
            end
            if bankOpen and bankChanged then
                capture("bank", at, affected)
            end
            if afterFlush then
                afterFlush()
            end
        end)
    end

    local function queue()
        if not queued then
            queued = true
            if type(api.C_Timer) == "table" and type(api.C_Timer.After) == "function" then
                api.C_Timer.After(0, flush)
            else
                flush()
            end
        end
    end

    ---@param event string
    ---@param value? number|boolean
    function inventory.event(_self, event, value)
        if event == "BAG_UPDATE" then
            if type(value) == "number" then
                pendingBags[value] = true
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            queue()
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            if type(value) == "number" then
                pendingEquipment[value] = true
            end
            queue()
        elseif event == "BANKFRAME_OPENED" then
            bankOpen = true
            inventory:check("all")
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
            inventory:check("bank")
        elseif event == "GET_ITEM_INFO_RECEIVED" and value then
            local at = now()
            for _, area in ipairs({ "bags", "equipped", "bank" }) do
                local unreadable = reader:unreadable(area)
                if unreadable and (area ~= "bank" or bankOpen) then
                    capture(area, at, unreadable)
                end
            end
        end
    end

    return inventory
end

addon.Inventory = Inventory
