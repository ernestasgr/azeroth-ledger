-- Native frame port replay: checks visible text and input behavior, not private book state.
local addon = {}
for _, source in ipairs({ "Item", "Schema", "Client", "Collection", "BookWidgets", "Book" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
date = os.date
local native = assert(loadfile("tests/support/native_ui.lua"))().create()
local controls = native.controls
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
print("book_ui_spec: passed (native frame port replay; live client pending)")
