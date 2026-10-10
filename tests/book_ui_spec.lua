-- Native frame port replay: checks visible text and input behavior, not private book state.
local addon = {}
for _, source in ipairs({
    "Item",
    "Work",
    "Schema",
    "Client",
    "LastSeen",
    "Collection",
    "Journal",
    "BookWidgets",
    "BookQuery",
    "Book",
}) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
date = os.date
local native = assert(loadfile("tests/support/native_ui.lua"))().create({
    rejectedTextures = { ["Interface\\Icons\\INV_Misc_Food_14"] = true },
})
local controls = native.controls
local function assertIconsAboveBackings()
    local layers = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
    for _, icon in ipairs(controls) do
        if icon.kind == "Texture" and icon.texture and icon:IsVisible() and icon.width == icon.height then
            for _, backing in ipairs(controls) do
                if
                    backing.parent == icon.parent
                    and backing.kind == "Texture"
                    and backing.color
                    and backing.color[4] == 1
                    and backing.width == icon.width + 2
                    and backing.height == icon.height + 2
                then
                    local iconOrder = layers[icon.layer] * 16 + (icon.subLevel or 0)
                    local backingOrder = layers[backing.layer] * 16 + (backing.subLevel or 0)
                    assert(iconOrder > backingOrder, "Opaque icon backing can cover the icon in WoW")
                end
            end
        end
    end
end
local ready = true
local api = native.api
local browsingTime = 100000
api.GetServerTime = function()
    return browsingTime
end
api.IsControlKeyDown = function()
    return true
end
api.C_Item = {
    GetItemInfo = function(link)
        if not ready then
            return nil
        end
        local id = tonumber(link:match("item:(%d+)"))
        return "Name",
            link,
            1,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            "Interface\\Icons\\INV_Misc_Food_14",
            nil,
            id == 2672 and 7 or 2
    end,
}
local writes = 0
local store = addon.Schema.open(nil, function()
    writes = writes + 1
end)
local items = { { itemID = 2672, link = "|Hitem:2672::::::::|h[Meat]|h", quantity = 400 } }
for index = 1, 14 do
    items[#items + 1] = {
        itemID = 100 + index,
        link = "|Hitem:" .. (100 + index) .. "::::::::|h[Sword " .. string.format("%02d", index) .. "]|h",
        quantity = 1,
    }
end
assert(store:scan({ character = "Ada", realm = "A", area = "bags", complete = true, seenAt = 1000, items = items }))
assert(store:scan({
    character = "Ben",
    realm = "B",
    area = "bags",
    complete = true,
    seenAt = 1001,
    items = { { itemID = 2672, link = "|cffffffff|Hitem:2672:0:0:0:0:0:0:0:15:7|h[Meat]|h|r", quantity = 10 } },
}))
local frame = assert(addon.Collection.open(api, store, "Ada", "A"))
frame.scripts.OnKeyDown(frame, "ENTER")
local openingFade = assert(frame.animationGroups[1])
assert(openingFade.playing and openingFade.animations[1].duration <= 0.5)
openingFade:Finish()
assert(frame.alpha == 1, "opening must finish fully opaque")
local function find(text, kind)
    for index = #controls, 1, -1 do
        local control = controls[index]
        if control.text == text and control:IsVisible() and (not kind or control.kind == kind) then
            return control
        end
    end
    error("Missing visible control: " .. text)
end
local function click(text)
    find(text, "Button"):Click()
end
local search
local scroll
for _, control in ipairs(controls) do
    if control.kind == "EditBox" then
        search = control
    end
    if control.kind == "ScrollFrame" then
        scroll = control
    end
end
find("15 items")
find("15 discoveries")
assertIconsAboveBackings()
for _, control in ipairs(controls) do
    if control.kind == "Texture" and control:IsVisible() and control.width == 32 and control.height == 32 then
        assert(control.texture ~= nil, "A rejected item texture left a blank Collection icon")
    end
