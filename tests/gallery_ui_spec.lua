-- Native UI boundary replay; native model rendering still requires the Forever client.
local addon = {}
for _, source in ipairs({ "Item", "Schema", "Client", "Collection", "Journal", "BookWidgets", "Book" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
date = os.date
local native = assert(loadfile("tests/support/native_ui.lua"))().create()
local api = native.api
local bear = "|Hitem:100:0:0:0:0:0:42:1:60:0:0:0:1:111|h[Sword Bear]|h"
local enchanted = "|Hitem:100:88:55:0:0:0:42:9:60:0:0:0:1:111|h[Sword Bear]|h"
local wolf = "|Hitem:100:0:0:0:0:0:43:1:60:0:0:0:1:111|h[Sword Wolf]|h"
local meat = "|Hitem:2672::::::::|h[Meat]|h"
local ready, wearable, shown = true, true, nil
local failPreview = false
api.C_Item = {
    GetItemInfo = function(link)
        if not ready then
            return nil
        end
        return "Name", link, 1, nil, nil, nil, nil, nil, nil, 134400, nil, link == meat and 7 or 2
    end,
    IsDressableItemByID = function()
        return wearable
    end,
}
api.DressUpItemLink = function(link)
    if failPreview then
        error("unavailable model")
    end
    shown = link
    return true
end
local writes = 0
local store = addon.Schema.open(nil, function()
    writes = writes + 1
end)
assert(store:scan({
    character = "Ada",
    realm = "A",
    area = "bags",
    complete = true,
    seenAt = 1000,
    items = {
        { itemID = 100, link = bear, quantity = 1 },
        { itemID = 2672, link = meat, quantity = 400 },
    },
}))
assert(store:scan({
    character = "Ben",
    realm = "B",
    area = "bags",
    complete = true,
    seenAt = 1001,
    items = {
        { itemID = 100, link = enchanted, quantity = 1 },
        { itemID = 100, link = wolf, quantity = 1 },
    },
}))
local before = writes
local frame = assert(addon.Collection.open(api, store, "Ada", "A"))
local function find(text, kind)
    for index = #native.controls, 1, -1 do
        local control = native.controls[index]
        if control.text == text and control:IsVisible() and (not kind or control.kind == kind) then
            return control
        end
    end
    error("Missing visible control: " .. text)
end
local function click(text)
    find(text, "Button"):Click()
end
click("Gallery")
find("2 items")
assert(find("Sword Bear", "Button"):GetHeight() > 80, "gear should appear in gallery cards")
click("Sword Bear")
click("Saved link 1 of 2")
frame.scripts.OnKeyDown(frame, "DOWN")
frame.scripts.OnKeyDown(frame, "ENTER")
click("Preview gear")
assert(shown == enchanted, "preview must use the selected saved link, including enchants and gems")
find("Opened the native dressing room.")
frame.scripts.OnKeyDown(frame, "DOWN")
find("Saved link 1 of 1", "Button")
click("Preview gear")
assert(shown == wolf, "keyboard selection must preview the other intrinsic variant")
click("All characters")
click("Ada-A")
find("1 item")
find("Sword Bear", "FontString")
click("A")
click("B")
find("2 items")
click("Clear filters")
find("Gallery", "Button")
find("2 items")
ready = false
frame.scripts.OnEvent(frame, "ITEM_DATA_LOAD_RESULT", 100, false)
frame.scripts.OnUpdate()
find("3 items awaiting item data")
find("Item data is not loaded yet. Preview when it becomes available.")
assert(not find("Preview gear", "Button"):IsEnabled())
ready = true
wearable = false
frame.scripts.OnEvent(frame, "ITEM_DATA_LOAD_RESULT", 100, true)
frame.scripts.OnUpdate()
find("This item cannot be worn in the dressing room. Its saved link is available below.")
wearable = true
failPreview = true
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
click("Preview gear")
find("Native preview is unavailable. Its saved link is available below.")
click("All realms")
click("B")
click("All characters")
click("Ben-B")
find("2 items")
-- A search can empty the gallery without retaining a preview from the previous scope.
for _, control in ipairs(native.controls) do
    if control.kind == "EditBox" then
        control:SetText("missing")
    end
end
frame.scripts.OnUpdate()
find("0 items")
find("No matching gear. Try another search or clear your filters.")
for _, control in ipairs(native.controls) do
    assert(
        not (control.text == "Preview gear" and control:IsVisible()),
        "an empty gallery must not preview stale selection"
    )
end
click("Clear filters")
click("−")
assert(frame:GetScale() < 1)
assert(writes == before, "gallery selection and previews must not write SavedVariables")
print("gallery_ui_spec: passed (native boundary replay; live client pending)")
