local _, addon = ...

local Book = {}
local active
local PAGE_SIZE = 12
local PLACE_SIZE = 6

local function label(parent, text, x, y, width)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    font:SetPoint("TOPLEFT", x, y)
    font:SetWidth(width)
    font:SetJustifyH("LEFT")
    font:SetText(text)
    return font
end

local function button(book, parent, text, x, y, width, callback)
    local control = book.api.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetPoint("TOPLEFT", x, y)
    control:SetText(text)
    control:SetScript("OnClick", callback)
    book.controls[#book.controls + 1] = control
    return control
end

local function fit(book)
    local parent = book.api.UIParent
    local width, height = parent:GetWidth(), parent:GetHeight()
    book.frame:SetScale(math.min(book.scale, width / 1080, height / 700))
end

local function select(book, key)
    book.selected = key
    book.details:Clear()
    for _, line in ipairs(addon.Collection.details(book.store, key, book.character, book.realm, book.filter)) do
        book.details:AddMessage(line)
    end
    book.details:ScrollToTop()
    for _, row in ipairs(book.rows) do
        if row.key == key then
            row:LockHighlight()
        else
            row:UnlockHighlight()
        end
    end
end

local function warning(book)
    local diagnostic = book.store:diagnostic()
    local evidence = book.store:evidenceSummary()
    if diagnostic.kind ~= "healthy" then
        return "Saved data: " .. diagnostic.kind .. "; readable history shown"
    end
    if evidence.discarded > 0 then
        return "WARNING: "
            .. evidence.discarded
            .. " unresolved records discarded ("
            .. date("%Y-%m-%d", evidence.firstDiscarded)
            .. " – "
            .. date("%Y-%m-%d", evidence.lastDiscarded)
            .. ")"
    end
    local unresolved = #book.store:unresolved()
    return unresolved > 0 and (unresolved .. " unresolved evidence records; no guessed gains") or ""
end

local function render(book)
    local result = addon.Collection.query(book.store, book.character, book.realm, book.filter, function(record)
        return addon.Client.itemMetadata(book.api, record)
    end)
    book.result = result
    book.page = math.max(1, math.min(book.page, math.max(1, math.ceil(#result.rows / PAGE_SIZE))))
    book.count:SetText(#result.rows .. " results • " .. result.discoveryCount .. " account discoveries")
    local state = #result.rows == 0 and "No discoveries match these filters." or ""
    if result.discoveryCount == 0 then
        state = "No items Seen yet. Open your bags or bank to record items."
    end
    if result.loading > 0 then
        state = state
            .. " Item data loading or unavailable: "
            .. result.loading
            .. ". Unknown category remains searchable."
    end
    book.state:SetText(state)
    book.warning:SetText(warning(book))
    book.scope:SetText(
        book.filter.character and (book.filter.character .. "-" .. book.filter.realm) or book.filter.realm or "Account"
    )
    book.view:SetText(book.filter.view or "Collection")
    for index, row in ipairs(book.rows) do
        local item = result.rows[(book.page - 1) * PAGE_SIZE + index]
        row.key = item and item.key or nil
        if item then
            local info = book.filter.view == "Discoveries" and date("%Y-%m-%d %H:%M", item.discoveredAt)
                or (item.category .. " • Recorded " .. (item.record.firstSeenUnits + item.record.totalGained))
            row:SetText(item.name .. "\n" .. info .. " • " .. item.key)
            row:Show()
        else
            row:Hide()
        end
    end
    book.pageLabel:SetText("Page " .. book.page .. " / " .. math.max(1, math.ceil(#result.rows / PAGE_SIZE)))
    book.placePage = math.max(1, math.min(book.placePage, math.max(1, math.ceil(#result.places / PLACE_SIZE))))
    for index, control in ipairs(book.places) do
        local place = result.places[(book.placePage - 1) * PLACE_SIZE + index]
        control.place = place
        if place then
            local kinds = { zone = "Zone", dungeon = "Dungeon", place = "Recorded place" }
            control:SetText(kinds[place.kind] .. ": " .. place.name)
            control:Show()
        else
            control:Hide()
        end
    end
    book.placeLabel:SetText(#result.places == 0 and "No confirmed places yet" or "Recorded discoveries by place")
    book.placeFilter:SetText(book.filter.place or "All places")
    select(book, book.selected or (result.rows[1] and result.rows[1].key))
    book.dirty = false
end

local function change(book, field, value)
    book.filter[field] = value
    book.page = 1
    render(book)
end

local function cycleScope(book, kind)
    local choices = { { name = "Account" } }
    local seen = {}
    for _, actor in ipairs(book.store:characters()) do
        local key = kind == "realm" and actor.realm or actor.realm .. ":" .. actor.character
        if not seen[key] then
            seen[key] = true
            choices[#choices + 1] = { character = kind == "character" and actor.character or nil, realm = actor.realm }
        end
    end
    local index = 1
    for position, choice in ipairs(choices) do
        if choice.character == book.filter.character and choice.realm == book.filter.realm then
            index = position
        end
    end
    local nextChoice = choices[index % #choices + 1]
    book.filter.character, book.filter.realm = nextChoice.character, nextChoice.realm
    book.page = 1
    render(book)
end

local function turnPage(book, delta)
    book.page = book.page + delta
    render(book)
end

local function keyboard(book, key)
    local frame = book.frame
    frame:SetPropagateKeyboardInput(false)
    if key == "ESCAPE" then
        book.search:ClearFocus()
        frame:Hide()
        return
    end
    if book.search:HasFocus() then
        frame:SetPropagateKeyboardInput(true)
        return
    end
    if key == "F" and book.api.IsControlKeyDown and book.api.IsControlKeyDown() then
        book.search:SetFocus()
        return
    end
    if key == "TAB" then
        if book.focus then
            book.controls[book.focus]:UnlockHighlight()
        end
        local direction = book.api.IsShiftKeyDown and book.api.IsShiftKeyDown() and -1 or 1
        local index = book.focus or 0
        for _ = 1, #book.controls do
            index = (index + direction - 1) % #book.controls + 1
            if book.controls[index]:IsShown() then
                break
            end
        end
        book.focus = index
        book.controls[index]:LockHighlight()
        return
    end
    if key == "ENTER" and book.focus then
        book.controls[book.focus]:Click()
        return
    end
    if key == "PAGEUP" or key == "PAGEDOWN" then
        turnPage(book, key == "PAGEUP" and -1 or 1)
        return
    end
    if key == "UP" or key == "DOWN" then
        local index = 1
        for position, row in ipairs(book.result.rows) do
            if row.key == book.selected then
                index = position
            end
        end
        index = math.max(1, math.min(#book.result.rows, index + (key == "UP" and -1 or 1)))
        local row = book.result.rows[index]
        if row then
            book.selected = row.key
            book.page = math.ceil(index / PAGE_SIZE)
            render(book)
        end
        return
    end
    frame:SetPropagateKeyboardInput(true)
end

local function create(api)
    local frame = api.CreateFrame("Frame", "AzerothLedgerCollection", api.UIParent, "BasicFrameTemplateWithInset")
    local book = {
        api = api,
        frame = frame,
        controls = {},
        rows = {},
        places = {},
        filter = {},
        page = 1,
        placePage = 1,
        scale = 1,
    }
    frame:SetSize(1060, 680)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("Azeroth Ledger")
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(_, key)
        keyboard(book, key)
    end)
    frame:SetScript("OnUpdate", function()
        if book.dirty then
            render(book)
        end
    end)
    frame:SetScript("OnEvent", function()
        book.dirty = true
        fit(book)
    end)
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    if api.UISpecialFrames then
        table.insert(api.UISpecialFrames, "AzerothLedgerCollection")
    end

    label(frame, "Browse", 18, -40, 185)
    button(book, frame, "Collection", 18, -65, 185, function()
        change(book, "view", "Collection")
    end)
    button(book, frame, "Recent discoveries", 18, -93, 185, function()
        change(book, "view", "Discoveries")
    end)
    local categories =
        { "All categories", "Weapons", "Armour", "Recipes", "Materials", "Consumables", "Junk", "Other", "Unknown" }
    for index, category in ipairs(categories) do
        button(book, frame, category, 18, -125 - (index - 1) * 26, 185, function()
            change(book, "category", category ~= "All categories" and category or nil)
        end)
    end
    book.placeLabel = label(frame, "Recorded discoveries by place", 18, -365, 185)
    book.placeFilter = button(book, frame, "All places", 18, -395, 185, function()
        book.filter.place, book.filter.placeKind = nil, nil
        book.page = 1
        render(book)
    end)
    for index = 1, PLACE_SIZE do
        local control
        control = button(book, frame, "", 18, -425 - (index - 1) * 26, 185, function()
            if control.place then
                book.filter.placeKind = control.place.kind
                change(book, "place", control.place.name)
            end
        end)
        book.places[index] = control
    end
    button(book, frame, "< Places", 18, -585, 90, function()
        book.placePage = math.max(1, book.placePage - 1)
        render(book)
    end)
    button(book, frame, "Places >", 113, -585, 90, function()
        book.placePage = book.placePage + 1
        render(book)
    end)

    book.view = label(frame, "Collection", 220, -40, 410)
    book.scope = label(frame, "Account", 650, -40, 385)
    button(book, frame, "Account", 220, -65, 125, function()
        book.filter.character, book.filter.realm = nil, nil
        book.page = 1
        render(book)
    end)
    button(book, frame, "Character >", 350, -65, 135, function()
        cycleScope(book, "character")
    end)
    button(book, frame, "Realm >", 490, -65, 140, function()
        cycleScope(book, "realm")
    end)
    button(book, frame, "Historical only", 650, -65, 185, function(self)
        change(book, "historical", not book.filter.historical)
        self:SetText(book.filter.historical and "Historical only: on" or "Historical only")
    end)
    button(book, frame, "Found once", 840, -65, 195, function(self)
        change(book, "foundOnce", not book.filter.foundOnce)
        self:SetText(book.filter.foundOnce and "Found once: on" or "Found once")
    end)
    label(frame, "Search name, item ID or variant (Ctrl+F)", 220, -100, 410)
    book.search = api.CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    book.search:SetSize(400, 24)
    book.search:SetPoint("TOPLEFT", 225, -125)
    book.search:SetAutoFocus(false)
    book.search:SetMaxLetters(160)
    book.search:SetScript("OnTextChanged", function(self)
        book.filter.search = self:GetText()
        book.page = 1
        book.dirty = true
    end)
    book.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    book.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        render(book)
    end)
    book.search:SetScript("OnTabPressed", function(self)
        self:ClearFocus()
        keyboard(book, "TAB")
    end)
    button(book, frame, "Search", 650, -125, 185, function()
        book.search:SetFocus()
    end)
    button(book, frame, "Reset filters", 840, -125, 195, function()
        book.filter = {}
        book.search:SetText("")
        book.page = 1
        render(book)
    end)
    book.count = label(frame, "", 220, -162, 410)
    for index = 1, PAGE_SIZE do
        local row
        row = button(book, frame, "", 220, -188 - (index - 1) * 32, 410, function()
            if row.key then
                select(book, row.key)
            end
        end)
        row:SetHeight(30)
        book.rows[index] = row
    end
    button(book, frame, "< Previous", 220, -582, 120, function()
        turnPage(book, -1)
    end)
    book.pageLabel = label(frame, "", 350, -588, 150)
    button(book, frame, "Next >", 510, -582, 120, function()
        turnPage(book, 1)
    end)
    book.state = label(frame, "", 220, -618, 410)

    label(frame, "Item details • account history", 650, -162, 385)
    book.details = api.CreateFrame("ScrollingMessageFrame", nil, frame)
    book.details:SetPoint("TOPLEFT", 650, -188)
    book.details:SetSize(385, 415)
    book.details:SetFontObject(api.GameFontNormal)
    book.details:SetJustifyH("LEFT")
    book.details:SetMaxLines(10000)
    book.details:SetFading(false)
    book.details:EnableMouseWheel(true)
    book.details:SetHyperlinksEnabled(true)
    book.details:SetScript("OnHyperlinkClick", function(_, link, text, mouseButton)
        if api.SetItemRef then
            api.SetItemRef(link, text, mouseButton)
        end
    end)
    book.details:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)
    button(book, frame, "Details up", 650, -610, 185, function()
        book.details:ScrollUp()
    end)
    button(book, frame, "Details down", 840, -610, 195, function()
        book.details:ScrollDown()
    end)
    book.warning = label(frame, "", 18, -650, 820)
    button(book, frame, "Scale –", 840, -645, 90, function()
        book.scale = math.max(0.6, book.scale - 0.1)
        fit(book)
    end)
    button(book, frame, "Scale +", 935, -645, 100, function()
        book.scale = math.min(1.3, book.scale + 0.1)
        fit(book)
    end)
    fit(book)
    return book
end

---@param api table
---@param store ALStore
---@param character string
---@param realm string
---@param filterCharacter? string
---@param filterRealm? string
---@return table?
function Book.open(api, store, character, realm, filterCharacter, filterRealm)
    if type(api.CreateFrame) ~= "function" then
        return nil
    end
    active = active or create(api)
    active.store, active.character, active.realm = store, character, realm
    active.filter.character, active.filter.realm = filterCharacter, filterRealm
    render(active)
    active.frame:Show()
    return active.frame
end

function Book.refresh(store, character, realm)
    if active then
        active.store, active.character, active.realm = store, character, realm
        active.dirty = true
    end
end

addon.Book = Book
