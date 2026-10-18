local _, addon = ...

-- Builds the Collection window: layout, anchors, and reusable row widgets.
-- Controls report input through the actions table; they hold no view state.
local BookFrame = {}
local Widgets = addon.BookWidgets
local State = addon.BookState
local colors = Widgets.colors
BookFrame.DETAIL_HEIGHT = 320
BookFrame.DETAIL_WIDTH = 338

local FONT = "Fonts\\FRIZQT__.TTF"
local CATEGORIES =
    { "All items", "Weapons", "Armour", "Recipes", "Materials", "Consumables", "Junk", "Other", "Unknown" }
local HELP_TEXT = "The Ledger tracks characters after you log in on them. "
    .. "Open each character's bank to check its contents.\n\n"
    .. "Character overall counts that character's first-seen units plus confirmed gains, after refunds. "
    .. "All characters overall adds those character totals.\n\n"
    .. "Current counts add the latest known quantities in bags, bank, and equipped gear "
    .. "for every tracked character, including offline characters.\n\n"
    .. "Character overall shows Unknown if saved history cannot separate a confirmed gain "
    .. "from the first recorded stock.\n\n"
    .. "Current counts use saved quantities, which can be from different times. "
    .. "Areas with no saved check add no known quantity.\n"
for _, choice in ipairs(addon.LastSeen.ownershipChoices()) do
    if choice.value then
        HELP_TEXT = HELP_TEXT .. "\n" .. addon.LastSeen.ownership(choice.value).help
    end
end

local function font(api)
    return api.STANDARD_TEXT_FONT or FONT
end

local function tooltip(book, control, link)
    control:SetScript("OnEnter", function()
        Widgets.tooltip(book.api, control, link())
    end)
    control:SetScript("OnLeave", function()
        Widgets.hideTooltip(book.api)
    end)
end

-- List rows and gallery cards: one presentation, two layouts.
local ItemRowMixin = {}

---@param model table? from BookRender.rowModel; nil hides the row
function ItemRowMixin:present(model)
    self.key = model and model.key or nil
    self.evidenceID = model and model.evidenceID or nil
    self.sequence = model and model.sequence or nil
    self.fullLink = model and model.fullLink or nil
    self:SetShown(model ~= nil)
    if not model then
        return
    end
    self:SetText(model.text)
    self.nameColor = model.color
    Widgets.tint(self:GetFontString(), self.nameColor)
    Widgets.itemIcon(self.icon, model.icon)
    self.subtitle:SetText(model.subtitle)
    self.quantity:SetText(model.quantity)
end

-- Detail rows are reusable native regions with measured heights, inside a real scroll frame.
local DetailRowMixin = {}

function DetailRowMixin:reset()
    self.left:ClearAllPoints()
    self.left:SetPoint("TOPLEFT", 0, -4)
    self.right:Hide()
    self.line:Hide()
    self.section:Hide()
    self.onClick = nil
    self.fullLink = nil
    self.link:Hide()
end

-- Evidence details are plain wrapped lines; the last may be the saved item link.
---@return number height
function DetailRowMixin:presentLine(text, title, link)
    self:reset()
    self.left:SetWidth(BookFrame.DETAIL_WIDTH)
    Widgets.tint(self.left, title and colors.gold or colors.text)
    self.left:SetText(text)
    self.left:Show()
    if link then
        self.fullLink = link
        self.link:SetText(link)
        self.link:Show()
        self.left:Hide()
    end
    local height = math.max(34, self.left:GetStringHeight() + 16)
    self:SetHeight(height)
    self:Show()
    return height
end

