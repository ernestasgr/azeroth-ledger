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
    .. "Total found counts a character's units from its first check plus confirmed gains, after refunds. "
    .. "It shows Unknown if saved history cannot separate a confirmed gain from the first check.\n\n"
    .. "Current count adds the latest saved bags, bank, and equipped quantities, "
    .. "including offline characters. Checks can be from different times, "
    .. "and areas with no saved check add nothing.\n"
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

-- The detail panel (BookDetailFrame.lua) shares these helpers.
BookFrame.font, BookFrame.tooltip = font, tooltip

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
    Widgets.fill(panel, colors.raised, 580, 20, 192, 42)
    book.discoveries = Widgets.text(api, panel, "", 590, 32, 170, 16, colors.gold)
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
    -- Below the 32px tabs, not under them: tab backgrounds would cover all but the gaps.
    Widgets.fill(frame, colors.edge, 218, 132, 440, 1, "ARTWORK")
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
    book.quantityHeading = Widgets.text(api, frame, "ALL CURRENT", 568, 295, 80, 9, colors.muted)
    book.quantityHeading:SetJustifyH("RIGHT")
    book.quantityHeading:SetWordWrap(false)
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

local function footer(book, actions)
    local api, frame = book.api, book.frame
    book.loading = Widgets.text(api, frame, "", 218, 656, 440, 10, colors.muted)
    book.loading:SetHeight(22)
    Widgets.button(book, frame, "Review item changes", 20, 680, 190, 18, function()
        actions.change("view", "Evidence")
    end)
    book.warning = Widgets.button(book, frame, "", 220, 680, 450, 18, function()
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
    local function centered(control)
        local label = control:GetFontString()
        label:ClearAllPoints()
        label:SetPoint("CENTER")
        label:SetWidth(control:GetWidth() - 4)
        label:SetJustifyH("CENTER")
        return control
    end
    -- Header actions share one bordered cluster so they read as buttons, not captions.
    centered(Widgets.button(book, top, "Close", 1000, 24, 80, 34, function()
        frame:Hide()
    end, true))
    book.help = Widgets.panel(api, frame, 218, 146, 440, 500, colors.raised)
    book.help:SetFrameLevel(frame:GetFrameLevel() + 30)
    book.help:EnableMouse(true)
    Widgets.text(api, book.help, "About your Ledger", 18, 18, 400, 20, colors.gold)
    local explanation = Widgets.text(api, book.help, HELP_TEXT, 18, 58, 400, 13)
    explanation:SetHeight(380)
    Widgets.button(book, book.help, "Got it", 18, 444, 130, 32, actions.dismissHelp)
    book.help:Hide()
    centered(Widgets.button(book, top, "Help (F1)", 788, 24, 100, 34, actions.help, true))
    centered(Widgets.button(book, top, "Settings", 892, 24, 100, 34, actions.settings, true))
    local function helpButton(parent, x, y, height)
        return centered(Widgets.button(book, parent, "?", x, y, 28, height, actions.help, true))
    end
    book.ownershipHelp = helpButton(side, 144, 438, 32)
    helpButton(frame, 536, 290, 20)
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
    -- MEDIUM would let the unit frames and action bars draw over the window.
    frame:SetFrameStrata("HIGH")
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
    BookFrame.details(book, actions)
    footer(book, actions)
    menu(book, actions)
    scripts(book, actions)
    help(book, actions, top, side)
end

addon.BookFrame = BookFrame
