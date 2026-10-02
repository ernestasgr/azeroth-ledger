-- Native frame port replay: checks visible text and input behavior, not private book state.
local addon = {}
for _, source in ipairs({ "Item", "Schema", "Client", "Collection", "Book" }) do
    assert(loadfile("AzerothLedger/" .. source .. ".lua"))("AzerothLedger", addon)
end
date = os.date
local controls = {}
local function nativeFrame(kind)
    local control = { kind = kind, scripts = {}, shown = true, text = "", width = 1600, height = 900, messages = {} }
    controls[#controls + 1] = control
    for _, method in ipairs({
        "SetPoint",
        "EnableMouse",
        "SetMovable",
        "RegisterForDrag",
        "EnableKeyboard",
        "RegisterEvent",
        "SetJustifyH",
        "SetAutoFocus",
        "SetMaxLetters",
        "SetFontObject",
        "SetMaxLines",
        "SetFading",
        "EnableMouseWheel",
        "SetHyperlinksEnabled",
        "LockHighlight",
        "UnlockHighlight",
    }) do
        control[method] = function() end
    end
    function control:SetScript(event, callback)
        self.scripts[event] = callback
    end
    function control:SetPropagateKeyboardInput(value)
        self.propagate = value
    end
    function control:SetText(value)
        self.text = value
        if self.scripts.OnTextChanged then
            self.scripts.OnTextChanged(self)
        end
    end
    function control:GetText()
        return self.text
    end
    function control:SetSize(width, height)
        self.width, self.height = width, height
    end
    function control:SetHeight(value)
        self.height = value
    end
    function control:SetWidth(value)
        self.width = value
    end
    function control:GetHeight()
        return self.height
    end
    function control:GetWidth()
        return self.width
    end
    function control:SetScale(value)
        self.scale = value
    end
    function control:Show()
        self.shown = true
    end
    function control:Hide()
        self.shown = false
    end
    function control:IsShown()
        return self.shown
    end
    function control:Clear()
        self.messages = {}
    end
    function control:AddMessage(text)
        self.messages[#self.messages + 1] = text
    end
    function control:ScrollUp()
        self.scroll = (self.scroll or 0) + 1
    end
    function control:ScrollDown()
        self.scroll = (self.scroll or 0) - 1
    end
    function control:ScrollToTop()
        self.scroll = 0
    end
    function control:SetFocus()
        self.focus = true
    end
    function control:ClearFocus()
        self.focus = false
    end
    function control:HasFocus()
        return self.focus
    end
    function control:Click()
        self.scripts.OnClick(self)
    end
    function control:CreateFontString()
        return nativeFrame("FontString")
    end
    if kind == "Frame" then
        control.TitleText = nativeFrame("FontString")
    end
    return control
end
local ready = true
local api = {
    UIParent = nativeFrame("Frame"),
    GameFontNormal = {},
    UISpecialFrames = {},
    CreateFrame = nativeFrame,
    IsControlKeyDown = function()
        return true
    end,
    C_Item = {
        GetItemInfo = function(link)
            if not ready then
                return nil
            end
            local id = tonumber(link:match("item:(%d+)"))
            return "Name", link, 1, nil, nil, nil, nil, nil, nil, nil, nil, id == 2672 and 7 or 2
        end,
    },
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
local before = writes
local frame = assert(addon.Collection.open(api, store, "Ada", "A"))
local function find(text)
    for _, control in ipairs(controls) do
        if control.text == text and control.shown then
            return control
        end
    end
    error("Missing visible control: " .. text)
end
local function click(text)
    find(text):Click()
end
find("15 results • 15 account discoveries")
local details
local search
for _, control in ipairs(controls) do
    if control.kind == "ScrollingMessageFrame" then
        details = control
    end
    if control.kind == "EditBox" then
        search = control
    end
end
assert(table.concat(details.messages, "\n"):find("Recorded units: 400", 1, true))
click("Next >")
find("Page 2 / 2")
assert(table.concat(details.messages, "\n"):find("Recorded units: 400", 1, true), "details must persist across pages")
click("Weapons")
find("14 results • 15 account discoveries")
click("Materials")
find("1 results • 15 account discoveries")
search:SetText("missing")
frame.scripts.OnUpdate()
find("0 results • 15 account discoveries")
find("No discoveries match these filters.")
click("Reset filters")
frame.scripts.OnKeyDown(frame, "F")
assert(search:HasFocus())
search.scripts.OnEnterPressed(search)
assert(not search:HasFocus())
frame.scripts.OnKeyDown(frame, "DOWN")
assert(table.concat(details.messages, "\n"):find("Variant: 101:0", 1, true))
frame.scripts.OnKeyDown(frame, "TAB")
frame.scripts.OnKeyDown(frame, "ENTER")
click("Recent discoveries")
find("Discoveries")
click("Scale –")
assert(frame.scale < 1)
ready = false
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
find(" Item data loading or unavailable: 15. Unknown category remains searchable.")
ready = true
frame.scripts.OnEvent()
frame.scripts.OnUpdate()
assert(writes == before, "browsing must not write SavedVariables")
frame.scripts.OnKeyDown(frame, "ESCAPE")
assert(not frame:IsShown())
print("book_ui_spec: passed (native frame port replay; live client pending)")