-- Lays out one Collection or Journal detail row by kind: note, pair, date,
-- section, link, or action. Returns nil when a collapsed section hides it.
---@return number? height
function DetailRowMixin:present(kind, left, right, collapsed)
    local api = self.api
    self.left:ClearAllPoints()
    self.right:ClearAllPoints()
    self.left:SetPoint("TOPLEFT", 0, -4)
    self.right:SetPoint("TOPLEFT", 254, -4)
    self.left:SetWidth(kind == "note" and BookFrame.DETAIL_WIDTH or 246)
    self.right:SetWidth(84)
    Widgets.tint(self.left, kind == "section" and colors.gold or colors.text)
    self.left:SetFont(font(api), kind == "section" and 13 or 12, "")
    Widgets.tint(self.right, colors.muted)
    self.left:SetText(left)
    self.right:SetText(right or "")
    self.link:ClearAllPoints()
    self.link:SetPoint("TOPLEFT", 0, 0)
    self.link:SetSize(BookFrame.DETAIL_WIDTH, 30)
    self.link.background:Show()
    local linkText = self.link:GetFontString()
    linkText:ClearAllPoints()
    linkText:SetPoint("TOPLEFT", 12, -8.5)
    linkText:SetWidth(314)
    linkText:SetFont(font(api), 12, "")
    Widgets.tint(linkText, colors.text)
    local clickable = kind == "link" or kind == "action" or kind == "section"
    self.left:SetShown(not clickable)
    self.right:SetShown(not clickable)
    self.link:SetShown(clickable)
    self.line:SetShown(kind == "section")
    self.section:SetShown(kind == "section")
    self.fullLink = kind == "link" and left or nil
    self.disclosureIcon:Hide()
    self.link:SetText(left)
    if kind == "section" then
        self.link:SetSize(BookFrame.DETAIL_WIDTH, 40)
        self.link.background:Hide()
        linkText:ClearAllPoints()
        linkText:SetPoint("TOPLEFT", 28, -14)
        linkText:SetWidth(300)
        linkText:SetFont(font(api), 13, "")
        Widgets.tint(linkText, colors.gold)
        self.disclosureIcon:SetTexture(
            collapsed and "Interface\\Buttons\\UI-PlusButton-UP" or "Interface\\Buttons\\UI-MinusButton-UP"
        )
        self.disclosureIcon:Show()
    end
    local height = math.max(24, self.left:GetStringHeight() + 10, self.right:GetStringHeight() + 10)
    if kind == "section" then
        self.line:ClearAllPoints()
        self.line:SetPoint("TOPLEFT", 0, -16)
        self.line:SetSize(2, 14)
        Widgets.tint(self.line, colors.gold, true)
        self.section:ClearAllPoints()
        self.section:SetPoint("TOPLEFT", 0, -6)
        self.section:SetSize(BookFrame.DETAIL_WIDTH, 1)
        Widgets.tint(self.section, colors.edge, true)
        height = 40
    elseif collapsed then
        self.left:Hide()
        self.right:Hide()
        self.link:Hide()
        self.line:Hide()
        self.section:Hide()
        self:SetHeight(1)
        self:Hide()
        return nil
    end
    if kind == "date" then
        self.left:SetWidth(118)
        self.right:ClearAllPoints()
        self.right:SetPoint("TOPLEFT", 120, -4)
        self.right:SetWidth(218)
        height = math.max(24, self.right:GetStringHeight() + 10)
    end
    if kind == "link" or kind == "action" then
        height = 34
    end
    self:SetHeight(height)
    self:Show()
    return height
end

---@return table row a DetailRowMixin frame, created on first use
function BookFrame.detailRow(book, index)
    local row = book.detailRows[index]
    if row then
        return row
    end
    local api = book.api
    row = Widgets.mixin(api.CreateFrame("Frame", nil, book.detailBody), DetailRowMixin)
    row.api = api
    row:SetWidth(BookFrame.DETAIL_WIDTH)
    row.left = Widgets.text(api, row, "", 0, 4, 246, 12)
    row.right = Widgets.text(api, row, "", 254, 4, 84, 12)
    row.right:SetJustifyH("RIGHT")
    row.line = Widgets.fill(row, colors.edge, 0, 26, BookFrame.DETAIL_WIDTH, 1, "ARTWORK")
    row.section = Widgets.fill(row, colors.raised, 0, 12, BookFrame.DETAIL_WIDTH, 32)
    row.link = Widgets.button(book, row, "", 0, 0, BookFrame.DETAIL_WIDTH, 30, function(_, mouseButton)
        if row.onClick then
            row.onClick()
        else
            Widgets.openLink(api, row.fullLink, mouseButton)
        end
    end)
    row.disclosureIcon = row.link:CreateTexture(nil, "ARTWORK", nil, 1)
    row.disclosureIcon:SetPoint("LEFT", row.link, "LEFT", 8, 0)
    row.disclosureIcon:SetSize(16, 16)
    row.disclosureIcon:Hide()
    tooltip(book, row.link, function()
        return row.fullLink
    end)
    book.detailRows[index] = row
    return row
