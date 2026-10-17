local _, addon = ...

-- Client signal plumbing: route tables for frame events, a single dispatcher,
-- a repeating timer, and secure hooks. Unusable client APIs become client issues
-- for /al status instead of Lua errors.
local Events = {}

---@alias ALRoutes table<string, fun(...)>

-- Merges route tables in argument order, so a later route for the same event
-- runs after an earlier one.
---@param ... ALRoutes
---@return table<string, fun(...)[]>
function Events.merge(...)
    local merged = {}
    for index = 1, select("#", ...) do
        for event, handler in pairs(select(index, ...) or {}) do
            local handlers = merged[event] or {}
            handlers[#handlers + 1] = handler
            merged[event] = handlers
        end
    end
    return merged
end

---@param routes table<string, fun(...)[]>
---@return string[]
function Events.names(routes)
    local names = {}
    for event in pairs(routes) do
        names[#names + 1] = event
    end
    table.sort(names)
    return names
end

---@param routes table<string, fun(...)[]>
---@param event string
function Events.run(routes, event, ...)
    for _, handler in ipairs(routes[event] or {}) do
        handler(...)
    end
end

-- Registers each event and installs one OnEvent script.
---@param frame table
---@param names string[]
---@param dispatch fun(frame: table, event: string, ...)
---@param issues string[]
function Events.attach(frame, names, dispatch, issues)
    for _, event in ipairs(names) do
        if not pcall(frame.RegisterEvent, frame, event) then
            issues[#issues + 1] = event .. " (unusable)"
        end
    end
    if not pcall(frame.SetScript, frame, "OnEvent", dispatch) then
        issues[#issues + 1] = "CreateFrame events (unusable)"
    end
end

-- Calls callback every interval seconds. C_Timer.NewTicker is preferred; the
-- frame's OnUpdate is the fallback for clients and fixtures without it.
---@param api table
---@param frame table
---@param interval number
---@param callback fun()
---@param issues string[]
function Events.every(api, frame, interval, callback, issues)
    local timer = api.C_Timer
    if type(timer) == "table" and type(timer.NewTicker) == "function" then
        if pcall(timer.NewTicker, interval, function()
            callback()
        end) then
            return
        end
    end
    local elapsed = 0
    local ok = pcall(frame.SetScript, frame, "OnUpdate", function(_, delta)
        elapsed = elapsed + (tonumber(delta) or 0)
        if elapsed >= interval then
            elapsed = 0
            callback()
        end
    end)
    if not ok then
        issues[#issues + 1] = "CreateFrame timer (unusable)"
    end
end

-- Runs callback after the client calls target[method]. The label names the
-- feature that loses its evidence when the hook cannot be installed.
---@param api table
---@param issues string[]
---@param label string
---@param target any
---@param method string
---@param callback fun(...)
---@return boolean installed
function Events.hook(api, issues, label, target, method, callback)
    local hook = api.hooksecurefunc
    if type(hook) ~= "function" or type(target) ~= "table" or type(target[method]) ~= "function" then
        issues[#issues + 1] = method .. " (" .. label .. " hook unavailable)"
        return false
    end
    if not pcall(hook, target, method, callback) then
        issues[#issues + 1] = method .. " (" .. label .. " hook unusable)"
        return false
    end
    return true
end

addon.Events = Events