end
click("Gallery")
assertIconsAboveBackings()
find("14 items")
find("1 / 3")
frame.scripts.OnKeyDown(frame, "PAGEDOWN")
find("2 / 3")
click("Next")
find("3 / 3")
frame.scripts.OnKeyDown(frame, "PAGEUP")
find("2 / 3")
click("Collection")
click("Meat")
find("400")
find("Item history")
find("How you got it")
assert(not pcall(find, "Developer details"), "Internal details should be hidden by default")
assert(addon.Book.setDeveloperMode(store, true))
frame.scripts.OnUpdate(frame)
find("Developer details")
find("Internal item key: 2672:0")
assert(addon.Book.setDeveloperMode(store, false))
frame.scripts.OnUpdate(frame)
local before = writes
click("Show all 2 saved links")
find("|Hitem:2672::::::::|h[Meat]|h", "Button")
find("|cffffffff|Hitem:2672:0:0:0:0:0:0:0:15:7|h[Meat]|h|r", "Button")
click("Show item versions only")
find("Show all 2 saved links", "Button")
scroll.scripts.OnMouseWheel(scroll, -1)
assert(scroll:GetVerticalScroll() == 48)
addon.Collection.refresh(store, "Ada", "A")
frame.scripts.OnUpdate()
assert(scroll:GetVerticalScroll() == 48, "an inventory refresh must preserve the reader's scroll position")
click("Next")
find("2 / 3")
find("400") -- selected details persist while browsing another page
click("Weapons")
find("14 items")
find("Sword 01", "FontString")
click("Materials")
find("1 item")
find("Meat", "FontString")
search:SetText("missing")
frame.scripts.OnUpdate()
find("0 items")
find("No matching items. Try another search or clear your filters.")
find("Select an item to explore\nits history.")
click("Clear filters")
click("Any status")
click("Historical only")
find("0 items")
click("Clear filters")
find("15 items")
click("Found once")
find("0 items")
click("Clear filters")
find("15 items")
click("Name A-Z")
click("Quantity: largest")
click("Any quality")
click("Rare")
find("0 items")
find("Select an item to explore\nits history.")
click("Clear filters")
click("Any method")
click("Looted")
find("0 items")
click("Gallery")
find("0 items")
click("Clear filters")
find("14 items")
click("Discoveries")
find("Discovery: newest", "Button")
click("Collection")
find("Name A-Z", "Button")
find("15 items")
click("All characters")
find("Ada-A")
frame.scripts.OnKeyDown(frame, "DOWN")
frame.scripts.OnKeyDown(frame, "ENTER")
find("Ada", "Button")
click("A")
click("All realms")
find("All realms", "Button")
click("Clear filters")
click("All places")
frame.scripts.OnKeyDown(frame, "ESCAPE")
assert(frame:IsShown(), "Escape should dismiss an open menu before closing the book")
frame.scripts.OnKeyDown(frame, "F")
assert(search:HasFocus())
search.scripts.OnEnterPressed(search)
assert(not search:HasFocus())
frame.scripts.OnKeyDown(frame, "DOWN")
find("Sword 01", "FontString")
assert(scroll:GetVerticalScroll() == 0, "selecting another item starts its history at the top")
frame.scripts.OnKeyDown(frame, "TAB")
frame.scripts.OnKeyDown(frame, "ENTER")
assert(frame:IsShown(), "keyboard navigation must start with browsing, not the close action")
frame.scripts.OnKeyDown(frame, "F")
search.scripts.OnTabPressed(search)
frame.scripts.OnKeyDown(frame, "ENTER")
find("Ada-A", "Button")
frame.scripts.OnKeyDown(frame, "ESCAPE")
click("Discoveries")
find("Discoveries", "Button")
click("−")
assert(frame.scale < 1)
api.UIParent:SetSize(900, 600)
frame.scripts.OnEvent()
local smaller = frame:GetScale()
click("−")
assert(frame:GetScale() < smaller, "window size must change immediately even when fitted to a smaller screen")
ready = false
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
find("15 items awaiting item data")
click("Any quality")
click("Next")
click("Unknown quality")
find("15 items")
ready = true
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
find("0 items")
find("Select an item to explore\nits history.")
click("Clear filters")
assert(writes == before, "browsing must not write SavedVariables")
click("All characters")
click("Ben-B")
click("Meat")
find("Character", "Button")
find("10")
click("Account")
find("400")
click("Character")
local stats = find("LATEST CHECK", "FontString").parent
local detailFade = assert(stats.animationGroups[1])
local detailPlays = detailFade.plays
addon.Collection.refresh(store, "Ada", "A")
frame.scripts.OnUpdate(frame, 0.1)
assert(detailFade.plays == detailPlays, "background refresh must not replay the detail transition")
click("Meat")
assert(detailFade.plays == detailPlays, "reselecting the same item must not restart its transition")
local scopedRecorded = false
for _, control in ipairs(controls) do
    if control.parent == stats and control.text == "10+" then
        scopedRecorded = true
    end
    assert(not (control.parent == stats and control.text == "400"), "character totals must not show account stock")
end
assert(scopedRecorded, "the detail statistic must show the selected character's initial stock")
click("Clear filters")
click("All places")
local menu = find("Next", "Button").parent
assert(menu.background:GetHeight() == menu:GetHeight(), "a short menu must not paint beyond its visible bounds")
frame.scripts.OnKeyDown(frame, "ESCAPE")
for index = 1, 10 do
    assert(store:scan({
        character = "Alt" .. string.format("%02d", index),
        realm = "A",
        area = "bags",
        complete = true,
        seenAt = 1000,
        items = {},
    }))
