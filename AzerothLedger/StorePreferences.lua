local _, addon = ...

-- Book layout, display options and pending discovery toasts.

local V = addon.SchemaValidate
local displayDefaults, copyValue, validDisplayField = V.displayDefaults, V.copyValue, V.validDisplayField
local bookPreferences, validDisplay = V.bookPreferences, V.validDisplay

local StorePreferences = {
    -- Settings and the book build their controls from the options this file saves.
    displayOptions = V.displayOptions,
    colorOptions = V.colorOptions,
    bookChoices = V.bookChoices,
}

-- Display options, which also decide whether discoveries queue toasts, and the
-- saved book layout. A damaged layout is replaced, not counted as damage.
---@type AzerothLedgerSlice[]
StorePreferences.slices = {
    {
        name = "display",
        validate = validDisplay,
        discoveries = function(display)
            return not validDisplay(display) or display.toasts
        end,
    },
    { name = "book" },
}

---@param slices table<string, table> Handles for this file's slices, by name
function StorePreferences.install(store, kernel, slices)
    local readable, saveFields = kernel.readable, kernel.save
    local savedBook, savedDisplay = slices.book.state, slices.display.state

    function store.book(_self)
        return bookPreferences(readable and savedBook() or nil)
    end
    function store.setBook(_self, preferences)
        if not readable or (type(savedBook()) == "table" and savedBook().version ~= 1) then
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
        if readable and type(savedDisplay()) == "table" then
            for key, value in pairs(savedDisplay()) do
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
