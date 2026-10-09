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
local before = writes
local frame = assert(addon.Collection.open(api, store, "Ada", "A"))
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
find("Discovery history")
find("How it was recorded")
click("Show all 2 recorded links")
find("|Hitem:2672::::::::|h[Meat]|h", "Button")
find("|cffffffff|Hitem:2672:0:0:0:0:0:0:0:15:7|h[Meat]|h|r", "Button")
click("Show distinct versions")
find("Show all 2 recorded links", "Button")
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
click("Materials")
find("1 item")
search:SetText("missing")
frame.scripts.OnUpdate()
find("0 items")
find("No matching items. Try another search or clear your filters.")
click("Clear filters")
click("Historical only")
find("0 items")
click("Clear filters")
find("15 items")
click("Found once")
find("0 items")
click("Clear filters")
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
click("All recorded places")
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
ready = true
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
assert(writes == before, "browsing must not write SavedVariables")
click("All characters")
click("Ben-B")
click("Meat")
find("Character", "Button")
find("10")
click("Account")
find("400")
click("Character")
local stats = find("CHECKED UNITS", "FontString").parent
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
click("All recorded places")
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
find("0 activities")
find("No retained activity. Retention limits are in AddOns Settings.")
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
find("1 activities")
assertIconsAboveBackings()
click("Purchase • Bread")
find("Purchase ×2")
find("Matched item gain; Vendor: Unknown source")
search:SetText("no match")
frame.scripts.OnUpdate(frame, 0.1)
find("0 activities")
search:SetText("")
frame.scripts.OnUpdate(frame, 0.1)
find("1 activities")
assert(store:setRetention("gains", 0))
addon.Book.refresh(store)
frame.scripts.OnUpdate(frame, 0.1)
find("0 activities")
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
find("Bank • Last observed")
find("5")
find(date("%d %b %Y  %H:%M", 4000))
find("Current check")
find(date("%d %b %Y  %H:%M", 4100))
print("book_ui_spec: passed (native frame port replay; live client pending)")
