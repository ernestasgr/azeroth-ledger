local _, addon = ...

local Book = {}
local active
local Widgets = addon.BookWidgets
local colors = Widgets.colors
local PAGE_SIZE = 7
local MENU_SIZE = 8
local render
local showMenu

local function stamp(at)
    return at and date("%d %b %Y  %H:%M", at) or "Unknown"
end

local function fit(book)
    local parent = book.api.UIParent
    local maximum = math.min(1.1, parent:GetWidth() * 0.9 / 1100, parent:GetHeight() * 0.86 / 700)
    local scale = math.min(book.scale, maximum)
    book.frame:SetScale(scale)
    if book.shrink then
        Widgets.enable(book.shrink, scale > 0.601)
    end
    if book.expand then
        Widgets.enable(book.expand, scale < maximum - 0.001)
    end
end

local function closeMenu(book)
    book.menu:Hide()
    book.menuAnchor = nil
end

local function tooltip(book, control, link)
    control:SetScript("OnEnter", function()
        Widgets.tooltip(book.api, control, link())
    end)
    control:SetScript("OnLeave", function()
        Widgets.hideTooltip(book.api)
    end)
end

-- Detail rows are reusable native regions with measured heights, inside a real scroll frame.
local function detailRow(book, index)
    local row = book.detailRows[index]
    if row then
        return row
    end
    row = book.api.CreateFrame("Frame", nil, book.detailBody)
    row:SetWidth(338)
    row.left = Widgets.text(book.api, row, "", 0, 4, 246, 12)
    row.right = Widgets.text(book.api, row, "", 254, 4, 84, 12)
    row.right:SetJustifyH("RIGHT")
    row.line = Widgets.fill(row, colors.edge, 0, 26, 338, 1, "ARTWORK")
    row.link = Widgets.button(book, row, "", 0, 0, 338, 30, function(_, mouseButton)
        Widgets.openLink(book.api, row.fullLink, mouseButton)
    end)
    tooltip(book, row.link, function()
        return row.fullLink
    end)
    book.detailRows[index] = row
    return row
end

