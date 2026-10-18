local load = assert(loadfile("tests/support/addon.lua"))()
-- Native frame port replay of the Book's review queue, Source navigation, and
-- Collection rows whose item data or counts are still incomplete.
local addon = load.addon("Book")
date = os.date
local ui = assert(loadfile("tests/support/book_ui.lua"))()()
local api, controls, find, click = ui.api, ui.controls, ui.find, ui.click

local queued = {
    schema = 2,
    records = {},
    areas = {},
    evidence = { nextID = 2001, discarded = 5, firstDiscarded = 100, lastDiscarded = 200, unresolved = {} },
}
for index = 1, 2000 do
    queued.evidence.unresolved[index] = {
        id = index,
        kind = "identity",
        reason = "unreadable",
        at = 1000 + index,
        character = "EvidenceOnly",
        realm = "EvidenceRealm",
        detail = { itemID = 999, quantity = 1, area = "bank" },
    }
end
local queueWrites = 0
local queueStore = addon.Schema.open(queued, function()
    queueWrites = queueWrites + 1
end)
local profileTime = 0
api.debugprofilestop = function()
    profileTime = profileTime + 0.2
    return profileTime
end
local frame = assert(addon.Book.open(api, queueStore, "Ada", "A"))
frame.scripts.OnKeyDown(frame, "ENTER")
click("Review item changes")
frame.scripts.OnKeyDown(frame, "DOWN")
for _ = 1, 10000 do
    frame.scripts.OnUpdate(frame, 0.1)
end
find("2000 items to review")
find("1 / 286")
find(
    "5 older item changes without details • "
        .. date("%d %b %Y  %H:%M", 100)
        .. " – "
        .. date("%d %b %Y  %H:%M", 200)
)
local loading = find(
    "5 older item changes without details • "
        .. date("%d %b %Y  %H:%M", 100)
        .. " – "
        .. date("%d %b %Y  %H:%M", 200)
)
local warningControl = find(
    "Warning: 5 item changes need review; details discarded • "
        .. date("%d %b %Y", 100)
        .. " – "
        .. date("%d %b %Y", 200),
    "Button"
)
assert(loading.points[1].y > warningControl.points[1].y, "Discarded details and warning must occupy separate lines")
frame.scripts.OnKeyDown(frame, "PAGEDOWN")
for _ = 1, 10000 do
    frame.scripts.OnUpdate(frame, 0.1)
end
find("2 / 286")
click("All characters")
click("EvidenceOnly-EvidenceRealm")
for _ = 1, 10000 do
    frame.scripts.OnUpdate(frame, 0.1)
end
find("2000 items to review")
assert(queueWrites == 0)
print("book_ui_review_spec: large evidence queue, loading keyboard access and overflow layout passed")

api.debugprofilestop = nil
local sourceSaved
local sourceStore = addon.Schema.open(nil, function(value)
    sourceSaved = value
end)
assert(sourceStore:scan({
    character = "Ada",
    realm = "A",
    area = "bags",
    complete = true,
    seenAt = 1000,
    items = { { itemID = 2672, link = "|Hitem:2672::::::::|h[Meat]|h", quantity = 2 } },
}))
local sourceRecord = sourceSaved.records["2672:0"]
sourceRecord.totalGained, sourceRecord.firstGained, sourceRecord.lastGained = 5, 1001, 1001
sourceRecord.gains = {
    {
        id = "mob-gain",
        at = 1001,
        quantity = 5,
        character = "Ada",
        realm = "A",
        level = 1,
        place = "Forest",
        method = "Looted",
        source = { kind = "mob", guid = "Creature-0-1-2-3-4-001", name = "Boar" },
    },
}
local sourceWrites = 0
sourceStore = addon.Schema.open(sourceSaved, function()
    sourceWrites = sourceWrites + 1
end)
addon.Book.open(api, sourceStore, "Ada", "A")
frame.scripts.OnKeyDown(frame, "ENTER")
click("Collection")
click("Clear filters")
click("All sources")
click("Boar")
find("Boar", "Button")
find("ALL CURRENT")
find("Unknown")
find("Shows items gained from this source, not everything it can drop.")
local sourceSearch = find("", "EditBox")
sourceSearch:SetText("Boar")
sourceSearch.scripts.OnEnterPressed(sourceSearch)
find("Meat", "Button")
click("All realms")
click("A")
find("ALL CURRENT")
click("Clear filters")
find("All sources", "Button")
find("ALL CURRENT")
assert(sourceWrites == 0)
print("book_ui_review_spec: source navigation, source search and clearing passed")

