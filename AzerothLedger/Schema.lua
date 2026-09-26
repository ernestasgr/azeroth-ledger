local _, addon = ...

---@class AzerothLedgerRecord
---@field itemID integer
---@field firstSeen integer

---@class AzerothLedgerData
---@field schema integer
---@field marker? string
---@field environment? AzerothLedgerEnvironment
---@field records table<string, AzerothLedgerRecord>

---@class AzerothLedgerEnvironment
---@field build string
---@field interface string
---@field locale string
---@field revision string

---@class AzerothLedgerStore
---@field diagnostic fun(self: AzerothLedgerStore): AzerothLedgerDiagnostic
---@field marker fun(self: AzerothLedgerStore): string?
---@field environment fun(self: AzerothLedgerStore): AzerothLedgerEnvironment?
---@field list fun(self: AzerothLedgerStore): AzerothLedgerRecord[]
---@field find fun(self: AzerothLedgerStore, itemID: integer): AzerothLedgerRecord?
---@field setMarker fun(self: AzerothLedgerStore, marker: string): boolean
---@field setEnvironment fun(self: AzerothLedgerStore, environment: AzerothLedgerEnvironment): boolean
---@field recordSeen fun(self: AzerothLedgerStore, itemID: integer, firstSeen: integer): boolean

---@class AzerothLedgerDiagnostic
---@field kind 'healthy'|'damaged'|'unsupported'
---@field damagedCount integer
---@field schema? integer

local CURRENT_SCHEMA = 1

---@param value any
---@return boolean
-- Checks that a value is a finite whole number.
local function isInteger(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

---@param key any
---@param record any
---@return boolean
-- Checks that a saved item record has the expected shape.
local function validRecord(key, record)
    return type(key) == "string"
        and type(record) == "table"
        and isInteger(record.itemID)
        and record.itemID > 0
        and key == tostring(record.itemID)
        and isInteger(record.firstSeen)
        and record.firstSeen >= 0
end

---@param record AzerothLedgerRecord
---@return AzerothLedgerRecord
-- Copies an item record so callers cannot mutate saved state directly.
local function copyRecord(record)
    return { itemID = record.itemID, firstSeen = record.firstSeen }
end

---@param environment any
---@return boolean
-- Checks that saved build and addon metadata is valid.
local function validEnvironment(environment)
    return type(environment) == "table"
        and type(environment.build) == "string"
        and #environment.build > 0
        and #environment.build <= 64
        and type(environment.interface) == "string"
        and #environment.interface > 0
        and #environment.interface <= 32
        and type(environment.locale) == "string"
        and #environment.locale > 0
        and #environment.locale <= 16
        and type(environment.revision) == "string"
        and #environment.revision > 0
        and #environment.revision <= 64
end

---@param environment AzerothLedgerEnvironment
---@return AzerothLedgerEnvironment
-- Copies environment metadata before returning it to callers.
local function copyEnvironment(environment)
    return {
        build = environment.build,
        interface = environment.interface,
        locale = environment.locale,
        revision = environment.revision,
    }
end

local Schema = {}

---@param raw any
---@param save fun(value: AzerothLedgerData)
---@return AzerothLedgerStore
-- Opens saved data, retaining valid entries and isolating invalid values.
function Schema.open(raw, save)
    if raw == nil then
        raw = { schema = CURRENT_SCHEMA, records = {} }
        save(raw)
    end

    local supported = type(raw) == "table" and raw.schema == CURRENT_SCHEMA
    local recordsReadable = supported and type(raw.records) == "table"
    local valid = {}
    local damagedCount = 0

    if recordsReadable then
        for key, record in pairs(raw.records) do
            if validRecord(key, record) then
                valid[key] = copyRecord(record)
            else
                damagedCount = damagedCount + 1
            end
        end
    elseif supported then
        damagedCount = 1
    end

    if supported and raw.environment ~= nil and not validEnvironment(raw.environment) then
        damagedCount = damagedCount + 1
    end

    local store = {}

    ---@return AzerothLedgerDiagnostic
    -- Reports whether saved data is healthy, damaged, or unsupported.
    function store.diagnostic(_self)
        if not supported then
            return { kind = "unsupported", damagedCount = 0, schema = type(raw) == "table" and raw.schema or nil }
        end
        local markerDamaged = raw.marker ~= nil
            and (type(raw.marker) ~= "string" or #raw.marker < 1 or #raw.marker > 64)
        return {
            kind = (damagedCount > 0 or markerDamaged) and "damaged" or "healthy",
            damagedCount = damagedCount + (markerDamaged and 1 or 0),
            schema = CURRENT_SCHEMA,
        }
    end

    ---@return string?
    -- Returns the reload marker when it is valid.
    function store.marker(_self)
        if supported and type(raw.marker) == "string" and #raw.marker > 0 and #raw.marker <= 64 then
            return raw.marker
        end
        return nil
    end

    ---@return AzerothLedgerEnvironment?
    -- Returns the last recorded client environment when it is valid.
    function store.environment(_self)
        return supported and validEnvironment(raw.environment) and copyEnvironment(raw.environment) or nil
    end

    ---@return AzerothLedgerRecord[]
    -- Returns sorted copies of all readable item records.
    function store.list(_self)
        local result = {}
        for _, record in pairs(valid) do
            result[#result + 1] = copyRecord(record)
        end
        table.sort(result, function(left, right)
            return left.itemID < right.itemID
        end)
        return result
    end

    ---@param itemID integer
    ---@return AzerothLedgerRecord?
    -- Returns a copy of one readable item record.
    function store.find(_self, itemID)
        local record = valid[tostring(itemID)]
        return record and copyRecord(record) or nil
    end

    ---@param marker string
    ---@return boolean
    -- Saves a marker when the current schema and data are writable.
    function store.setMarker(_self, marker)
        if not recordsReadable or type(marker) ~= "string" or #marker < 1 or #marker > 64 then
            return false
        end
        local nextValue = {
            schema = CURRENT_SCHEMA,
            marker = marker,
            environment = raw.environment,
            records = raw.records,
        }
        save(nextValue)
        raw = nextValue
        return true
    end

    ---@param environment AzerothLedgerEnvironment
    ---@return boolean
    -- Saves the client build and addon revision metadata.
    function store.setEnvironment(_self, environment)
        if not recordsReadable or not validEnvironment(environment) then
            return false
        end
        local nextValue = {
            schema = CURRENT_SCHEMA,
            marker = raw.marker,
            environment = environment,
            records = raw.records,
        }
        save(nextValue)
        raw = nextValue
        return true
    end

    ---@param itemID integer
    ---@param firstSeen integer
    ---@return boolean
    -- Adds an item's first Seen observation without overwriting existing data.
    function store.recordSeen(_self, itemID, firstSeen)
        if not recordsReadable or not isInteger(itemID) or itemID <= 0 or not isInteger(firstSeen) or firstSeen < 0 then
            return false
        end

        local key = tostring(itemID)
        if raw.records[key] ~= nil then
            return valid[key] ~= nil
        end

        local record = { itemID = itemID, firstSeen = firstSeen }
        local nextRecords = {}
        for existingKey, existingRecord in pairs(raw.records) do
            nextRecords[existingKey] = existingRecord
        end
        nextRecords[key] = record

        local nextValue = {
            schema = CURRENT_SCHEMA,
            marker = raw.marker,
            environment = raw.environment,
            records = nextRecords,
        }
        save(nextValue)
        raw = nextValue
        valid[key] = copyRecord(record)
        return true
    end

    return store
end

addon.Schema = Schema
