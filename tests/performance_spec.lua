local addon = {}
for _, name in ipairs({ "Item", "Work", "Schema", "Client", "Scan", "LastSeen", "Collection" }) do
    assert(loadfile("AzerothLedger/" .. name .. ".lua"))("AzerothLedger", addon)
end
date = os.date
local fixture = assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))()
local saved = fixture(10000)
local store = addon.Schema.open(saved, function(value)
    saved = value
end)
assert(store:diagnostic().kind == "healthy")
local instructions = 0
debug.sethook(function()
    instructions = instructions + 1000
end, "", 1000)
assert(store:scan({
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 1002,
    complete = true,
    items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 1 } },
}))
debug.sethook()
assert(instructions < 250000, "Normal bag scan traversed the large ledger: " .. instructions .. " instructions")
local removed = store:find("10002:0")
assert(removed.observations[#removed.observations].quantity == 0)
assert(store:find("20000:0").totalGained == 2)
assert(#store:find("20000:0").links == 2)
print("performance_spec: selective scan passed")

local clock, reads = 0, 0
local api = {
    debugprofilestop = function()
        clock = clock + 0.05
        return clock
    end,
}
local query = addon.Collection.startQuery(api, store, "Fixture", "Test", {}, function()
    reads = reads + 1
    return { category = "Materials", icon = 1 }
end)
local result = query:step()
assert(result == nil and reads < 50, "Opening a large Collection must yield before loading every item")
local frames = 1
repeat
    result = query:step()
    frames = frames + 1
until result
assert(frames > 2 and result.discoveryCount == 10000 and #result.rows == 10000)
assert(result.rows[1].name == "Item 00001" and result.rows[10000].name == "Item 10000")
assert(store:setRetention("gains", 0) and store:setRetention("vendor", 0) and store:setRetention("transfers", 0))
assert(#store:journal() == 0)
local restored = addon.Schema.open(saved, function(value)
    saved = value
end)
assert(restored:count() == 10000)
assert(restored:breakdown("20000:0").recorded == 3)
assert(restored:breakdown("20000:0").sources["Mob #10000"] == 2)
assert(#restored:find("20000:0").links == 2)
print("performance_spec: budgeted browsing and permanent facts passed")

for _, name in ipairs({ "Journal", "BookWidgets", "BookQuery", "Book" }) do
    assert(loadfile("AzerothLedger/" .. name .. ".lua"))("AzerothLedger", addon)
end
local native = assert(loadfile("tests/support/native_ui.lua"))().create()
local metadataReads = 0
native.api.debugprofilestop = api.debugprofilestop
native.api.C_Item = {
    GetItemInfo = function(link)
        metadataReads = metadataReads + 1
        return "Fixture", link, 1, nil, nil, nil, nil, nil, nil, 1, nil, 7
    end,
}
local frame = addon.Collection.open(native.api, restored, "Fixture", "Test")
local function visible(text)
    for _, control in ipairs(native.controls) do
        if control.text == text and control:IsVisible() then
            return control
        end
    end
end
assert(visible("Loading your Collection…"), "Large native book should show loading immediately")
for _ = 1, 12000 do
    if visible("10000 items") then
        break
    end
    frame.scripts.OnUpdate(frame)
end
assert(visible("10000 items"), "Native book must finish its query across frames")
frame.scripts.OnKeyDown(frame, "ENTER")
local beforePage = metadataReads
frame.scripts.OnKeyDown(frame, "PAGEDOWN")
assert(visible("2 / 1429"))
assert(metadataReads - beforePage < 20, "Paging must reuse its completed query")
frame.scripts.OnEvent(frame, "ITEM_DATA_LOAD_RESULT", 10001, true)
frame.scripts.OnUpdate(frame)
assert(visible("Loading your Collection…"))
for _ = 1, 12000 do
    if visible("10000 items") then
        break
    end
    frame.scripts.OnUpdate(frame)
end
assert(visible("10000 items") and visible("2 / 1429"), "A background refresh must preserve the current page")
print("performance_spec: native loading and cached paging passed")

local raw = fixture(3)
local failSave = false
local atomic = addon.Schema.open(raw, function()
    if failSave then
        error("test save failure")
    end
end)
local priorRevision = atomic:revision()
failSave = true
local accepted = pcall(
    atomic.scan,
    atomic,
    { character = "Fixture", realm = "Test", area = "bags", seenAt = 1002, complete = true, items = {} }
)
assert(not accepted and atomic:revision() == priorRevision)
assert(atomic:find("10001:0").observations[1].quantity == 1)
assert(addon.Schema.open(raw, function() end):find("10001:0").observations[1].quantity == 1)
failSave = false
assert(
    atomic:scan({ character = "Fixture", realm = "Test", area = "bags", seenAt = 1002, complete = true, items = {} })
)
local cleared = atomic:find("10001:0").observations
assert(cleared[#cleared].quantity == 0, "Failed save must leave the held-item index usable")
print("performance_spec: failed save preserves public and saved facts")
