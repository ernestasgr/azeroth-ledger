local _, addon = ...

-- /al slash commands as an ordered route list. Each route's match returns its
-- arguments (or nil), and the first matching route runs.
local Commands = {}

---@class ALCommandRoute
---@field match fun(message: string): any
---@field run fun(argument: any)

local function trim(message)
    return (message or ""):match("^%s*(.-)%s*$")
end

local function exactly(word)
    return function(message)
        return message == word or nil
    end
end

-- "", "collection", "collection <character> <realm>", or "collection realm <realm>".
---@param message string
---@return {character?: string, realm?: string}?
function Commands.collectionFilter(message)
    if message ~= "" and message ~= "collection" and not message:match("^collection%s+") then
        return nil
    end
    local realm = message:match("^collection%s+realm%s+(.+)$")
    if realm then
        return { realm = realm }
    end
    local character
    character, realm = message:match("^collection%s+(%S+)%s+(.+)$")
    return { character = character, realm = realm }
end

---@param routes ALCommandRoute[]
---@param fallback fun(message: string)
---@return fun(message?: string)
function Commands.dispatcher(routes, fallback)
    return function(message)
        message = trim(message)
        for _, route in ipairs(routes) do
            local argument = route.match(message)
            if argument ~= nil then
                route.run(argument)
                return
            end
        end
        fallback(message)
    end
end

---@class ALCommandContext
---@field api table
---@field store fun(): ALStore
---@field client AzerothLedgerClientInspection
---@field revision string
---@field inventory table
---@field print fun(...)

---@param context ALCommandContext
---@return table<string, fun()>
local function traceActions(context)
    local Trace, say = addon.Trace, context.print
    return {
        on = function()
            Trace.setEnabled(true)
            Trace.log(
                "trace-on",
                "revision=" .. context.revision,
                "client=" .. context.client.build,
                "locale=" .. context.client.locale
            )
            say("Azeroth Ledger: trace on; it stays on for every character until /al trace off")
        end,
        off = function()
            Trace.log("trace-off")
            Trace.setEnabled(false)
            say("Azeroth Ledger: trace off")
        end,
        clear = function()
            Trace.clear()
            say("Azeroth Ledger: trace cleared")
        end,
        dump = function()
            if not Trace.enabled then
                say("Azeroth Ledger: trace is off; /al trace on first")
                return
            end
            addon.Diagnostics.traceState(context.api, context.store(), context.client, context.revision)
            say("Azeroth Ledger: state written to the trace;", Trace.count(), "lines. /reload to save it to disk")
        end,
        status = function()
            say("Azeroth Ledger: trace", Trace.enabled and "on" or "off", "with", Trace.count(), "lines")
            say("Azeroth Ledger: /al trace on, /al trace off, /al trace dump, /al trace clear")
        end,
    }
end

---@param context ALCommandContext
---@return ALCommandRoute[]
function Commands.routes(context)
    local say = context.print
    local trace = traceActions(context)
    return {
        {
            match = Commands.collectionFilter,
            run = function(filter)
                local character, realm = addon.Runtime.identity(context.api)
                if character and realm then
                    addon.Collection.open(
                        context.api,
                        context.store(),
                        character,
                        realm,
                        filter.character,
                        filter.realm
                    )
                end
            end,
        },
        {
            match = exactly("status"),
            run = function()
                Commands.printStatus(context)
            end,
        },
        {
            match = exactly("profile"),
            run = function()
                say("Azeroth Ledger: session timings in milliseconds; frame budget 2 ms; open target 250 ms")
                for label, timing in pairs(addon.Work.timings) do
                    say(label, "samples", timing.frames, "total", timing.total, "maximum", timing.maximum)
                end
            end,
        },
        {
            match = function(message)
                if message == "trace" or message:match("^trace%s") then
                    return message:match("^trace%s+(%S+)") or "status"
                end
            end,
            run = function(action)
                (trace[action] or trace.status)()
            end,
        },
        {
            match = exactly("scan"),
            run = function()
                context.inventory:check("all")
                say("Azeroth Ledger: readable storage checked")
            end,
        },
        {
            match = function(message)
                return message:match("^mark%s+(.+)$")
            end,
            run = function(marker)
                say(
                    context.store():setMarker(marker) and "Azeroth Ledger: marker saved"
                        or "Azeroth Ledger: marker rejected; use 1-64 characters and current schema"
                )
            end,
        },
    }
end

---@param context ALCommandContext
function Commands.printStatus(context)
    local lines = addon.Diagnostics.status(context.store(), context.client, context.revision, context.api.date)
    for _, line in ipairs(lines) do
        context.print(unpack(line, 1, line.n))
    end
end

---@param context ALCommandContext
function Commands.help(context)
    context.print("Azeroth Ledger: /al collection [character realm], /al collection realm <realm>")
    context.print("Azeroth Ledger: /al status, /al scan, /al mark <token>, /al trace")
end

---@param context ALCommandContext
---@return fun(message?: string)
function Commands.new(context)
    return Commands.dispatcher(Commands.routes(context), function()
        Commands.help(context)
    end)
end

addon.Commands = Commands