end

function BookFrame.hideDetailRows(book)
    for _, row in ipairs(book.detailRows) do
        row:Hide()
    end
end

-- Positions the detail scroll area for the current view.
function BookFrame.detailArea(book, top, height)
    book.detailScroll:ClearAllPoints()
    book.detailScroll:SetPoint("TOPLEFT", 16, -top)
    book.detailScroll:SetHeight(height)
end

-- Restores scroll for the same selection, and starts a new selection at the top.
function BookFrame.finishDetails(book, height, keepScroll, oldScroll)
    book.detailBody:SetHeight(math.max(1, height))
    book.detailScroll:SetVerticalScroll(
        keepScroll and math.min(oldScroll, math.max(0, height - book.detailScroll:GetHeight())) or 0
    )
end

---@param placement table from BookState.place
function BookFrame.place(book, placement)
    local parent = book.api.UIParent
    book.frame:SetScale(placement.scale)
    book.frame:ClearAllPoints()
    book.frame:SetPoint("CENTER", parent, "CENTER", placement.x / placement.scale, placement.y / placement.scale)
    if book.shrink then
        Widgets.enable(book.shrink, placement.scale > State.MIN_SCALE + 0.001)
    end
    if book.expand then
        Widgets.enable(book.expand, placement.scale < placement.maximum - 0.001)
    end
end

function BookFrame.closeMenu(book)
    book.menu:Hide()
    book.menuAnchor = nil
end

-- Sidebar dropdowns sit low in the window, so their menus open upward.
function BookFrame.anchorMenu(book, anchor)
    book.menu:ClearAllPoints()
    if
        anchor == book.place
        or anchor == book.sourceFilter
        or anchor == book.ownershipFilter
        or anchor == book.qualityFilter
        or anchor == book.methodFilter
    then
        book.menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    else
        book.menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    end
    book.menu:SetFrameLevel(book.frame:GetFrameLevel() + 20)
end

local function itemButton(book, actions, x, y, width, height)
    local row
    row = Widgets.button(book, book.frame, "", x, y, width, height, function(_, mouseButton)
        actions.rowClicked(row, mouseButton)
    end)
    Widgets.mixin(row, ItemRowMixin)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tooltip(book, row, function()
        return row.fullLink
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        actions.turnPage(delta > 0 and -1 or 1)
    end)
    return row
end

local function header(book, actions)
    local api, frame = book.api, book.frame
    local panel = Widgets.panel(api, frame, 0, 0, 1100, 82, colors.panel)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function()
        if not Widgets.preferences.lockWindow then
            frame:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local px, py = api.UIParent:GetCenter()
        local scale = frame:GetScale()
        actions.moved(x * scale - px, y * scale - py)
    end)
    local emblem = Widgets.icon(panel, 24, 24, 32)
    emblem:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    Widgets.text(api, panel, "Azeroth Ledger", 70, 20, 420, 24, colors.gold)
    Widgets.text(api, panel, "Your account's item collection", 72, 51, 420, 12, colors.muted)
    Widgets.fill(panel, colors.gold, 0, 22, 3, 38, "ARTWORK")
    Widgets.fill(panel, colors.raised, 810, 20, 192, 42)
    book.discoveries = Widgets.text(api, panel, "", 820, 32, 170, 16, colors.gold)
    book.discoveries:SetJustifyH("RIGHT")
    return panel
