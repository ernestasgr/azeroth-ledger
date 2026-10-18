local _, addon = ...

-- Retention limits and the newest-first gain, transfer and vendor history.

local V = addon.SchemaValidate
local retentionMaximums, isInteger, gainRoot = V.retentionMaximums, V.isInteger, V.gainRoot
local chronological, copyValue = V.chronological, V.copyValue

local StoreJournal = {
    -- Settings offers the retention limits this file saves.
    retentionOptions = V.retentionOptions,
}

function StoreJournal.install(store, kernel)
    local valid, readable, saveFields, retention = kernel.valid, kernel.readable, kernel.save, kernel.retention

    function store.retention(_self)
        return retention()
    end

    function store.setRetention(_self, category, limit)
        local maximum = retentionMaximums[category]
        if not readable or not maximum or not isInteger(limit) or limit < 0 or limit > maximum then
            return false
        end
        if category == "gains" and kernel.journalDamaged() then
            return false
        end
        for _, list in ipairs(kernel.journalLists()) do
            if list.retention == category and list.damaged() then
                return false
            end
        end
        local limits = retention()
        limits[category] = limit
        saveFields({ retention = limits })
        return true
    end

    function store.journal(_self, pause)
        local result = {}
        if not readable then
            return result
        end
        for _, entry in ipairs(kernel.journalHealthy() and kernel.journal().gains or {}) do
            if pause then
                pause()
            end
            local contributions = {}
            for _, gain in ipairs(kernel.gains(entry.key, entry.id) or {}) do
                contributions[#contributions + 1] = copyValue(gain)
                if pause then
                    pause()
                end
            end
            if #contributions > 0 then
                local row = copyValue(entry)
                row.category, row.contributions = "gain", contributions
                result[#result + 1] = row
            end
        end
        for _, list in ipairs(kernel.journalLists()) do
            for _, entry in ipairs(list.entries) do
                if pause then
                    pause()
                end
                if valid[entry.key] and isInteger(entry.sequence) and entry.sequence > 0 then
                    local row = copyValue(entry)
                    row.category = list.retention == "transfers" and "transfer" or "vendor"
                    row.linkedAcquisitionID = row.linkedGainID and gainRoot(row.linkedGainID)
                    result[#result + 1] = row
                end
            end
        end
        local function newestFirst(a, b)
            return chronological(b, a)
        end
        if pause then
            addon.Work.sort(result, newestFirst, pause)
        else
            table.sort(result, newestFirst)
        end
        return result
    end
end

addon.StoreJournal = StoreJournal