end
click("All characters")
click("Next")
local function firstMenuChoice()
    for _, control in ipairs(controls) do
        if
            control.parent == menu
            and control.kind == "Button"
            and control:IsVisible()
            and control.text ~= "Previous"
            and control.text ~= "Next"
        then
            return assert(control.text:match("^(.-)%-"))
        end
    end
    error("Missing visible menu choice")
end
local expectedCharacter = firstMenuChoice()
frame.scripts.OnKeyDown(frame, "ENTER")
find(expectedCharacter, "Button")
click(expectedCharacter)
menu.scripts.OnMouseWheel(menu, -1)
expectedCharacter = firstMenuChoice()
frame.scripts.OnKeyDown(frame, "ENTER")
find(expectedCharacter, "Button")
click(expectedCharacter)
frame.scripts.OnKeyDown(frame, "PAGEDOWN")
expectedCharacter = firstMenuChoice()
frame.scripts.OnKeyDown(frame, "ENTER")
find(expectedCharacter, "Button")
frame.scripts.OnKeyDown(frame, "ESCAPE")
assert(not frame:IsShown())
for _, control in ipairs(controls) do
    for _, group in ipairs(control.animationGroups or {}) do
        assert(not group.playing, "closing during a transition must stop every animation")
        assert(control.alpha == 1, "interrupted fades must restore opacity")
    end