end

local function sidebar(book, actions)
    local api = book.api
    local panel = Widgets.panel(api, book.frame, 20, 100, 178, 552)
    book.backToCollection =
        Widgets.button(book, panel, "Back to Collection", 6, 466, 166, 32, actions.returnFromHistory)
    Widgets.text(api, panel, "CATEGORIES", 12, 16, 154, 10, colors.muted)
    for index, category in ipairs(CATEGORIES) do
        local selectedCategory = category ~= "All items" and category or nil
        local control = Widgets.button(book, panel, category, 0, 42 + (index - 1) * 30, 178, 28, function()
            actions.change("category", selectedCategory)
        end)
        control.category = selectedCategory
        control:GetFontString():SetWidth(122)
        control.count = Widgets.text(api, control, "", 136, 10, 30, 11, colors.muted)
        control.count:SetJustifyH("RIGHT")
        book.categories[index] = control
    end
    Widgets.fill(panel, colors.edge, 12, 326, 154, 1, "ARTWORK")
    Widgets.text(api, panel, "ITEM HISTORY", 12, 337, 154, 10, colors.muted)
    book.sourceFilter = Widgets.dropdown(book, panel, "All sources", 6, 354, 166, actions.sourceMenu)
    book.place = Widgets.dropdown(book, panel, "All places", 6, 398, 166, actions.placeMenu)
    return panel
end

local function tabs(book, actions)
    local frame = book.frame
    Widgets.fill(frame, colors.edge, 218, 131, 440, 1, "ARTWORK")
    local function tab(label, x, width)
        return Widgets.tab(book, frame, label, x, 100, width, function()
            actions.change("view", label)
        end)
    end
    book.collectionTab = tab("Collection", 218, 106)
    book.discoveryTab = tab("Discoveries", 330, 118)
    book.journalTab = tab("Journal", 454, 96)
    book.galleryTab = tab("Gallery", 556, 102)
end

local function search(book, actions)
    local api = book.api
    local surface = Widgets.panel(api, book.frame, 218, 146, 440, 36, colors.raised)
    local accent = Widgets.fill(surface, colors.gold, 0, 35, 440, 1, "ARTWORK")
    accent:Hide()
    local box = api.CreateFrame("EditBox", nil, surface)
    book.search = box
    box:SetPoint("TOPLEFT", 12, -2)
    box:SetSize(410, 32)
    box:SetFont(font(api), 12, "")
    Widgets.tint(box, colors.text)
    box:SetAutoFocus(false)
    box:SetMaxLetters(160)
    book.placeholder = Widgets.text(api, surface, "Search your collection…", 12, 12, 400, 12, colors.muted)
    box:SetScript("OnTextChanged", function(self)
        book.placeholder:SetShown(self:GetText() == "")
        actions.searchChanged(self:GetText())
    end)
    box:SetScript("OnEditFocusGained", function()
        book.placeholder:Hide()
        accent:Show()
        BookFrame.closeMenu(book)
    end)
    box:SetScript("OnEditFocusLost", function()
        accent:Hide()
        book.placeholder:SetShown(box:GetText() == "")
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        actions.render()
    end)
    box:SetScript("OnTabPressed", function(self)
        self:ClearFocus()
        actions.focusControl(book.scope)
    end)
end

local function filters(book, actions, side)
    local frame = book.frame
    book.scope = Widgets.dropdown(book, frame, "All characters", 218, 194, 216, function(self)
        actions.scopeMenu(self, "character")
    end)
    book.realmFilter = Widgets.dropdown(book, frame, "All realms", 442, 194, 216, function(self)
        actions.scopeMenu(self, "realm")
    end)
    local function browseDropdown(field, parent, x, y, width)
        return Widgets.dropdown(book, parent, "", x, y, width, function(self)
            actions.browseMenu(self, field)
        end)
    end
    book.ownershipFilter = browseDropdown("ownership", side, 6, 438, 132)
    book.qualityFilter = browseDropdown("quality", side, 6, 474, 166)
    book.methodFilter = browseDropdown("method", side, 6, 510, 166)
    book.sortFilter = browseDropdown("sort", frame, 218, 232, 160)
    book.actionFilter = browseDropdown("action", frame, 218, 232, 150)
    book.dateFilter = Widgets.dropdown(book, frame, "Any date", 376, 232, 164, actions.dateMenu)
    book.clearFilters = Widgets.button(book, frame, "Clear filters", 548, 232, 110, 26, actions.clearFilters)