local function details(book, key)
    local previous = book.selected
    local oldScroll = book.detailScroll:GetVerticalScroll()
    book.selected = key
    local model = key and addon.Collection.inspect(book.store, key, book.character, book.realm, book.filter)
    book.detailEmpty:SetShown(not model)
    book.detailHeader:SetShown(model ~= nil)
    book.detailScroll:SetShown(model ~= nil)
    for _, row in ipairs(book.detailRows) do
        row:Hide()
    end
    if not model then
        return
    end
    local record = model.record
    local info = addon.Client.itemMetadata(book.api, record)
    local itemName = record.links[1]:match("%[([^%]]+)%]") or ("Item " .. record.itemID)
    book.itemTitle:SetText(itemName)
    book.itemTitle:SetTextColor(unpack(Widgets.quality(book.api, info.quality)))
    book.itemCategory:SetText(info.category .. "  •  Account history")
    book.itemIcon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    book.itemLink = record.links[#record.links]
    book.ownership:SetText(model.ownership)
    book.ownership:SetTextColor(unpack(model.ownership == "Present" and colors.green or colors.gold))
    book.recorded:SetText(tostring(model.breakdown.recorded))
    book.gained:SetText(tostring(record.totalGained))
    book.initial:SetText(tostring(record.firstSeenUnits))
    local index, y = 0, 0
    local function write(kind, left, right)
        index = index + 1
        local row = detailRow(book, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.left:ClearAllPoints()
        row.right:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", 0, -4)
        row.right:SetPoint("TOPLEFT", 254, -4)
        row.left:SetWidth(kind == "note" and 338 or 246)
        row.right:SetWidth(84)
        row.left:SetTextColor(unpack(kind == "section" and colors.gold or colors.text))
        row.right:SetTextColor(unpack(colors.muted))
        row.left:SetText(left)
        row.right:SetText(right or "")
        row.left:SetShown(kind ~= "link")
        row.right:SetShown(kind ~= "link")
        row.link:SetShown(kind == "link")
        row.line:SetShown(kind == "section")
        local height = math.max(24, row.left:GetStringHeight() + 10, row.right:GetStringHeight() + 10)
        if kind == "section" then
            height = 38
        end
        if kind == "date" then
            row.left:SetWidth(118)
            row.right:ClearAllPoints()
            row.right:SetPoint("TOPLEFT", 120, -4)
            row.right:SetWidth(218)
            height = math.max(24, row.right:GetStringHeight() + 10)
        end
        if kind == "link" then
            row.fullLink = left
            row.link:SetText(left)
            height = 34
        end
        row:SetHeight(height)
        row:Show()
        y = y + height
    end
    write("section", "Discovery history")
    write("date", "First Seen", stamp(record.firstSeen))
    write("date", "Latest Seen", stamp(record.lastSeen))
    write("date", "First known gain", stamp(record.firstGained))
    write("date", "Latest known gain", stamp(record.lastGained))
    local function breakdown(title, totals)
        write("section", title)
        local labels = {}
        for name, quantity in pairs(totals) do
            if quantity > 0 then
                labels[#labels + 1] = name
            end
        end
        table.sort(labels)
        if #labels == 0 then
            write("note", "No recorded units.")
        end
        for _, name in ipairs(labels) do
            write("pair", name == "Seen" and "Initial stock (Seen)" or name, tostring(totals[name]))
        end
    end
    breakdown("How it was recorded", model.breakdown.methods)
    breakdown("Recorded sources", model.breakdown.sources)
    write("section", "Last checked")
    local lastCharacter
    local areas = { bags = "Bags", bank = "Bank", equipped = "Equipped" }
    for _, check in ipairs(model.checks) do
        local actor = check.character .. "-" .. check.realm
        if actor ~= lastCharacter then
            write("note", actor .. (not check.online and " • Offline; current ownership unknown" or ""))
            lastCharacter = actor
        end
        write("pair", areas[check.area], check.quantity and tostring(check.quantity) or "Unknown")
        write("date", "Checked", check.at and stamp(check.at) or "Never checked")
    end
    write("section", "Strongest evidence")
    write("note", model.evidence)
    write("section", "Item links & variant")
    write("note", "Variant " .. record.key)
    for _, link in ipairs(record.links) do
        write("link", link)
    end
    book.detailBody:SetHeight(math.max(y, 1))
    book.detailScroll:SetVerticalScroll(previous == key and math.min(oldScroll, math.max(0, y - 352)) or 0)
end

local function selectItem(book, key)
    details(book, key)
    for _, row in ipairs(book.rows) do
        Widgets.select(row, row.key == key)
    end
end

local function warning(book)
    local diagnostic = book.store:diagnostic()
    local evidence = book.store:evidenceSummary()
    if diagnostic.kind ~= "healthy" then
        return "Saved data: " .. diagnostic.kind .. "; readable history shown"
    end
    if evidence.discarded > 0 then
        return "Warning: "
            .. evidence.discarded
            .. " unresolved records discarded • "
            .. date("%d %b %Y", evidence.firstDiscarded)
            .. " – "
            .. date("%d %b %Y", evidence.lastDiscarded)
    end
    local count = #book.store:unresolved()
    return count > 0 and (count .. " unresolved records • no guessed gains") or ""
end

render = function(book, requestedKey)
    local result = addon.Collection.query(book.store, book.character, book.realm, book.filter, function(record)
        return addon.Client.itemMetadata(book.api, record)
    end)
    book.result = result
    local pages = math.max(1, math.ceil(#result.rows / PAGE_SIZE))
    book.page = math.max(1, math.min(book.page, pages))
    book.count:SetText(#result.rows .. (#result.rows == 1 and " item" or " items"))
    book.discoveries:SetText(result.discoveryCount .. (result.discoveryCount == 1 and " discovery" or " discoveries"))
    book.context:SetText(book.filter.category or "All items")
    local state = #result.rows == 0 and "No matching items. Try another search or clear your filters." or ""
    if result.discoveryCount == 0 then
        state = "Your collection starts here. Open your bags or bank to record items."
    end
    book.empty:SetText(state)
    book.empty:SetShown(#result.rows == 0)
    book.loading:SetText(result.loading > 0 and (result.loading .. " items awaiting item data") or "")
    book.warning:SetText(warning(book))
    book.scope:SetText(book.filter.character or "All characters")
    book.realmFilter:SetText(book.filter.realm or "All realms")
    book.place:SetText(book.filter.place or "All recorded places")
    book.historical.mark:SetShown(book.filter.historical == true)
    book.foundOnce.mark:SetShown(book.filter.foundOnce == true)
    Widgets.select(book.collectionTab, book.filter.view ~= "Discoveries")
    Widgets.select(book.discoveryTab, book.filter.view == "Discoveries")
    for _, control in ipairs(book.categories) do
        local category = control.category
        Widgets.select(control, book.filter.category == category)
        control.count:SetText(tostring(category and (result.categories[category] or 0) or result.matchedCount))
    end
    for index, row in ipairs(book.rows) do
        local item = result.rows[(book.page - 1) * PAGE_SIZE + index]
        row.key = item and item.key or nil
        row.fullLink = item and item.record.links[#item.record.links] or nil
        row:SetShown(item ~= nil)
        if item then
            row:SetText(item.name)
            row.nameColor = Widgets.quality(book.api, item.metadata.quality)
            row:GetFontString():SetTextColor(unpack(row.nameColor))
            row.icon:SetTexture(item.metadata.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.subtitle:SetText(
                book.filter.view == "Discoveries" and ("First Seen " .. stamp(item.discoveredAt)) or item.category
            )
            row.quantity:SetText(tostring(item.record.firstSeenUnits + item.record.totalGained))
        end
    end
    book.pageLabel:SetText(book.page .. " / " .. pages)
    Widgets.enable(book.previous, book.page > 1)
    Widgets.enable(book.next, book.page < pages)
    if book.selected and not book.store:find(book.selected) then
        book.selected = nil
    end
    selectItem(book, requestedKey or book.selected or (result.rows[1] and result.rows[1].key))
    book.dirty = false
end

local function change(book, field, value)
    book.filter[field] = value
    book.page = 1
    closeMenu(book)
    render(book)
end

local function turnPage(book, delta)
    book.page = book.page + delta
    render(book)
end

local function renderMenu(book)
    local count = #book.menuChoices
    local pages = math.max(1, math.ceil(count / MENU_SIZE))
    book.menuPage = math.max(1, math.min(book.menuPage, pages))
    local first = (book.menuPage - 1) * MENU_SIZE + 1
    local last = math.min(count, first + MENU_SIZE - 1)
    if book.menuIndex < first or book.menuIndex > last then
        book.menuIndex = first
    end
    for index, row in ipairs(book.menuRows) do
        local choice = book.menuChoices[(book.menuPage - 1) * MENU_SIZE + index]
        row.choice = choice
        row:SetShown(choice ~= nil)
        if choice then
            row:SetText(choice.label)
            Widgets.select(row, (book.menuPage - 1) * MENU_SIZE + index == book.menuIndex)
        end
    end
    local shown = math.min(MENU_SIZE, count - (book.menuPage - 1) * MENU_SIZE)
    book.menu:SetHeight(shown * 30 + 48)
    book.menu.background:SetHeight(book.menu:GetHeight())
    book.menuPrevious:ClearAllPoints()
    book.menuPrevious:SetPoint("TOPLEFT", 8, -(shown * 30 + 10))
    book.menuNext:ClearAllPoints()
    book.menuNext:SetPoint("TOPLEFT", 172, -(shown * 30 + 10))
    Widgets.enable(book.menuPrevious, book.menuPage > 1)
    Widgets.enable(book.menuNext, book.menuPage < pages)
end

showMenu = function(book, anchor, choices, selectChoice)
    if book.menuAnchor == anchor and book.menu:IsShown() then
        closeMenu(book)
        return
    end
    book.menuAnchor, book.menuChoices, book.choose = anchor, choices, selectChoice
    book.menuPage = 1
    book.menuIndex = 1
    book.menu:ClearAllPoints()
    if anchor == book.place then
        book.menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    else
        book.menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    end
    book.menu:SetFrameLevel(book.frame:GetFrameLevel() + 20)
    renderMenu(book)
    book.menu:Show()
end

local function scopeMenu(book, anchor, kind)
    local choices = { { label = kind == "character" and "All characters" or "All realms" } }
    local seen = {}
    for _, actor in ipairs(book.store:characters()) do
        if kind == "character" or not seen[actor.realm] then
            if kind ~= "character" or not book.filter.realm or actor.realm == book.filter.realm then
                choices[#choices + 1] = {
                    label = kind == "character" and (actor.character .. "-" .. actor.realm) or actor.realm,
                    character = kind == "character" and actor.character or nil,
                    realm = actor.realm,
                }
            end
            seen[actor.realm] = true
        end
    end
    showMenu(book, anchor, choices, function(choice)
        if kind == "character" then
            book.filter.character = choice.character
            if choice.character then
                book.filter.realm = choice.realm
            end
        else
            book.filter.realm = choice.realm
            book.filter.character = nil
        end
        book.page = 1
        closeMenu(book)
        render(book)
    end)
end

local function keyboard(book, key)
    local frame = book.frame
    frame:SetPropagateKeyboardInput(false)
    if key == "ESCAPE" then
        if book.menu:IsShown() then
            closeMenu(book)
        elseif book.search:HasFocus() then
            book.search:ClearFocus()
        else
            frame:Hide()
        end
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
        if book.menu:IsShown() then
            local direction = book.api.IsShiftKeyDown and book.api.IsShiftKeyDown() and -1 or 1
            book.menuIndex = (book.menuIndex + direction - 1) % #book.menuChoices + 1
            book.menuPage = math.ceil(book.menuIndex / MENU_SIZE)
            renderMenu(book)
            return
        end
        if book.focus then
            book.controls[book.focus]:UnlockHighlight()
        end
        local direction = book.api.IsShiftKeyDown and book.api.IsShiftKeyDown() and -1 or 1
        local index = book.focus or (direction == 1 and 0 or 1)
        for _ = 1, #book.controls do
            index = (index + direction - 1) % #book.controls + 1
            local control = book.controls[index]
            if control:IsVisible() and control:IsEnabled() then
                break
            end
        end
        book.focus = index
        book.controls[index]:LockHighlight()
        return
    end
    if key == "ENTER" and book.menu:IsShown() then
        book.choose(book.menuChoices[book.menuIndex])
        return
    end
    if key == "ENTER" and book.focus then
        local control = book.controls[book.focus]
        if control:IsVisible() and control:IsEnabled() then
            control:Click()
        end
        return
    end
    if key == "PAGEUP" or key == "PAGEDOWN" then
        local direction = key == "PAGEUP" and -1 or 1
        if book.menu:IsShown() then
            book.menuPage = book.menuPage + direction
            renderMenu(book)
        else
            turnPage(book, direction)
        end
        return
    end
    if key == "UP" or key == "DOWN" then
        if book.menu:IsShown() then
            book.menuIndex = math.max(1, math.min(#book.menuChoices, book.menuIndex + (key == "UP" and -1 or 1)))
            book.menuPage = math.ceil(book.menuIndex / MENU_SIZE)
            renderMenu(book)
            return
        end
        local index = 1
        for position, row in ipairs(book.result.rows) do
            if row.key == book.selected then
                index = position
            end
        end
        index = math.max(1, math.min(#book.result.rows, index + (key == "UP" and -1 or 1)))
        local row = book.result.rows[index]
        if row then
            book.page = math.ceil(index / PAGE_SIZE)
            render(book, row.key)
        end
        return
    end
    frame:SetPropagateKeyboardInput(true)
end

local function create(api)
    local frame = api.CreateFrame("Frame", "AzerothLedgerCollection", api.UIParent)
    local book = {
        api = api,
        frame = frame,
        controls = {},
        rows = {},
        categories = {},
        detailRows = {},
        filter = {},
        page = 1,
        scale = 1,
    }
    frame:SetSize(1100, 700)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    Widgets.fill(frame, colors.canvas, 0, 0, 1100, 700)
    Widgets.fill(frame, colors.gold, 0, 0, 1100, 1, "ARTWORK")
    Widgets.fill(frame, colors.edge, 0, 699, 1100, 1, "ARTWORK")
    local header = Widgets.panel(api, frame, 0, 0, 1100, 82, colors.panel)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    local emblem = Widgets.icon(header, 24, 24, 32)
    emblem:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    Widgets.text(api, header, "Azeroth Ledger", 70, 20, 420, 24, colors.gold)
    Widgets.text(api, header, "Your account's item collection", 72, 51, 420, 12, colors.muted)
    book.discoveries = Widgets.text(api, header, "", 700, 27, 300, 18)
    book.discoveries:SetJustifyH("RIGHT")

    local sidebar = Widgets.panel(api, frame, 20, 100, 178, 552)
    Widgets.text(api, sidebar, "CATEGORIES", 12, 16, 154, 10, colors.muted)
    local categories =
        { "All items", "Weapons", "Armour", "Recipes", "Materials", "Consumables", "Junk", "Other", "Unknown" }
    for index, category in ipairs(categories) do
        local selectedCategory = category ~= "All items" and category or nil
        local control = Widgets.button(book, sidebar, category, 0, 42 + (index - 1) * 34, 178, 32, function()
            change(book, "category", selectedCategory)
        end)
        control.category = selectedCategory
        control:GetFontString():SetWidth(122)
        control.count = Widgets.text(api, control, "", 136, 10, 30, 11, colors.muted)
        control.count:SetJustifyH("RIGHT")
        book.categories[index] = control
    end
    Widgets.fill(sidebar, colors.edge, 12, 366, 154, 1, "ARTWORK")
    Widgets.text(api, sidebar, "RECORDED PLACES", 12, 389, 154, 10, colors.muted)
    book.place = Widgets.dropdown(book, sidebar, "All recorded places", 6, 418, 166, function(self)
        local choices = { { label = "All recorded places" } }
        local kinds = { zone = "Zone", dungeon = "Dungeon", place = "Place" }
        for _, place in ipairs(book.result.places) do
            choices[#choices + 1] =
                { label = kinds[place.kind] .. ": " .. place.name, place = place.name, kind = place.kind }
        end
        showMenu(book, self, choices, function(choice)
            book.filter.placeKind = choice.kind
            change(book, "place", choice.place)
        end)
    end)
    Widgets.text(api, sidebar, "Only places linked to\nrecorded gains appear here.", 12, 467, 154, 11, colors.muted)

    book.collectionTab = Widgets.button(book, frame, "Collection", 218, 100, 128, 32, function()
        change(book, "view", "Collection")
    end)
    book.discoveryTab = Widgets.button(book, frame, "Discoveries", 354, 100, 150, 32, function()
        change(book, "view", "Discoveries")
    end)
    local searchSurface = Widgets.panel(api, frame, 218, 146, 440, 36, colors.raised)
    book.search = api.CreateFrame("EditBox", nil, searchSurface)
    book.search:SetPoint("TOPLEFT", 12, -2)
    book.search:SetSize(410, 32)
    book.search:SetFont(api.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
    book.search:SetTextColor(unpack(colors.text))
    book.search:SetAutoFocus(false)
    book.search:SetMaxLetters(160)
    book.placeholder = Widgets.text(api, searchSurface, "Search your collection…", 12, 12, 400, 12, colors.muted)
    book.search:SetScript("OnTextChanged", function(self)
        book.filter.search = self:GetText()
        book.page = 1
        book.dirty = true
        book.placeholder:SetShown(self:GetText() == "")
    end)
    book.search:SetScript("OnEditFocusGained", function()
        book.placeholder:Hide()
        closeMenu(book)
    end)
    book.search:SetScript("OnEditFocusLost", function()
        book.placeholder:SetShown(book.search:GetText() == "")
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
        if book.focus then
            book.controls[book.focus]:UnlockHighlight()
        end
        for index, control in ipairs(book.controls) do
            if control == book.scope then
                book.focus = index
                control:LockHighlight()
                break
            end
        end
    end)
    book.scope = Widgets.dropdown(book, frame, "All characters", 218, 194, 216, function(self)
        scopeMenu(book, self, "character")
    end)
    book.realmFilter = Widgets.dropdown(book, frame, "All realms", 442, 194, 216, function(self)
        scopeMenu(book, self, "realm")
    end)
    book.historical = Widgets.checkbox(book, frame, "Historical only", 218, 232, 160, function()
        change(book, "historical", not book.filter.historical)
    end)
    book.foundOnce = Widgets.checkbox(book, frame, "Found once", 384, 232, 150, function()
        change(book, "foundOnce", not book.filter.foundOnce)
    end)
    Widgets.button(book, frame, "Clear filters", 548, 232, 110, 26, function()
        book.filter = {}
        book.search:SetText("")
        book.page = 1
        closeMenu(book)
        render(book)
    end)
    book.count = Widgets.text(api, frame, "", 218, 274, 160, 12)
    book.context = Widgets.text(api, frame, "", 390, 274, 268, 11, colors.muted)
    book.context:SetJustifyH("RIGHT")
    Widgets.text(api, frame, "RECORDED", 598, 295, 60, 9, colors.muted):SetJustifyH("RIGHT")
    book.empty = Widgets.text(api, frame, "", 248, 408, 380, 14, colors.muted)
    for index = 1, PAGE_SIZE do
        local row
        row = Widgets.button(book, frame, "", 218, 314 + (index - 1) * 42, 440, 40, function(_, mouseButton)
            if row.key then
                if mouseButton == "RightButton" then
                    Widgets.openLink(api, row.fullLink, mouseButton)
                else
                    selectItem(book, row.key)
                end
            end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.icon = Widgets.icon(row, 8, 4, 32)
        row:GetFontString():ClearAllPoints()
        row:GetFontString():SetPoint("TOPLEFT", 50, -6)
        row:GetFontString():SetWidth(320)
        row.subtitle = Widgets.text(api, row, "", 50, 23, 320, 10, colors.muted)
        row.quantity = Widgets.text(api, row, "", 378, 13, 48, 13, colors.muted)
        row.quantity:SetJustifyH("RIGHT")
        tooltip(book, row, function()
            return row.fullLink
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            turnPage(book, delta > 0 and -1 or 1)
        end)
        book.rows[index] = row
    end
    book.previous = Widgets.button(book, frame, "Previous", 218, 621, 94, 30, function()
        turnPage(book, -1)
    end)
    book.pageLabel = Widgets.text(api, frame, "", 318, 629, 240, 11, colors.muted)
    book.pageLabel:SetJustifyH("CENTER")
    book.next = Widgets.button(book, frame, "Next", 564, 621, 94, 30, function()
        turnPage(book, 1)
    end)

    local detailPanel = Widgets.panel(api, frame, 680, 100, 400, 552)
    book.detailEmpty =
        Widgets.text(api, detailPanel, "Select an item to explore\nits history.", 32, 234, 336, 15, colors.muted)
    book.detailHeader = api.CreateFrame("Frame", nil, detailPanel)
    book.detailHeader:SetPoint("TOPLEFT")
    book.detailHeader:SetSize(400, 164)
    book.itemIcon = Widgets.icon(book.detailHeader, 16, 16, 44)
    book.itemTitle = Widgets.text(api, book.detailHeader, "", 74, 17, 310, 17)
    book.itemTitle:SetHeight(40)
    book.itemCategory = Widgets.text(api, book.detailHeader, "", 74, 61, 310, 10, colors.muted)
    book.ownership = Widgets.text(api, book.detailHeader, "", 16, 84, 368, 11, colors.green)
    local itemLink = api.CreateFrame("Button", nil, book.detailHeader)
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
    local function statistic(label, x)
        Widgets.fill(book.detailHeader, colors.raised, x, 111, 116, 49)
        Widgets.text(api, book.detailHeader, label, x + 10, 119, 96, 9, colors.muted)
        return Widgets.text(api, book.detailHeader, "", x + 10, 136, 96, 18)
    end
    book.recorded = statistic("RECORDED", 16)
    book.gained = statistic("TOTAL GAINED", 142)
    book.initial = statistic("INITIALLY SEEN", 268)
    book.detailScroll = api.CreateFrame("ScrollFrame", nil, detailPanel, "UIPanelScrollFrameTemplate")
    book.detailScroll:SetPoint("TOPLEFT", 16, -176)
    book.detailScroll:SetSize(344, 352)
    book.detailBody = api.CreateFrame("Frame", nil, book.detailScroll)
    book.detailBody:SetPoint("TOPLEFT", book.detailScroll, "TOPLEFT", 0, 0)
    book.detailBody:SetSize(338, 1)
    book.detailScroll:SetScrollChild(book.detailBody)
    book.detailScroll:EnableMouseWheel(true)
    book.detailScroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(
            math.max(0, math.min(book.detailBody:GetHeight() - self:GetHeight(), self:GetVerticalScroll() - delta * 48))
        )
    end)
    book.loading = Widgets.text(api, frame, "", 218, 660, 440, 10, colors.muted)
    book.warning = Widgets.text(api, frame, "", 20, 681, 700, 10, colors.gold)
    Widgets.text(api, frame, "Ctrl+F search  •  Esc close", 680, 669, 210, 10, colors.muted)
    book.shrink = Widgets.button(book, frame, "−", 1004, 662, 32, 24, function()
        book.scale = math.max(0.6, book.frame:GetScale() - 0.1)
        fit(book)
    end)
    book.expand = Widgets.button(book, frame, "+", 1044, 662, 32, 24, function()
        book.scale = math.min(1.1, book.frame:GetScale() + 0.1)
        fit(book)
    end)
    Widgets.text(api, frame, "Window size", 900, 669, 98, 10, colors.muted)

    book.menu = Widgets.panel(api, frame, 0, 0, 260, 290, colors.raised)
    book.menuRows = {}
    for index = 1, MENU_SIZE do
        local row
        row = Widgets.button(book, book.menu, "", 6, 6 + (index - 1) * 30, 248, 28, function()
            if row.choice then
                book.choose(row.choice)
            end
        end)
        book.menuRows[index] = row
    end
    book.menuPrevious = Widgets.button(book, book.menu, "Previous", 8, 250, 80, 28, function()
        book.menuPage = book.menuPage - 1
        renderMenu(book)
    end)
    book.menuNext = Widgets.button(book, book.menu, "Next", 172, 250, 80, 28, function()
        book.menuPage = book.menuPage + 1
        renderMenu(book)
    end)
    book.menu:EnableMouseWheel(true)
    book.menu:SetScript("OnMouseWheel", function(_, delta)
        book.menuPage = book.menuPage + (delta > 0 and -1 or 1)
        renderMenu(book)
    end)
    book.menu:Hide()
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
    frame:SetScript("OnHide", function()
        if book.focus then
            book.controls[book.focus]:UnlockHighlight()
            book.focus = nil
        end
        closeMenu(book)
        Widgets.hideTooltip(api)
    end)
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    if api.UISpecialFrames then
        table.insert(api.UISpecialFrames, "AzerothLedgerCollection")
    end
    Widgets.button(book, header, "Close", 1020, 24, 60, 30, function()
        frame:Hide()
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