end
addon.Collection.open(api, store, "Ada", "A")
assert(#frame.animationGroups == 1 and openingFade.playing, "reopening must reuse the opening animation")
local openingPlays = openingFade.plays
addon.Collection.open(api, store, "Ada", "A")
assert(openingFade.plays == openingPlays, "opening an already visible book must not restart the fade")
click("Journal")
click("Clear filters")
find("All characters", "Button")
find("All activity", "Button")
find("Any date", "Button")
find("0 entries")
find(
    "No retained activity in this view. This does not mean no lifetime gains. Retention limits are in AddOns Settings."
)
local bread = "|Hitem:4540::::::::|h[Bread]|h"
local breadKey = addon.Item.key(bread, 4540)
assert(
    store:vendorAction(
        { kind = "purchase", key = breadKey, itemID = 4540, link = bread, quantity = 2 },
        1100,
        { character = "Ada", realm = "A", level = 12, place = "Elwynn" }
    )
)
assert(store:scan({
    character = "Ada",
    realm = "A",
    area = "bags",
    complete = true,
    seenAt = 1101,
    items = { { itemID = 4540, link = bread, quantity = 2 } },
}))
addon.Collection.refresh(store, "Ada", "A")
frame.scripts.OnUpdate(frame, 0.1)
find("1 entry")
assertIconsAboveBackings()
click("Purchase • Bread")
find("Purchase ×2")
assert(not pcall(find, "Recording details: Matched item gain; Purchase: Unknown source"))
assert(addon.Book.setDeveloperMode(store, true))
frame.scripts.OnUpdate(frame)
find("Recording details: Matched item gain; Purchase: Unknown source")
find("Place: Elwynn")
find("Character level")
find("Purchased 2; refunded 0; net gained 2.")
assert(addon.Book.setDeveloperMode(store, false))
frame.scripts.OnUpdate(frame)
local browsingWrites = writes
click("All activity")
click("Looted")
find("0 entries")
find("Select an item to explore\nits history.")
click("Clear filters")
find("1 entry")
click("Any date")
click("Last 24 hours")
find("0 entries")
browsingTime = 604900
click("Last 24 hours")
click("Last 7 days")
ready = false
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
find("1 entry")
local dateAndLoading = date("%d %b %Y  %H:%M", 100)
    .. " through "
    .. date("%d %b %Y  %H:%M", 604900)
    .. " (inclusive)\n1 items awaiting item data"
find(dateAndLoading)
ready = true
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
click("Clear filters")
click("All characters")
click("Ada-A")
find("1 entry")
click("A")
click("B")
find("0 entries")
click("Clear filters")
find("1 entry")
assert(writes == browsingWrites, "Journal controls must be read-only")
click("Collection")
search:SetText("Bread")
frame.scripts.OnUpdate(frame, 0.1)
click("Bread")
local historyWrites = writes
click("View item history")
find("This item's history • newest first")
for _, control in ipairs(controls) do
    if control.text == "Only places linked to\nrecorded gains appear here." then
        assert(not control:IsVisible(), "The place caption must not overlap the history return button")
    end
end
find("1 entry")
click("Back to Collection")
assert(search:GetText() == "Bread", "History must restore the Collection search")
find("Bread", "Button")
assert(writes == historyWrites, "Viewing history must not write permanent facts")
click("Journal")
search:SetText("no match")
frame.scripts.OnUpdate(frame, 0.1)
find("0 entries")
search:SetText("")
frame.scripts.OnUpdate(frame, 0.1)
find("1 entry")
assert(
    store:vendorAction(
        { kind = "refund", key = breadKey, itemID = 4540, link = bread, quantity = 1 },
        1110,
        { character = "Ada", realm = "A", level = 12, place = "Elwynn" }
    )
)
assert(store:scan({
    character = "Ada",
    realm = "A",
    area = "bags",
    complete = true,
    seenAt = 1111,
    items = { { itemID = 4540, link = bread, quantity = 1 } },
}))
addon.Book.refresh(store)
frame.scripts.OnUpdate(frame, 0.1)
click("Refund • Bread")
click("Linked purchase • " .. date("%d %b %Y  %H:%M", 1100))
find("Purchased 2; refunded 1; net gained 1.")
click("Linked refund • " .. date("%d %b %Y  %H:%M", 1110))
find("Refund ×1")
assert(store:setRetention("vendor", 0))
assert(store:setRetention("gains", 0))
addon.Book.refresh(store)
frame.scripts.OnUpdate(frame, 0.1)
find("0 entries")
click("Collection")
find("Bread", "Button")
for _, area in ipairs({ "bags", "equipped", "bank" }) do
    assert(store:scan({
        character = "Ada",
        realm = "A",
        area = area,
        complete = true,
        seenAt = 4000,
        items = area == "bank" and { { itemID = 4540, link = bread, quantity = 5 } } or {},
    }))
end
assert(store:scan({ character = "Ada", realm = "A", area = "bank", complete = false, seenAt = 4100, items = {} }))
addon.Collection.open(api, store, "Ada", "A", "Ada", "A")
frame.scripts.OnUpdate(frame, 0.1)
click("Bread")
find("Unknown")
find("Bank • Last found")
find("5")
find(date("%d %b %Y  %H:%M", 4000))
find("Latest check")
find(date("%d %b %Y  %H:%M", 4100))
click("Review item changes")
find("Item changes to review")
find("No item changes need review in this view.")
assert(store:lootOpen({
    character = "Ada",
    realm = "A",
    level = 12,
    place = "Forest",
    at = 4110,
    slots = { { key = "4540:0", quantity = 1 } },
}))
addon.Book.refresh(store)
frame.scripts.OnUpdate(frame, 0.1)
click("Loot pickup • Bread")
find("Still checking")
find("Ada-A")
local evidenceWrites = writes
frame.scripts.OnKeyDown(frame, "DOWN")
assert(writes == evidenceWrites)
assert(store:expireEvidence(4170))
addon.Book.refresh(store)
frame.scripts.OnUpdate(frame, 0.1)
find("Timed out")
find("This old item change can no longer be confirmed. Future checks will not add it to Total gained.")
search:SetText("nothing matches")
frame.scripts.OnUpdate(frame, 0.1)
find("No matching item changes. Try another search or character/realm filter.")
search:SetText("")
frame.scripts.OnUpdate(frame, 0.1)
for index = 1, 10 do
    assert(
        store:vendorAction(
            { kind = "purchase", key = "4540:0", itemID = 4540, link = bread, quantity = 1 },
            4170 + index,
            { character = "Ada", realm = "A", level = 12, place = "Forest" }
        )
    )
end
addon.Book.refresh(store)
frame.scripts.OnUpdate(frame, 0.1)
find("1 / 2")
frame.scripts.OnKeyDown(frame, "PAGEDOWN")
find("2 / 2")
click("Previous")
find("1 / 2")
click("Collection")
find("Bread", "Button")
print("book_ui_spec: passed (native frame port replay; live client pending)")

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
addon.Book.open(api, queueStore, "Ada", "A")
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
print("book_ui_spec: large evidence queue, loading keyboard access and overflow layout passed")

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
click("Boar • 5")
find("Boar", "Button")
find("GAINED")
find("5")
find("Shows items gained from this source, not everything it can drop.")
local sourceSearch = find("", "EditBox")
sourceSearch:SetText("Boar")
sourceSearch.scripts.OnEnterPressed(sourceSearch)
find("Meat", "Button")
click("All realms")
click("A")
find("GAINED")
click("Clear filters")
find("All sources", "Button")
find("TRACKED")
assert(sourceWrites == 0)
print("book_ui_spec: source navigation, source search, contribution quantity and clearing passed")

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
        ready = false
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
print("book_ui_spec: historical-item hover keeps the Collection visible")