end

local function results(book, actions)
    local api, frame = book.api, book.frame
    book.count = Widgets.text(api, frame, "", 218, 274, 160, 12)
    book.context = Widgets.text(api, frame, "", 390, 274, 268, 11, colors.muted)
    book.context:SetJustifyH("RIGHT")
    book.quantityHeading = Widgets.text(api, frame, "ALL CURRENT", 558, 295, 90, 9, colors.muted)
    book.quantityHeading:SetJustifyH("RIGHT")
    book.empty = Widgets.text(api, frame, "", 248, 408, 380, 14, colors.muted)
    for index = 1, State.PAGE_SIZE do
        local row = itemButton(book, actions, 218, 314 + (index - 1) * 42, 440, 40)
        row.icon = Widgets.icon(row, 8, 4, 32)
        row:GetFontString():ClearAllPoints()
        row:GetFontString():SetPoint("TOPLEFT", 50, -6)
        row:GetFontString():SetWidth(280)
        row.subtitle = Widgets.text(api, row, "", 50, 23, 280, 10, colors.muted)
        row.subtitle:SetWordWrap(false)
        row.quantity = Widgets.text(api, row, "", 340, 13, 90, 13, colors.text)
        row.quantity:SetJustifyH("RIGHT")
        book.rows[index] = row
    end
    for index = 1, State.GALLERY_PAGE_SIZE do
        local x = 218 + ((index - 1) % 2) * 224
        local row = itemButton(book, actions, x, 314 + math.floor((index - 1) / 2) * 98, 216, 90)
        row.icon = Widgets.icon(row, 10, 10, 40)
        row:GetFontString():ClearAllPoints()
        row:GetFontString():SetPoint("TOPLEFT", 60, -12)
        row:GetFontString():SetWidth(146)
        row.subtitle = Widgets.text(api, row, "", 10, 62, 194, 10, colors.muted)
        row.subtitle:SetWordWrap(false)
        row.quantity = Widgets.text(api, row, "", 60, 34, 146, 11, colors.muted)
        row:Hide()
        book.galleryRows[index] = row
    end
    book.previous = Widgets.button(book, frame, "Previous", 218, 621, 94, 30, function()
        actions.turnPage(-1)
    end)
    book.pageLabel = Widgets.text(api, frame, "", 318, 629, 240, 11, colors.muted)
    book.pageLabel:SetJustifyH("CENTER")
    book.next = Widgets.button(book, frame, "Next", 564, 621, 94, 30, function()
        actions.turnPage(1)
    end)
end

