-- Pure seams of the composition root: routes, commands, minimap geometry, revision.
local addon = {}
for _, source in ipairs({ "Item", "Work", "Trace", "Client", "Events", "Runtime", "Diagnostics", "Commands" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
assert(loadfile("AzerothLedger/MinimapButton.lua"))("AzerothLedger", addon)
local Events, Commands, MinimapButton, Runtime = addon.Events, addon.Commands, addon.MinimapButton, addon.Runtime

-- Routes from several sessions run in session order for a shared event.
local calls = {}
local routes = Events.merge(
    {
        A = function(value)
            calls[#calls + 1] = "first " .. value
        end,
    },
    nil,
    {
        A = function(value)
            calls[#calls + 1] = "second " .. value
        end,
        B = function() end,
    }
)
Events.run(routes, "A", 1)
Events.run(routes, "MISSING")
assert(calls[1] == "first 1" and calls[2] == "second 1" and #calls == 2)
local names = Events.names(routes)
assert(#names == 2 and names[1] == "A" and names[2] == "B")

-- A failed registration becomes a client issue, never a Lua error.
local issues = {}
local frame = {
    RegisterEvent = function(_, event)
        assert(event ~= "BROKEN", "unknown event")
    end,
    SetScript = function() end,
}
Events.attach(frame, { "OK", "BROKEN" }, function() end, issues)
assert(#issues == 1 and issues[1] == "BROKEN (unusable)")

-- Missing hook targets are reported with the feature that loses evidence.
issues = {}
assert(not Events.hook({}, issues, "vendor", {}, "BuyMerchantItem", function() end))
assert(issues[1] == "BuyMerchantItem (vendor hook unavailable)")

-- C_Timer.NewTicker is preferred; OnUpdate is the fallback.
local ticks, ticker = 0, nil
Events.every(
    {
        C_Timer = {
            NewTicker = function(interval, callback)
                assert(interval == 1)
                ticker = callback
            end,
        },
    },
    frame,
    1,
    function()
        ticks = ticks + 1
    end,
    issues
)
assert(ticker, "NewTicker must be used when available")({})
assert(ticks == 1)
local scripts = {}
Events.every(
    {},
    {
        SetScript = function(_, name, script)
            scripts[name] = script
        end,
    },
    1,
    function()
        ticks = ticks + 1
    end,
    issues
)
scripts.OnUpdate(nil, 0.6)
assert(ticks == 1, "OnUpdate must wait for the interval")
scripts.OnUpdate(nil, 0.6)
assert(ticks == 2)

-- Collection command filters.
local filter = Commands.collectionFilter("")
assert(filter and filter.character == nil and filter.realm == nil)
filter = Commands.collectionFilter("collection realm Classic Beta PvE")
assert(filter.realm == "Classic Beta PvE" and filter.character == nil)
filter = Commands.collectionFilter("collection Ada Classic Beta PvE")
assert(filter.character == "Ada" and filter.realm == "Classic Beta PvE")
assert(Commands.collectionFilter("status") == nil)

-- The first matching route wins; unmatched input reaches the fallback.
local ran = {}
local dispatch = Commands.dispatcher({
    {
        match = function(message)
            return message:match("^mark%s+(.+)$")
        end,
        run = function(marker)
            ran[#ran + 1] = "mark " .. marker
        end,
    },
}, function(message)
    ran[#ran + 1] = "help " .. message
end)
dispatch("  mark  release  ")
dispatch("unknown")
dispatch(nil)
assert(ran[1] == "mark release" and ran[2] == "help unknown" and ran[3] == "help ")

-- Minimap geometry and saved-angle defaults.
assert(MinimapButton.angle(nil) == 315 and MinimapButton.angle(0 / 0) == 315 and MinimapButton.angle(1 / 0) == 315)
assert(MinimapButton.angle(-45) == 315 and MinimapButton.angle(405) == 45)
local x, y = MinimapButton.offset(0, 140)
assert(math.abs(x - 80) < 1e-9 and math.abs(y) < 1e-9)
x = MinimapButton.offset(0, nil)
assert(math.abs(x - 80) < 1e-9, "unreadable minimap width must use the fallback radius")
assert(MinimapButton.cursorAngle(100, 150, 100, 100, 1) == 90)
assert(MinimapButton.cursorAngle(100, 150, 100, 100, 0) == nil)
assert(MinimapButton.cursorAngle(nil, 150, 100, 100, 1) == nil)

-- The saved environment uses the TOC version when the client exposes it.
assert(Runtime.revision({}, "AzerothLedger") == "dev")
assert(Runtime.revision({
    C_AddOns = {
        GetAddOnMetadata = function(name, field)
            assert(name == "AzerothLedger" and field == "Version")
            return "0.11.7"
        end,
    },
}, "AzerothLedger") == "0.11.7")
assert(Runtime.revision({
    GetAddOnMetadata = function()
        error("unavailable")
    end,
}, "AzerothLedger") == "dev")

print("event_routing_spec: passed")