-- Hovering a historical item can complete an uncached item-info request. Keep
-- the already-rendered Collection visible while that metadata refresh runs.
assert(sourceStore:scan({
    character = "Ada",
    realm = "A",
    area = "bags",
    complete = true,
    seenAt = 2000,
    items = {},
}))
assert(sourceStore:scan({
    character = "Ada",
    realm = "A",
    area = "equipped",
    complete = true,
    seenAt = 2000,
    items = {},
}))
assert(sourceStore:scan({
    character = "Ada",
    realm = "A",
    area = "bank",
    complete = true,
    seenAt = 2000,
    items = {},
}))
local historicalFrame = assert(addon.Book.open(api, sourceStore, "Ada", "A"))
for _ = 1, 20 do
    historicalFrame.scripts.OnUpdate(historicalFrame, 0.1)
end
local historicalRow
for _, control in ipairs(controls) do
    if control.kind == "Button" and control.key == "2672:0" and control:IsVisible() then
        historicalRow = control
        break
    end
end
assert(historicalRow, "A sold item should remain in Collection history")
local historicalProfileTime = 0
rawset(api, "debugprofilestop", function()
    historicalProfileTime = historicalProfileTime + 1
    return historicalProfileTime
end)
api.GameTooltip = {
    SetOwner = function() end,
    SetHyperlink = function()
        ui.ready = false
        historicalFrame.scripts.OnEvent(historicalFrame, "GET_ITEM_INFO_RECEIVED", 2672, true)
    end,
    Show = function() end,
    Hide = function() end,
}
historicalRow.scripts.OnEnter(historicalRow)
historicalFrame.scripts.OnUpdate(historicalFrame, 0.1)
for _, control in ipairs(controls) do
    assert(
        control.text ~= "Loading your Collection…" or not control:IsVisible(),
        "Hovering a sold item must not blank the Collection while item metadata refreshes"
    )
end
print("book_ui_review_spec: historical-item hover keeps the Collection visible")

-- A current count is unknown until bags and equipped gear have complete checks
-- at the same time.
local partialStore = addon.Schema.open(nil, function() end)
local bootsLink = "|Hitem:990010::::::::|h[Neophyte's Boots]|h"
assert(partialStore:scan({
    character = "Ada",
    realm = "A",
    area = "equipped",
    complete = true,
    seenAt = 3000,
    items = { { itemID = 990010, link = bootsLink, quantity = 1 } },
}))
assert(partialStore:scan({
    character = "Ada",
    realm = "A",
    area = "bags",
    complete = true,
    seenAt = 3001,
    items = {},
}))
local partialFrame = assert(addon.Book.open(api, partialStore, "Ada", "A", "Ada", "A"))
for _ = 1, 20 do
    partialFrame.scripts.OnUpdate(partialFrame, 0.1)
end
local partialRow
for _, control in ipairs(controls) do
    if control.kind == "Button" and control.text == "Neophyte's Boots" and control:IsVisible() then
        partialRow = control
        break
    end
end
assert(partialRow, "the previously seen item should remain in the scoped Collection")
local partialCount
for _, control in ipairs(controls) do
    if control.parent == partialRow and control.text == "Unknown" and control:IsVisible() then
        partialCount = control
        break
    end
end
assert(partialCount, "a partial storage check must not be presented as an exact count")
print("book_ui_review_spec: item rows show exact current counts or Unknown")