local function details(book, actions)
    local api = book.api
    local panel = Widgets.panel(api, book.frame, 680, 100, 400, 552)
    book.detailEmpty =
        Widgets.text(api, panel, "Select an item to explore\nits history.", 32, 234, 336, 15, colors.muted)
    local detailHeader = api.CreateFrame("Frame", nil, panel)
    book.detailHeader = detailHeader
    detailHeader:SetPoint("TOPLEFT")
    detailHeader:SetSize(400, 196)
    book.itemIcon = Widgets.icon(detailHeader, 16, 16, 44)
    book.itemTitle = Widgets.text(api, detailHeader, "", 74, 17, 310, 17)
    book.itemTitle:SetHeight(40)
    book.itemCategory = Widgets.text(api, detailHeader, "", 74, 61, 310, 10, colors.muted)
    book.ownership = Widgets.text(api, detailHeader, "", 26, 92, 348, 11, colors.green)
    book.ownershipDot = Widgets.fill(detailHeader, colors.green, 16, 96, 4, 4, "ARTWORK")
    local itemLink = api.CreateFrame("Button", nil, detailHeader)
    itemLink:SetPoint("TOPLEFT", 16, -12)
    itemLink:SetSize(368, 68)
    itemLink:SetHighlightTexture(Widgets.fill(itemLink, { 1, 0.87, 0.6, 0.04 }, 0, 0, 368, 68, "HIGHLIGHT"))
    itemLink:SetScript("OnClick", function(_, mouseButton)
        Widgets.openLink(api, book.itemLink, mouseButton)
    end)
    tooltip(book, itemLink, function()
        return book.itemLink
    end)
    book.controls[#book.controls + 1] = itemLink
    local function count(label, y)
        Widgets.text(api, detailHeader, label, 18, y, 264, 10, colors.muted)
        local value = Widgets.text(api, detailHeader, "Unknown", 292, y - 1, 88, 12, colors.text)
        value:SetJustifyH("RIGHT")
        return value
    end
    book.characterOverall = count("CHARACTER OVERALL", 116)
    book.allCharactersOverall = count("ALL CHARACTERS OVERALL", 134)
    book.characterCurrent = count("CHARACTER CURRENT", 152)
    book.allCharactersCurrent = count("ALL CHARACTERS CURRENT", 170)
    local scroll = api.CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    book.detailScroll = scroll
    scroll:SetPoint("TOPLEFT", 16, -208)
    scroll:SetSize(344, BookFrame.DETAIL_HEIGHT)
    book.detailBody = api.CreateFrame("Frame", nil, scroll)
    book.detailBody:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    book.detailBody:SetSize(BookFrame.DETAIL_WIDTH, 1)
    scroll:SetScrollChild(book.detailBody)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(
            math.max(0, math.min(book.detailBody:GetHeight() - self:GetHeight(), self:GetVerticalScroll() - delta * 48))
        )
    end)
    book.previewPanel = api.CreateFrame("Frame", nil, panel)
    book.previewPanel:SetPoint("TOPLEFT", 16, -208)
    book.previewPanel:SetSize(368, 76)
    book.savedLink = Widgets.dropdown(book, book.previewPanel, "", 0, 0, 194, actions.savedLinkMenu)
    tooltip(book, book.savedLink, function()
        return book.previewLink
    end)
    book.preview = Widgets.button(book, book.previewPanel, "Preview gear", 202, 0, 166, 32, actions.preview)
    book.previewMessage = Widgets.text(api, book.previewPanel, "", 0, 40, 368, 10, colors.muted)
    book.previewPanel:Hide()
end

local function footer(book, actions)
    local api, frame = book.api, book.frame
    book.loading = Widgets.text(api, frame, "", 218, 656, 440, 10, colors.muted)
    book.loading:SetHeight(22)
    Widgets.button(book, frame, "Review item changes", 20, 680, 150, 18, function()
        actions.change("view", "Evidence")
    end)
    book.warning = Widgets.button(book, frame, "", 180, 680, 490, 18, function()
        actions.change("view", "Evidence")
    end)
    book.warning.nameColor = colors.gold
    book.warning:GetFontString():SetFont(font(api), 10, "")
    Widgets.text(api, frame, "Ctrl+F search  •  Esc close", 680, 669, 210, 10, colors.muted)
    book.shrink = Widgets.button(book, frame, "−", 1004, 662, 32, 24, function()
        actions.resize(-0.1)
    end)
    book.expand = Widgets.button(book, frame, "+", 1044, 662, 32, 24, function()
        actions.resize(0.1)
    end)
    Widgets.text(api, frame, "Window size", 900, 669, 98, 10, colors.muted)
end

