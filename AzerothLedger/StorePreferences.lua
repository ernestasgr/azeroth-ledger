local _, addon = ...

-- Book layout, display options and pending discovery toasts.

local V = addon.SchemaValidate
local displayDefaults, copyValue, validDisplayField = V.displayDefaults, V.copyValue, V.validDisplayField
local bookPreferences = V.bookPreferences

local StorePreferences = {}

function StorePreferences.install(store, kernel)
    local readable, saveFields = kernel.readable, kernel.save

    function store.book(_self)
        return bookPreferences(readable and kernel.raw().book or nil)
    end
    function store.setBook(_self, preferences)
        if not readable or (type(kernel.raw().book) == "table" and kernel.raw().book.version ~= 1) then
            return false
        end
        saveFields({ book = bookPreferences(preferences) })
        return true
    end
    local displayRevision = 0
    function store.displayRevision(_self)
        return displayRevision
    end
    function store.display(_self)
        local values = copyValue(displayDefaults)
        if readable and type(kernel.raw().display) == "table" then
            for key, value in pairs(kernel.raw().display) do
                if validDisplayField(key, value) then
                    values[key] = copyValue(value)
                end
            end
        end
        return values
    end

    function store.setDisplay(_self, control, enabled)
        if not readable or not validDisplayField(control, enabled) then
            return false
        end
        local values = store:display()
        values[control] = copyValue(enabled)
        saveFields({ display = values })
        displayRevision = displayRevision + 1
        return true
    end
    function store.takeDiscoveries(_self)
        return kernel.takeDiscoveries()
    end
end

addon.StorePreferences = StorePreferences
