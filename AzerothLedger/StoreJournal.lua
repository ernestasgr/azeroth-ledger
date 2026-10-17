local _, addon = ...

-- Retention limits and the newest-first gain, transfer and vendor history.

local V = addon.SchemaValidate
local retentionMaximums, isInteger, gainRoot = V.retentionMaximums, V.isInteger, V.gainRoot
local chronological, copyValue, validVendorState = V.chronological, V.copyValue, V.validVendorState
local validExchangeState, validJournal = V.validExchangeState, V.validJournal

local StoreJournal = {}

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
        if
            category == "vendor" and kernel.raw().vendor ~= nil and not validVendorState(kernel.raw().vendor)
            or category == "transfers" and kernel.raw().exchange ~= nil and not validExchangeState(
                kernel.raw().exchange
            )
            or category == "gains" and kernel.raw().journal ~= nil and not validJournal(kernel.raw().journal)
        then
            return false
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
        for _, entry in ipairs(kernel.journalHealthy() and kernel.raw().journal.gains or {}) do
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
        for _, category in ipairs({ "exchange", "vendor" }) do
            local state = kernel.raw()[category]
            local healthy = category == "exchange" and kernel.exchangeHealthy or kernel.vendorHealthy
            for _, entry in ipairs(state and healthy and state.journal or {}) do
                if pause then
                    pause()
                end
                if valid[entry.key] and isInteger(entry.sequence) and entry.sequence > 0 then
                    local row = copyValue(entry)
                    row.category = category == "exchange" and "transfer" or "vendor"
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
