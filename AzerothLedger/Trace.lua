local _, addon = ...

-- Opt-in diagnostic trace. Lines are kept in AzerothLedgerTraceDB so they survive
-- /reload, logout and character switches, and can be read from SavedVariables.
local Trace = { enabled = false }
local LIMIT = 4000
local saved
local sequence = 0

local function text(value)
    local kind = type(value)
    if kind == "string" then
        return value
    elseif kind == "table" then
        return "<table>"
    end
    return tostring(value)
end

---@param db any
---@param save fun(value: table)
function Trace.attach(db, save)
    if type(db) ~= "table" or type(db.lines) ~= "table" then
        db = { enabled = false, lines = {} }
        save(db)
    end
    saved = db
    Trace.enabled = db.enabled == true
    sequence = tonumber(db.sequence) or #db.lines
end

---@param kind string
function Trace.log(kind, ...)
    if not Trace.enabled or not saved then
        return
    end
    sequence = sequence + 1
    local clock = type(GetTime) == "function" and string.format("%.3f", GetTime()) or "?"
    local server = type(GetServerTime) == "function" and GetServerTime() or "?"
    local parts = { sequence, clock, server, kind }
    for index = 1, select("#", ...) do
        parts[#parts + 1] = text((select(index, ...)))
    end
    local lines = saved.lines
    lines[#lines + 1] = table.concat(parts, " ")
    saved.sequence = sequence
    if #lines > LIMIT + 500 then
        local kept = {}
        for index = #lines - LIMIT + 1, #lines do
            kept[#kept + 1] = lines[index]
        end
        saved.lines = kept
    end
end

---@param enabled boolean
function Trace.setEnabled(enabled)
    if saved then
        saved.enabled = enabled
        Trace.enabled = enabled
    end
end

function Trace.clear()
    if saved then
        saved.lines = {}
        saved.sequence = 0
        sequence = 0
    end
end

---@return integer
function Trace.count()
    return saved and #saved.lines or 0
end

addon.Trace = Trace
