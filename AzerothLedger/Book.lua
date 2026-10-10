local _, addon = ...

local Book = {}
local active
local Widgets = addon.BookWidgets
local colors = Widgets.colors
local PAGE_SIZE = 7
local MENU_SIZE = 8
local DETAIL_HEIGHT = 320
local render
local showMenu
local details

local function pageSize(book)
    return book.filter.view == "Gallery" and 6 or PAGE_SIZE
end

local function visibleRows(book)
    return book.filter.view == "Gallery" and book.galleryRows or book.rows
end

local previewMessages = {
    ready = "Choose a saved link, then preview it in the native dressing room.",
    opened = "Opened the native dressing room.",
    loading = "Item data is not loaded yet. Preview when it becomes available.",
    ["not-wearable"] = "This item cannot be worn in the dressing room. Its saved link is available below.",
    unavailable = "Native preview is unavailable. Its saved link is available below.",
}

local function updatePreview(book)
    local record = book.selected and book.store:find(book.selected)
    local selection =
        addon.Collection.gallerySelection(book.result, book.selected, record and record.links[book.previewIndex or 1])
    local link = selection and selection.link
    book.previewIndex = selection and selection.index or 1
    book.previewLink = link
    book.savedLink:SetText("Saved link " .. (book.previewIndex or 1) .. " of " .. (record and #record.links or 0))
    local status = addon.Client.previewStatus(book.api, link)
    Widgets.enable(book.preview, status == "ready")
    book.previewMessage:SetText(previewMessages[status])
end

local function stamp(at)
    return at and date("%d %b %Y  %H:%M", at) or "Unknown"
end

local function checkedQuantity(quantity, unchecked)
    return quantity == nil and "Unknown" or (tostring(quantity) .. ((unchecked or 0) > 0 and "+" or ""))
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
    row.section = Widgets.fill(row, colors.raised, 0, 12, 338, 32)
    row.link = Widgets.button(book, row, "", 0, 0, 338, 30, function(_, mouseButton)
        if row.action then
            book.showAllLinks = not book.showAllLinks
            details(book, book.selected)
        else
            Widgets.openLink(book.api, row.fullLink, mouseButton)
        end
    end)
    tooltip(book, row.link, function()
        return row.fullLink
    end)
    book.detailRows[index] = row
    return row
end

local function evidenceDetails(book, id)
    local previous, oldScroll = book.selectedEvidence, book.detailScroll:GetVerticalScroll()
    book.selectedEvidence = id
    book.detailHeader:Hide()
    book.previewPanel:Hide()
    local index = book.result.positions[id]
    local item = index and book.result.rows[index]
    book.detailEmpty:SetShown(not item)
    book.detailScroll:SetShown(item ~= nil)
    book.detailScroll:ClearAllPoints()
    book.detailScroll:SetPoint("TOPLEFT", 16, -16)
    book.detailScroll:SetHeight(520)
    for _, row in ipairs(book.detailRows) do
        row:Hide()
    end
    if not item then
        return
    end
    local lines = {
        item.name,
        item.action .. (item.quantity and (" ×" .. item.quantity) or " • quantity unknown"),
        item.character .. "-" .. item.realm,
        stamp(item.at),
        item.status,
        item.reason,
        item.nextStep,
        "Viewing evidence never confirms a gain or changes totals.",
    }
    if item.location then
        lines[#lines + 1] = "Observed location: " .. item.location
    end
    if item.link then
        lines[#lines + 1] = item.link
    end
    local y = 0
    for number, text in ipairs(lines) do
        local row = detailRow(book, number)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", 0, -4)
        row.left:SetWidth(338)
        row.left:SetTextColor(unpack(number == 1 and colors.gold or colors.text))
        row.left:SetText(text)
        row.left:Show()
        row.right:Hide()
        row.line:Hide()
        row.section:Hide()
        row.action = false
        row.fullLink = nil
        row.link:Hide()
        if item.link and number == #lines then
            row.fullLink = item.link
            row.link:SetText(item.link)
            row.link:Show()
            row.left:Hide()
        end
        local height = math.max(34, row.left:GetStringHeight() + 16)
        row:SetHeight(height)
        row:Show()
        y = y + height
    end
    book.detailBody:SetHeight(math.max(1, y))
    book.detailScroll:SetVerticalScroll(previous == id and math.min(oldScroll, math.max(0, y - 520)) or 0)
end

function details(book, key)
    local previous = book.selected
    local oldScroll = book.detailScroll:GetVerticalScroll()
    book.selected = key
    if previous ~= key then
        book.showAllLinks = false
        book.previewIndex = 1
    end
    local scope = {}
    if not book.detailsAccount then
        if book.filter.character or book.filter.realm then
            scope = { character = book.filter.character, realm = book.filter.realm }
        else
            scope = { character = book.character, realm = book.realm }
        end
    end
    local model = key and addon.Collection.inspect(book.store, key, book.character, book.realm, scope)
    book.detailEmpty:SetShown(not model)
    book.detailHeader:SetShown(model ~= nil)
    book.detailScroll:SetShown(model ~= nil)
    local gallery = book.filter.view == "Gallery"
    book.previewPanel:SetShown(gallery and model ~= nil)
    book.detailScroll:ClearAllPoints()
    book.detailScroll:SetPoint("TOPLEFT", 16, gallery and -292 or -208)
    book.detailScroll:SetHeight(gallery and 236 or DETAIL_HEIGHT)
    for _, row in ipairs(book.detailRows) do
        row:Hide()
    end
    if not model then
        book.previewLink = nil
        return
    end
    if previous ~= key then
        Widgets.fade(book, book.detailHeader, 0.35, 0.65)
        Widgets.fade(book, book.detailScroll, 0.35, 0.65)
    end
    local record = model.record
    if gallery then
        updatePreview(book)
    end
    local info = addon.Client.itemMetadata(book.api, record)
    local itemName = record.links[1]:match("%[([^%]]+)%]") or ("Item " .. record.itemID)
    book.itemTitle:SetText(itemName)
    book.itemTitle:SetTextColor(unpack(Widgets.quality(book.api, info.quality)))
    book.itemCategory:SetText(info.category .. "  •  " .. model.scopeLabel)
    Widgets.itemIcon(book.itemIcon, info.icon)
    book.itemLink = record.links[#record.links]
    book.ownership:SetText(model.ownership)
    book.ownership:SetTextColor(unpack(model.ownershipState == "present" and colors.green or colors.gold))
    book.ownershipDot:SetColorTexture(unpack(model.ownershipState == "present" and colors.green or colors.gold))
    book.recorded:SetText(
        book.detailsAccount and tostring(model.breakdown.recorded)
            or checkedQuantity(model.checkedUnits, model.uncheckedAreas)
    )
    book.gained:SetText(tostring(model.breakdown.gained))
    book.initial:SetText(tostring((book.detailsAccount and model.breakdown.initial or model.firstChecked) or "Unknown"))
    book.recordedLabel:SetText(book.detailsAccount and "RECORDED" or "CHECKED UNITS")
    book.initialLabel:SetText(book.detailsAccount and "INITIALLY SEEN" or "FIRST CHECK")
    book.selectedTotals:SetText(book.filter.realm and not book.filter.character and "Realm" or "Character")
    Widgets.select(book.selectedTotals, not book.detailsAccount)
    Widgets.select(book.accountTotals, book.detailsAccount)
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
        row.left:SetFont(book.api.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", kind == "section" and 13 or 12, "")
        row.right:SetTextColor(unpack(colors.muted))
        row.left:SetText(left)
        row.right:SetText(right or "")
        local clickable = kind == "link" or kind == "action"
        row.left:SetShown(not clickable)
        row.right:SetShown(not clickable)
        row.link:SetShown(clickable)
        row.line:SetShown(kind == "section")
        row.section:SetShown(kind == "section")
        row.fullLink = kind == "link" and left or nil
        row.action = kind == "action"
        local height = math.max(24, row.left:GetStringHeight() + 10, row.right:GetStringHeight() + 10)
        if kind == "section" then
            row.left:ClearAllPoints()
            row.left:SetPoint("TOPLEFT", 10, -16)
            row.line:ClearAllPoints()
            row.line:SetPoint("TOPLEFT", 0, -16)
            row.line:SetSize(2, 14)
            row.line:SetColorTexture(unpack(colors.gold))
            row.section:ClearAllPoints()
            row.section:SetPoint("TOPLEFT", 0, -6)
            row.section:SetSize(338, 1)
            row.section:SetColorTexture(unpack(colors.edge))
            height = 40
        end
        if kind == "date" then
            row.left:SetWidth(118)
            row.right:ClearAllPoints()
            row.right:SetPoint("TOPLEFT", 120, -4)
            row.right:SetWidth(218)
            height = math.max(24, row.right:GetStringHeight() + 10)
        end
        if clickable then
            row.link:SetText(left)
            height = 34
        end
        row:SetHeight(height)
        row:Show()
        y = y + height
    end
    if book.filter.view == "Journal" then
        for _, activity in ipairs(book.result.rows) do
            if activity.sequence == book.selectedSequence then
                write("section", activity.action .. " ×" .. activity.quantity)
                write("date", "Confirmed", stamp(activity.at))
                write("note", activity.actors)
                write("note", activity.evidence)
                break
            end
        end
    end
    write("section", "Discovery history")
    if not book.detailsAccount then
        write(
            "note",
            "Latest check "
                .. stamp(model.checkedAt)
                .. ". + means other storage is older or unchecked. First check and gains are separate facts."
        )
    end
    write("date", "First Seen", stamp(model.firstSeen))
    write("date", "Latest Seen", stamp(model.lastSeen))
    write("date", "First known gain", stamp(model.firstGained))
    write("date", "Latest known gain", stamp(model.lastGained))
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
            write("note", book.detailsAccount and "No recorded units." or "No confirmed gains in this scope.")
        end
        for _, name in ipairs(labels) do
            write("pair", name == "Seen" and "Initial stock (Seen)" or name, tostring(totals[name]))
        end
    end
    breakdown("How it was recorded", model.breakdown.methods)
    breakdown("Recorded sources", model.breakdown.sources)
    write("section", "Last observed & current checks")
    local lastCharacter
    local areas = { bags = "Bags", bank = "Bank", equipped = "Equipped" }
    for _, check in ipairs(model.checks) do
        local actor = check.character .. "-" .. check.realm
        if actor ~= lastCharacter then
            write("note", actor .. (not check.online and " • Offline; current ownership unknown" or ""))
            lastCharacter = actor
        end
        write(
            "pair",
            areas[check.area] .. " • Last observed",
            check.observedQuantity ~= nil and tostring(check.observedQuantity) or "Unknown"
        )
        write("date", "Observed", check.observedAt and stamp(check.observedAt) or "Never observed")
        write("pair", "Current check", check.quantity ~= nil and tostring(check.quantity) or "Unknown")
        write("date", "Checked", check.at and stamp(check.at) or "Never checked")
    end
    write("section", "Strongest evidence")
    write("note", model.evidence)
    write("section", "Item links & variant")
    write("note", "Variant " .. record.key)
    write(
        "note",
        #model.links
            .. (#model.links == 1 and " item version" or " item versions")
            .. " • "
            .. #record.links
            .. " recorded links (account)"
    )
    if #model.links > 1 then
        write("note", "Hover links to compare enchants and gems.")
    end
    if book.showAllLinks then
        for _, link in ipairs(record.links) do
            write("link", link)
        end
    else
        for _, group in ipairs(model.links) do
            write("link", group.link)
        end
    end
    if #record.links > #model.links then
        write(
            "action",
            book.showAllLinks and "Show distinct versions" or ("Show all " .. #record.links .. " recorded links")
        )
    end
    book.detailBody:SetHeight(math.max(y, 1))
    book.detailScroll:SetVerticalScroll(
        previous == key and math.min(oldScroll, math.max(0, y - book.detailScroll:GetHeight())) or 0
    )
end

local function selectItem(book, key)
    if book.filter.view == "Evidence" then
        evidenceDetails(book, key)
    else
        details(book, key)
    end
    for _, row in ipairs(visibleRows(book)) do
        Widgets.select(
            row,
            book.filter.view == "Evidence" and row.evidenceID == book.selectedEvidence
                or book.filter.view == "Journal" and row.sequence == book.selectedSequence
                or (book.filter.view ~= "Journal" and book.filter.view ~= "Evidence") and row.key == key
        )
    end
end

local function warning(book)
    local diagnostic = book.store:diagnostic()
    local evidence = book.store:evidenceStatus()
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
    local count = evidence.count
    return count > 0 and (count .. " unresolved records • no guessed gains") or ""
end

local function renderBody(book, requestedKey)
    local scopeKey = (book.filter.realm or "") .. ":" .. (book.filter.character or "")
    if book.lastDetailScope ~= scopeKey then
        book.detailsAccount = not book.filter.character and not book.filter.realm
        book.lastDetailScope = scopeKey
    end
    local journal = book.filter.view == "Journal"
    local evidence = book.filter.view == "Evidence"
    local gallery = book.filter.view == "Gallery"
    local size = pageSize(book)
    local result, pending = book.query:step(book.store, book.character, book.realm, book.filter)
    book.queryPending = pending
    if not result then
        book.empty:SetText(evidence and "Loading unresolved evidence…" or "Loading your Collection…")
        book.empty:Show()
        book.loading:SetText("Loading items…")
        book.count:SetText("Loading…")
        book.discoveries:SetText(book.store:count() .. " discoveries")
        for _, row in ipairs(book.rows) do
            row:Hide()
        end
        for _, row in ipairs(book.galleryRows) do
            row:Hide()
        end
        book.previewPanel:Hide()
        book.detailHeader:Hide()
        book.detailScroll:Hide()
        Widgets.enable(book.previous, false)
        Widgets.enable(book.next, false)
        book.dirty = true
        return
    end
    if journal then
        local selected = result.bySequence and result.bySequence[book.selectedSequence]
        selected = selected or result.rows[(book.page - 1) * size + 1] or result.rows[1]
        book.selectedSequence = selected and selected.sequence or nil
        requestedKey = selected and selected.key or nil
    end
    book.result = result
    local pages = math.max(1, math.ceil(#result.rows / size))
    book.page = math.max(1, math.min(book.page, pages))
    book.count:SetText(
        #result.rows
            .. (
                evidence and " evidence records"
                or journal and " activities"
                or (#result.rows == 1 and " item" or " items")
            )
    )
    book.discoveries:SetText(result.discoveryCount .. (result.discoveryCount == 1 and " discovery" or " discoveries"))
    book.context:SetText(
        evidence and "Unresolved evidence"
            or journal and "Account-wide recent activity"
            or (book.filter.category or (gallery and "Gear & pending items" or "All items"))
    )
    book.quantityHeading:SetShown(not gallery and not evidence)
    book.quantityHeading:SetText(
        journal and "UNITS" or ((book.filter.character or book.filter.realm) and "CHECKED" or "RECORDED")
    )
    for _, control in ipairs({
        book.scope,
        book.realmFilter,
        book.historical,
        book.foundOnce,
        book.clearFilters,
        book.place,
    }) do
        control:SetShown(
            not journal
                and (
                    not evidence
                    or control == book.scope
                    or control == book.realmFilter
                    or control == book.clearFilters
                )
        )
    end
    for _, control in ipairs(book.categories) do
        Widgets.enable(control, not journal and not evidence)
    end
    local state = #result.rows == 0 and "No matching items. Try another search or clear your filters." or ""
    if gallery then
        state = "No matching gear. Try another search or clear your filters."
    end
    if result.discoveryCount == 0 then
        state = "Your collection starts here. Open your bags or bank to record items."
    end
    if journal then
        state = "No retained activity. Retention limits are in AddOns Settings."
    end
    if evidence then
        state = result.total == 0 and "No unresolved evidence in this scope."
            or "No matching evidence. Try another item search or character/realm filter."
        if result.discarded > 0 then
            state = state .. " Discarded details cannot be searched."
        end
    end
    book.empty:SetText(state)
    book.empty:SetShown(#result.rows == 0)
    book.loading:SetText(result.loading > 0 and (result.loading .. " items awaiting item data") or "")
    local warningText = warning(book)
    book.warning:SetText(warningText)
    book.warning:SetShown(warningText ~= "")
    if evidence then
        local discardedRange = stamp(result.firstDiscarded) .. " – " .. stamp(result.lastDiscarded)
        book.loading:SetText(
            result.discarded > 0 and ("Account-wide: " .. result.discarded .. " discarded • " .. discardedRange)
                or "No discarded evidence details."
        )
    end
    book.scope:SetText(book.filter.character or "All characters")
    book.realmFilter:SetText(book.filter.realm or "All realms")
    book.place:SetText(book.filter.place or "All recorded places")
    book.historical.mark:SetShown(book.filter.historical == true)
    book.foundOnce.mark:SetShown(book.filter.foundOnce == true)
    Widgets.select(
        book.collectionTab,
        not evidence and not journal and not gallery and book.filter.view ~= "Discoveries"
    )
    Widgets.select(book.discoveryTab, book.filter.view == "Discoveries")
    Widgets.select(book.journalTab, journal)
    Widgets.select(book.galleryTab, gallery)
    for _, control in ipairs(book.categories) do
        local category = control.category
        Widgets.select(control, book.filter.category == category)
        control.count:SetText(tostring(category and (result.categories[category] or 0) or result.matchedCount))
        control.count:SetTextColor(unpack(control.selected and colors.gold or colors.muted))
    end
    for _, row in ipairs(gallery and book.rows or book.galleryRows) do
        row:Hide()
    end
    for index, row in ipairs(visibleRows(book)) do
        local item = result.rows[(book.page - 1) * size + index]
        row.key = item and item.key or nil
        row.evidenceID = evidence and item and item.id or nil
        row.sequence = journal and item and item.sequence or nil
        row.fullLink = item and (evidence and item.link or (not evidence and item.record.links[#item.record.links]))
            or nil
        row:SetShown(item ~= nil)
        if item then
            row:SetText((journal or evidence) and (item.action .. " • " .. item.name) or item.name)
            row.nameColor = evidence and colors.text or Widgets.quality(book.api, item.metadata.quality)
            row:GetFontString():SetTextColor(unpack(row.nameColor))
            Widgets.itemIcon(row.icon, not evidence and item.metadata.icon or nil)
            row.subtitle:SetText(
                evidence and (item.status .. " • " .. item.character .. "-" .. item.realm)
                    or journal and (stamp(item.at) .. " • " .. item.actors)
                    or (
                        book.filter.view == "Discoveries" and ("First Seen " .. stamp(item.discoveredAt))
                        or (gallery and (item.loading and "Awaiting item data" or item.record.key))
                        or item.category
                    )
            )
            row.quantity:SetText(
                evidence and ""
                    or item.recorded and tostring(item.recorded)
                    or checkedQuantity(item.checkedUnits, item.uncheckedAreas)
            )
        end
    end
    book.pageLabel:SetText(book.page .. " / " .. pages)
    Widgets.enable(book.previous, book.page > 1)
    Widgets.enable(book.next, book.page < pages)
    if book.selected and not book.store:find(book.selected) then
        book.selected = nil
    end
    if evidence then
        local selected = requestedKey or book.selectedEvidence
        if not result.positions[selected] then
            selected = result.rows[(book.page - 1) * size + 1] and result.rows[(book.page - 1) * size + 1].id
        end
        selectItem(book, selected)
    elseif journal then
        book.detailsAccount = true
        selectItem(book, requestedKey)
    else
        if gallery then
            local selection = addon.Collection.gallerySelection(result, requestedKey or book.selected)
            requestedKey = selection and selection.key
            if not requestedKey then
                book.selected = nil
            end
        end
        selectItem(book, requestedKey or book.selected or (result.rows[1] and result.rows[1].key))
    end
    book.dirty = pending
end

render = function(book, requestedKey)
    return addon.Work.measure(book.api, "Book frame", function()
        return renderBody(book, requestedKey)
    end)
end

local function change(book, field, value)
    book.filter[field] = value
    book.page = 1
    book.selectedSequence = nil
    closeMenu(book)
    render(book)
end

local function turnPage(book, delta)
    book.page = book.page + delta
    book.selectedSequence = nil
    book.selectedEvidence = nil
    render(book)
end

local function itemButton(book, x, y, width, height)
    local row
    row = Widgets.button(book, book.frame, "", x, y, width, height, function(_, mouseButton)
        if row.evidenceID or row.key then
            if mouseButton == "RightButton" then
                Widgets.openLink(book.api, row.fullLink, mouseButton)
            else
                book.selectedSequence = row.sequence
                selectItem(book, row.evidenceID or row.key)
            end
        end
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tooltip(book, row, function()
        return row.fullLink
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        turnPage(book, delta > 0 and -1 or 1)
    end)
    return row
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
    Widgets.fade(book, book.menu, 0.25, 0.75)
end

local function scopeMenu(book, anchor, kind)
    if book.queryPending then
        return
    end
    local choices = { { label = kind == "character" and "All characters" or "All realms" } }
    local seen = {}
    for _, actor in ipairs(book.filter.view == "Evidence" and book.result.actors or book.store:characters()) do
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
        if book.queryPending or not book.result then
            return
        end
        if book.menu:IsShown() then
            book.menuIndex = math.max(1, math.min(#book.menuChoices, book.menuIndex + (key == "UP" and -1 or 1)))
            book.menuPage = math.ceil(book.menuIndex / MENU_SIZE)
            renderMenu(book)
            return
        end
        local selected = book.filter.view == "Evidence" and book.selectedEvidence
            or book.filter.view == "Journal" and book.selectedSequence
            or book.selected
        local index = book.result.positions and book.result.positions[selected] or 1
        index = math.max(1, math.min(#book.result.rows, index + (key == "UP" and -1 or 1)))
        local row = book.result.rows[index]
        if row then
            book.selectedSequence = row.sequence
            book.page = math.ceil(index / pageSize(book))
            render(book, book.filter.view == "Evidence" and row.id or row.key)
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
        galleryRows = {},
        categories = {},
        detailRows = {},
        filter = {},
        query = addon.BookQuery.new(api),
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
    Widgets.fill(frame, colors.edge, 0, 0, 1, 700, "ARTWORK")
    Widgets.fill(frame, colors.edge, 1099, 0, 1, 700, "ARTWORK")
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
    Widgets.fill(header, colors.gold, 0, 22, 3, 38, "ARTWORK")
    Widgets.fill(header, colors.raised, 810, 20, 192, 42)
    book.discoveries = Widgets.text(api, header, "", 820, 32, 170, 16, colors.gold)
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
        if book.queryPending or not book.result then
            return
        end
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

    Widgets.fill(frame, colors.edge, 218, 131, 440, 1, "ARTWORK")
    book.collectionTab = Widgets.tab(book, frame, "Collection", 218, 100, 106, function()
        change(book, "view", "Collection")
    end)
    book.discoveryTab = Widgets.tab(book, frame, "Discoveries", 330, 100, 118, function()
        change(book, "view", "Discoveries")
    end)
    book.journalTab = Widgets.tab(book, frame, "Journal", 454, 100, 96, function()
        change(book, "view", "Journal")
    end)
    book.galleryTab = Widgets.tab(book, frame, "Gallery", 556, 100, 102, function()
        change(book, "view", "Gallery")
    end)
    local searchSurface = Widgets.panel(api, frame, 218, 146, 440, 36, colors.raised)
    local searchAccent = Widgets.fill(searchSurface, colors.gold, 0, 35, 440, 1, "ARTWORK")
    searchAccent:Hide()
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
        searchAccent:Show()
        closeMenu(book)
    end)
    book.search:SetScript("OnEditFocusLost", function()
        searchAccent:Hide()
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
    book.clearFilters = Widgets.button(book, frame, "Clear filters", 548, 232, 110, 26, function()
        book.filter = { view = book.filter.view }
        book.search:SetText("")
        book.page = 1
        closeMenu(book)
        render(book)
    end)
    book.count = Widgets.text(api, frame, "", 218, 274, 160, 12)
    book.context = Widgets.text(api, frame, "", 390, 274, 268, 11, colors.muted)
    book.context:SetJustifyH("RIGHT")
    book.quantityHeading = Widgets.text(api, frame, "RECORDED", 598, 295, 60, 9, colors.muted)
    book.quantityHeading:SetJustifyH("RIGHT")
    book.empty = Widgets.text(api, frame, "", 248, 408, 380, 14, colors.muted)
    for index = 1, PAGE_SIZE do
        local row = itemButton(book, 218, 314 + (index - 1) * 42, 440, 40)
        row.icon = Widgets.icon(row, 8, 4, 32)
        row:GetFontString():ClearAllPoints()
        row:GetFontString():SetPoint("TOPLEFT", 50, -6)
        row:GetFontString():SetWidth(320)
        row.subtitle = Widgets.text(api, row, "", 50, 23, 312, 10, colors.muted)
        row.subtitle:SetWordWrap(false)
        row.quantity = Widgets.text(api, row, "", 378, 13, 48, 13, colors.text)
        row.quantity:SetJustifyH("RIGHT")
        book.rows[index] = row
    end
    for index = 1, 6 do
        local row = itemButton(book, 218 + ((index - 1) % 2) * 224, 314 + math.floor((index - 1) / 2) * 98, 216, 90)
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
    book.detailHeader:SetSize(400, 196)
    book.itemIcon = Widgets.icon(book.detailHeader, 16, 16, 44)
    book.itemTitle = Widgets.text(api, book.detailHeader, "", 74, 17, 310, 17)
    book.itemTitle:SetHeight(40)
    book.itemCategory = Widgets.text(api, book.detailHeader, "", 74, 61, 310, 10, colors.muted)
    book.selectedTotals = Widgets.tab(book, book.detailHeader, "Character", 16, 80, 174, function()
        book.detailsAccount = false
        details(book, book.selected)
    end)
    book.accountTotals = Widgets.tab(book, book.detailHeader, "Account", 206, 80, 178, function()
        book.detailsAccount = true
        details(book, book.selected)
    end)
    book.ownership = Widgets.text(api, book.detailHeader, "", 26, 122, 348, 11, colors.green)
    book.ownershipDot = Widgets.fill(book.detailHeader, colors.green, 16, 126, 4, 4, "ARTWORK")
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
        Widgets.fill(book.detailHeader, colors.raised, x, 143, 116, 49)
        Widgets.fill(book.detailHeader, colors.edge, x, 143, 116, 1, "ARTWORK")
        local caption = Widgets.text(api, book.detailHeader, label, x + 10, 151, 96, 9, colors.muted)
        return Widgets.text(api, book.detailHeader, "", x + 10, 168, 96, 18), caption
    end
    book.recorded, book.recordedLabel = statistic("RECORDED", 16)
    book.gained = statistic("TOTAL GAINED", 142)
    book.gained:SetTextColor(unpack(colors.gold))
    book.initial, book.initialLabel = statistic("INITIALLY SEEN", 268)
    book.detailScroll = api.CreateFrame("ScrollFrame", nil, detailPanel, "UIPanelScrollFrameTemplate")
    book.detailScroll:SetPoint("TOPLEFT", 16, -208)
    book.detailScroll:SetSize(344, DETAIL_HEIGHT)
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
    book.previewPanel = api.CreateFrame("Frame", nil, detailPanel)
    book.previewPanel:SetPoint("TOPLEFT", 16, -208)
    book.previewPanel:SetSize(368, 76)
    book.savedLink = Widgets.dropdown(book, book.previewPanel, "", 0, 0, 194, function(self)
        local record = book.selected and book.store:find(book.selected)
        if not record then
            return
        end
        local choices = {}
        for index, link in ipairs(record.links) do
            choices[#choices + 1] = { label = link, index = index }
        end
        showMenu(book, self, choices, function(choice)
            book.previewIndex = choice.index
            closeMenu(book)
            updatePreview(book)
        end)
    end)
    tooltip(book, book.savedLink, function()
        return book.previewLink
    end)
    book.preview = Widgets.button(book, book.previewPanel, "Preview gear", 202, 0, 166, 32, function()
        book.previewMessage:SetText(previewMessages[addon.Client.previewItem(api, book.previewLink)])
    end)
    book.previewMessage = Widgets.text(api, book.previewPanel, "", 0, 40, 368, 10, colors.muted)
    book.previewPanel:Hide()
    book.loading = Widgets.text(api, frame, "", 218, 660, 440, 10, colors.muted)
    Widgets.button(book, frame, "Inspect evidence", 20, 680, 150, 18, function()
        change(book, "view", "Evidence")
    end)
    book.warning = Widgets.button(book, frame, "", 180, 680, 490, 18, function()
        change(book, "view", "Evidence")
    end)
    book.warning.nameColor = colors.gold
    book.warning:GetFontString():SetFont(api.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "")
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
    frame:SetScript("OnEvent", function(_, event)
        if not event or event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
            book.query:metadataChanged()
        end
        book.dirty = true
        fit(book)
    end)
    frame:SetScript("OnHide", function()
        Widgets.stopMotion(book)
        if book.focus then
            book.controls[book.focus]:UnlockHighlight()
            book.focus = nil
        end
        closeMenu(book)
        Widgets.hideTooltip(api)
    end)
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
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
    return addon.Work.measure(api, "Collection open", function()
        if type(api.CreateFrame) ~= "function" then
            return nil
        end
        active = active or create(api)
        active.store, active.character, active.realm = store, character, realm
        active.filter.character, active.filter.realm = filterCharacter, filterRealm
        render(active)
        local opening = not active.opened or not active.frame:IsShown()
        active.frame:Show()
        if opening then
            Widgets.fade(active, active.frame, 0.45, 0.75)
        end
        active.opened = true
        return active.frame
    end)
end

function Book.refresh(store, character, realm)
    if active then
        active.store = store
        active.character, active.realm = character or active.character, realm or active.realm
        active.dirty = true
    end
end

addon.Book = Book