local function menu(book, actions)
    local api = book.api
    book.menu = Widgets.panel(api, book.frame, 0, 0, 260, 290, colors.raised)
    book.menuRows = {}
    for index = 1, State.MENU_SIZE do
        local row
        row = Widgets.button(book, book.menu, "", 6, 6 + (index - 1) * 30, 248, 28, function()
            if row.choice then
                actions.choose(row.choice)
            end
        end)
        book.menuRows[index] = row
    end
    book.menuPrevious = Widgets.button(book, book.menu, "Previous", 8, 250, 80, 28, function()
        actions.menuPage(-1)
    end)
    book.menuNext = Widgets.button(book, book.menu, "Next", 172, 250, 80, 28, function()
        actions.menuPage(1)
    end)
    book.menu:EnableMouseWheel(true)
    book.menu:SetScript("OnMouseWheel", function(_, delta)
        actions.menuPage(delta > 0 and -1 or 1)
    end)
    book.menu:Hide()
end

local function scripts(book, actions)
    local api, frame = book.api, book.frame
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(_, key)
        actions.key(key)
    end)
    frame:SetScript("OnUpdate", actions.update)
    frame:SetScript("OnEvent", function(_, event)
        actions.event(event)
    end)
    frame:SetScript("OnHide", actions.hidden)
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    if api.UISpecialFrames then
        table.insert(api.UISpecialFrames, "AzerothLedgerCollection")
    end
end

local function help(book, actions, top, side)
    local api, frame = book.api, book.frame
    Widgets.button(book, top, "Close", 1020, 24, 60, 30, function()
        frame:Hide()
    end)
    book.help = Widgets.panel(api, frame, 218, 146, 440, 500, colors.raised)
    book.help:SetFrameLevel(frame:GetFrameLevel() + 30)
    book.help:EnableMouse(true)
    Widgets.text(api, book.help, "About your Ledger", 18, 18, 400, 20, colors.gold)
    local explanation = Widgets.text(api, book.help, HELP_TEXT, 18, 58, 400, 13)
    explanation:SetHeight(380)
    Widgets.button(book, book.help, "Got it", 18, 444, 130, 32, actions.dismissHelp)
    book.help:Hide()
    Widgets.button(book, top, "Help (F1)", 520, 24, 90, 30, actions.help)
    Widgets.button(book, top, "Settings", 620, 24, 90, 30, actions.settings)
    local function helpButton(parent, x, y, height)
        local control = Widgets.button(book, parent, "?", x, y, 28, height, actions.help)
        local label = control:GetFontString()
        label:ClearAllPoints()
        label:SetPoint("CENTER")
        label:SetWidth(24)
        label:SetJustifyH("CENTER")
        return control
    end
    book.ownershipHelp = helpButton(side, 144, 438, 32)
    helpButton(frame, 566, 290, 20)
end

-- Builds the window and its controls into book. Creation order is also
-- keyboard Tab order. Handlers are looked up when controls are created.
---@param book table holds api; receives widgets
---@param actions table input handlers supplied by Book
function BookFrame.build(book, actions)
    local api = book.api
    local frame = api.CreateFrame("Frame", "AzerothLedgerCollection", api.UIParent)
    book.frame = frame
    book.controls, book.rows, book.galleryRows, book.categories, book.detailRows = {}, {}, {}, {}, {}
    frame:SetSize(State.WIDTH, State.HEIGHT)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    Widgets.fill(frame, colors.canvas, 0, 0, 1100, 700)
    Widgets.fill(frame, colors.gold, 0, 0, 1100, 1, "ARTWORK")
    Widgets.fill(frame, colors.edge, 0, 699, 1100, 1, "ARTWORK")
    Widgets.fill(frame, colors.edge, 0, 0, 1, 700, "ARTWORK")
    Widgets.fill(frame, colors.edge, 1099, 0, 1, 700, "ARTWORK")
    local top = header(book, actions)
    local side = sidebar(book, actions)
    tabs(book, actions)
    search(book, actions)
    filters(book, actions, side)
    results(book, actions)
    details(book, actions)
    footer(book, actions)
    menu(book, actions)
    scripts(book, actions)
    help(book, actions, top, side)
end

addon.BookFrame = BookFrame
