local _, addon = ...

-- Builds the Collection window's detail panel: the item header, the counts
-- grid, reusable detail rows, and the slim scrollbar beside them.
local BookFrame = addon.BookFrame
local Widgets = addon.BookWidgets
local colors = Widgets.colors
local font, tooltip = BookFrame.font, BookFrame.tooltip

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

-- Sizes the slim thumb to the visible share of the details; hidden when they fit.
function BookFrame.updateScrollbar(book)
    local scroll, track = book.detailScroll, book.detailTrack
    local visible, content = scroll:GetHeight(), book.detailBody:GetHeight()
    local range = content - visible
    track:SetHeight(visible)
    track:SetShown(scroll:IsShown() and range > 1)
    if range <= 1 then
        return
    end
    local thumbHeight = math.max(24, visible * visible / content)
    track.thumb:SetHeight(thumbHeight)
    track.thumb:ClearAllPoints()
    track.thumb:SetPoint("TOPLEFT", 0, -(visible - thumbHeight) * scroll:GetVerticalScroll() / range)
end

function BookFrame.scrollDetails(book, offset)
    local range = book.detailBody:GetHeight() - book.detailScroll:GetHeight()
    book.detailScroll:SetVerticalScroll(math.max(0, math.min(range, offset)))
    BookFrame.updateScrollbar(book)
end

-- Positions the detail scroll area for the current view.
function BookFrame.detailArea(book, top, height)
    book.detailScroll:ClearAllPoints()
    book.detailScroll:SetPoint("TOPLEFT", 16, -top)
    book.detailScroll:SetHeight(height)
    BookFrame.updateScrollbar(book)
end

-- Restores scroll for the same selection, and starts a new selection at the top.
function BookFrame.finishDetails(book, height, keepScroll, oldScroll)
    book.detailBody:SetHeight(math.max(1, height))
    BookFrame.scrollDetails(book, keepScroll and oldScroll or 0)
end

-- A thin track beside the details replaces the template's arrow buttons.
-- The thumb drags; the wheel works anywhere over the details.
local function scrollbar(book, panel)
    local api, scroll = book.api, book.detailScroll
    local track = api.CreateFrame("Frame", nil, panel)
    book.detailTrack = track
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 12, 0)
    track:SetWidth(6)
    local groove = track:CreateTexture(nil, "BACKGROUND")
    groove:SetAllPoints()
    Widgets.tint(groove, colors.edge, true)
    local thumb = api.CreateFrame("Button", nil, track)
    track.thumb = thumb
    thumb:SetWidth(6)
    local fill = thumb:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    Widgets.tint(fill, colors.muted, true)
    local hover = thumb:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    Widgets.tint(hover, colors.gold, true)
    thumb:SetHighlightTexture(hover)
    local grabY, grabScroll
    local function drag()
        local _, cursorY = api.GetCursorPosition()
        local visible = scroll:GetHeight()
        local travel = visible - thumb:GetHeight()
        if travel > 0 then
            local range = book.detailBody:GetHeight() - visible
            local moved = grabY - cursorY / thumb:GetEffectiveScale()
            BookFrame.scrollDetails(book, grabScroll + moved * range / travel)
        end
    end
    thumb:SetScript("OnMouseDown", function()
        local _, cursorY = api.GetCursorPosition()
        grabY, grabScroll = cursorY / thumb:GetEffectiveScale(), scroll:GetVerticalScroll()
        thumb:SetScript("OnUpdate", drag)
    end)
    thumb:SetScript("OnMouseUp", function()
        thumb:SetScript("OnUpdate", nil)
    end)
    thumb:SetScript("OnHide", function()
        thumb:SetScript("OnUpdate", nil)
    end)
    scroll:SetScript("OnShow", function()
        BookFrame.updateScrollbar(book)
    end)
    scroll:SetScript("OnHide", function()
        track:Hide()
    end)
    track:Hide()
end

function BookFrame.details(book, actions)
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
    -- The four counts read as a grid: what was found versus what is held now,
    -- for the selected character and for every character.
    Widgets.fill(detailHeader, colors.raised, 10, 108, 380, 80)
    Widgets.fill(detailHeader, colors.edge, 20, 135, 360, 1, "ARTWORK")
    local columns = { { x = 170, width = 90 }, { x = 270, width = 110 } }
    for index, heading in ipairs({ "CHARACTER", "ALL CHARACTERS" }) do
        local column = columns[index]
        Widgets.text(api, detailHeader, heading, column.x, 117, column.width, 9, colors.muted):SetJustifyH("RIGHT")
    end
    local function count(label, y)
        Widgets.text(api, detailHeader, label, 20, y + 1, 150, 12, colors.muted)
        local values = {}
        for index, column in ipairs(columns) do
            values[index] = Widgets.text(api, detailHeader, "Unknown", column.x, y, column.width, 14, colors.text)
            values[index]:SetJustifyH("RIGHT")
        end
        return values[1], values[2]
    end
    book.characterOverall, book.allCharactersOverall = count("Total found", 142)
    book.characterCurrent, book.allCharactersCurrent = count("Current count", 164)
    local scroll = api.CreateFrame("ScrollFrame", nil, panel)
    book.detailScroll = scroll
    scroll:SetPoint("TOPLEFT", 16, -208)
    scroll:SetSize(344, BookFrame.DETAIL_HEIGHT)
    book.detailBody = api.CreateFrame("Frame", nil, scroll)
    book.detailBody:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    book.detailBody:SetSize(BookFrame.DETAIL_WIDTH, 1)
    scroll:SetScrollChild(book.detailBody)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        BookFrame.scrollDetails(book, self:GetVerticalScroll() - delta * 48)
    end)
    scrollbar(book, panel)
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
