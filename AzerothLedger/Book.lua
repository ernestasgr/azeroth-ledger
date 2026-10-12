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
local openHistory

local browseChoices = addon.Schema.bookChoices()

local function choiceLabel(field, value)
    for _, choice in ipairs(browseChoices[field]) do
        if choice.value == value then
            return choice.label
        end
    end
    return browseChoices[field][1].label
end

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
    local record = book.selected and book.store:describe(book.selected)
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

local function exactQuantity(quantity)
    return quantity == nil and "Unknown" or tostring(quantity)
end

local function save(book)
    if book.store then
        book.store:setBook({
            version = 1,
            scale = book.scale,
            x = book.x or 0,
            y = book.y or 0,
            filter = book.filter,
            guided = book.guided,
            developerMode = book.developerMode,
        })
    end
end

local function fit(book)
    local parent = book.api.UIParent
    local maximum = math.min(1.1, parent:GetWidth() * 0.9 / 1100, parent:GetHeight() * 0.86 / 700)
    local scale = math.min(book.scale, maximum)
    book.frame:SetScale(scale)
    local maxX = math.max(0, (parent:GetWidth() - 1100 * scale) / 2)
    local maxY = math.max(0, (parent:GetHeight() - 700 * scale) / 2)
    book.x = math.max(-maxX, math.min(maxX, book.x or 0))
    book.y = math.max(-maxY, math.min(maxY, book.y or 0))
    book.frame:ClearAllPoints()
    book.frame:SetPoint("CENTER", parent, "CENTER", book.x / scale, book.y / scale)
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
        if row.onClick then
            row.onClick()
        else
            Widgets.openLink(book.api, row.fullLink, mouseButton)
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
        "Looking here will not confirm a gain or change your totals.",
    }
    if item.location then
        lines[#lines + 1] = "Where seen: " .. item.location
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
        Widgets.tint(row.left, number == 1 and colors.gold or colors.text)
        row.left:SetText(text)
        row.left:Show()
        row.right:Hide()
        row.line:Hide()
        row.section:Hide()
        row.action = false
        row.onClick = nil
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
        book.previewIndex = 1
    end
    local scope = { character = book.filter.character, realm = book.filter.realm }
    local model, pending = book.query:inspect(book.store, key, book.character, book.realm, scope)
    local developerMode = book.developerMode == true
    book.detailPending = pending
    book.detailEmpty:SetText(pending and "Loading item details…" or "Select an item to explore\nits history.")
    if pending then
        book.dirty = true
    end
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
    Widgets.tint(book.itemTitle, Widgets.quality(book.api, info.quality))
    book.itemCategory:SetText(info.category .. "  •  " .. model.scopeLabel)
    Widgets.itemIcon(book.itemIcon, info.icon)
    book.itemLink = record.links[#record.links]
    book.ownership:SetText("Status: " .. model.ownership)
    Widgets.tint(book.ownership, model.ownershipState == "present" and colors.green or colors.gold)
    Widgets.tint(book.ownershipDot, model.ownershipState == "present" and colors.green or colors.gold, true)
    book.characterOverall:SetText(exactQuantity(model.characterOverall))
    book.allCharactersOverall:SetText(exactQuantity(model.allCharactersOverall))
    book.characterCurrent:SetText(exactQuantity(model.characterCurrent))
    book.allCharactersCurrent:SetText(exactQuantity(model.allCharactersCurrent))
    local index, y = 0, 0
    local detailItem = book.filter.view == "Journal" and book.selectedSequence or key
    local detailIdentity = tostring(book.filter.view) .. "\031" .. tostring(detailItem)
    if book.collapsedContext ~= detailIdentity then
        book.collapsedContext = detailIdentity
        book.collapsedSections = {}
    end
    book.collapsedSections = book.collapsedSections or {}
    local sectionIndex, activeSectionKey, activeSectionCollapsed = 0, nil, false
    local function write(kind, left, right, onClick)
        index = index + 1
        if kind == "section" then
            sectionIndex = sectionIndex + 1
            activeSectionKey = sectionIndex
            activeSectionCollapsed = book.collapsedSections[activeSectionKey] == true
        end
        local row = detailRow(book, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.left:ClearAllPoints()
        row.right:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", 0, -4)
        row.right:SetPoint("TOPLEFT", 254, -4)
        row.left:SetWidth(kind == "note" and 338 or 246)
        row.right:SetWidth(84)
        Widgets.tint(row.left, kind == "section" and colors.gold or colors.text)
        row.left:SetFont(book.api.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", kind == "section" and 13 or 12, "")
        Widgets.tint(row.right, colors.muted)
        row.left:SetText(left)
        row.right:SetText(right or "")
        row.link:ClearAllPoints()
        row.link:SetPoint("TOPLEFT", 0, 0)
        row.link:SetSize(338, 30)
        row.link.background:Show()
        local linkText = row.link:GetFontString()
        linkText:ClearAllPoints()
        linkText:SetPoint("TOPLEFT", 12, -8.5)
        linkText:SetWidth(314)
        linkText:SetFont(book.api.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
        Widgets.tint(linkText, colors.text)
        local clickable = kind == "link" or kind == "action" or kind == "section"
        row.left:SetShown(not clickable)
        row.right:SetShown(not clickable)
        row.link:SetShown(clickable)
        row.line:SetShown(kind == "section")
        row.section:SetShown(kind == "section")
        row.fullLink = kind == "link" and left or nil
        row.disclosureIcon:Hide()
        if kind == "section" then
            local sectionKey = assert(activeSectionKey)
            row.onClick = function()
                book.collapsedSections[sectionKey] = not book.collapsedSections[sectionKey]
                details(book, key)
            end
            row.link:SetText(left)
            row.link:SetSize(338, 40)
            row.link.background:Hide()
            linkText:ClearAllPoints()
            linkText:SetPoint("TOPLEFT", 28, -14)
            linkText:SetWidth(300)
            linkText:SetFont(book.api.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "")
            Widgets.tint(linkText, colors.gold)
            row.disclosureIcon:SetTexture(
                activeSectionCollapsed and "Interface\\Buttons\\UI-PlusButton-UP"
                    or "Interface\\Buttons\\UI-MinusButton-UP"
            )
            row.disclosureIcon:Show()
        else
            row.onClick = onClick
            row.link:SetText(left)
        end
        local height = math.max(24, row.left:GetStringHeight() + 10, row.right:GetStringHeight() + 10)
        if kind == "section" then
            row.line:ClearAllPoints()
            row.line:SetPoint("TOPLEFT", 0, -16)
            row.line:SetSize(2, 14)
            Widgets.tint(row.line, colors.gold, true)
            row.section:ClearAllPoints()
            row.section:SetPoint("TOPLEFT", 0, -6)
            row.section:SetSize(338, 1)
            Widgets.tint(row.section, colors.edge, true)
            height = 40
        elseif activeSectionCollapsed then
            row.left:Hide()
            row.right:Hide()
            row.link:Hide()
            row.line:Hide()
            row.section:Hide()
            row:SetHeight(1)
            row:Hide()
            return
        end
        if kind == "date" then
            row.left:SetWidth(118)
            row.right:ClearAllPoints()
            row.right:SetPoint("TOPLEFT", 120, -4)
            row.right:SetWidth(218)
            height = math.max(24, row.right:GetStringHeight() + 10)
        end
        if kind == "link" or kind == "action" then
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
                write("date", "When", stamp(activity.at))
                write("note", activity.actors)
                if developerMode then
                    write("note", "Recording details: " .. activity.evidence)
                end
                if activity.kind == "transfer" then
                    write("note", "Moved between your characters. This does not count as a new gain.")
                end
                if activity.details then
                    for _, gain in ipairs(activity.details) do
                        write("section", gain.method .. " ×" .. gain.quantity)
                        write("note", gain.actor)
                        write("date", "Time", stamp(gain.at))
                        write("note", "Place: " .. gain.place)
                        write("pair", "Character level", tostring(gain.level or "Unknown"))
                        write("note", "Source: " .. gain.source)
                    end
                    if activity.action == "Purchase" or activity.refunded > 0 then
                        write(
                            "note",
                            "Purchased "
                                .. activity.quantity
                                .. "; refunded "
                                .. activity.refunded
                                .. "; net gained "
                                .. activity.netQuantity
                                .. "."
                        )
                    end
                else
                    write("note", "Place: " .. activity.placeText)
                    write("pair", "Character level", tostring(activity.level or "Unknown"))
                    write("note", "Action: " .. activity.action)
                    write("note", "From: " .. activity.sourceText)
                end
                local function related(sequence, label)
                    local retained = sequence and book.result.bySequence[sequence]
                    if retained then
                        write("action", label .. " • " .. stamp(retained.at), nil, function()
                            book.selectedSequence = sequence
                            book.page = math.ceil(book.result.positions[sequence] / PAGE_SIZE)
                            render(book)
                        end)
                    else
                        write("note", label .. " is not in the recent Journal entries.")
                    end
                end
                if activity.kind == "refund" then
                    if activity.linkedGainID then
                        related(activity.purchaseSequence, "Linked purchase")
                    else
                        write("note", "The matching purchase is not in the Journal.")
                    end
                elseif activity.kind == "buyback" then
                    if activity.linkedSaleID then
                        related(activity.saleSequence, "Linked sale")
                    else
                        write("note", "The matching sale is not in the Journal.")
                    end
                end
                for _, sequence in ipairs(activity.refundSequences or {}) do
                    related(sequence, "Linked refund")
                end
                break
            end
        end
    end
    if book.filter.view ~= "Journal" then
        write("action", "View item history", nil, function()
            openHistory(book, key)
        end)
    end
    write("note", "The Journal keeps recent activity. Older entries may disappear, but your Collection totals remain.")
    local function breakdown(title, totals, emptyMessage, labelFor)
        write("section", title)
        local labels = {}
        for label, quantity in pairs(totals) do
            if quantity > 0 then
                labels[#labels + 1] = label
            end
        end
        table.sort(labels)
        if #labels == 0 then
            write("note", emptyMessage)
            return
        end
        for _, label in ipairs(labels) do
            write("pair", labelFor(label), tostring(totals[label]))
        end
    end
    breakdown("How you got it", model.breakdown.methods, "No confirmed gains in this view.", function(label)
        return label == "Seen" and "Already had at first check" or label
    end)
    breakdown("Where it came from", model.breakdown.sources, "No source details recorded in this view.", function(label)
        return label == "Initial stock" and "Already had before first check" or label
    end)
    write("section", "Item history")
    write(
        "note",
        "Current counts add the latest known bags, bank, and equipped quantities for each character, "
            .. "including offline characters. "
            .. "Areas without a saved check add no known quantity; checks can be from different times."
    )
    write("date", "First seen", stamp(model.firstSeen))
    write("date", "Last seen", stamp(model.lastSeen))
    write("date", "First confirmed gain", stamp(model.firstGained))
    write("date", "Last confirmed gain", stamp(model.lastGained))
    write("section", "Last checks")
    local lastCharacter
    local areas = { bags = "Bags", bank = "Bank", equipped = "Equipped" }
    for _, check in ipairs(model.checks) do
        local actor = check.character .. "-" .. check.realm
        if actor ~= lastCharacter then
            write("note", actor .. (not check.online and " • Offline; status Unknown" or ""))
            lastCharacter = actor
        end
        write(
            "pair",
            areas[check.area] .. " • Last found",
            check.observedQuantity ~= nil and tostring(check.observedQuantity) or "Unknown"
        )
        write("date", "Last seen", check.observedAt and stamp(check.observedAt) or "Not seen yet")
        write("pair", "Latest check", check.quantity ~= nil and tostring(check.quantity) or "Unknown")
        write("date", "Checked", check.at and stamp(check.at) or "Not checked yet")
    end
    if developerMode then
        write("section", "Developer details")
        write("note", "Internal item key: " .. record.key)
        write("note", "Evidence summary: " .. model.evidence)
        write("note", #model.links .. " item versions • " .. #record.links .. " saved links")
    end
    write("section", "Item versions")
    if #model.links > 1 then
        write("note", "Hover over versions to compare bonuses, enchants, and gems.")
    end
    if #record.links > #model.links then
        write(
            "note",
            #record.links
                .. " saved links represent "
                .. #model.links
                .. " distinct item "
                .. (#model.links == 1 and "version." or "versions.")
        )
    end
    for _, group in ipairs(model.links) do
        write("link", group.link)
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
    if diagnostic.kind == "unsupported" then
        return "Saved item history is from another Ledger version; it is read-only."
    elseif diagnostic.kind == "damaged" then
        return "Some saved item history is damaged; readable entries are shown."
    end
    if evidence.discarded > 0 then
        return "Warning: "
            .. evidence.discarded
            .. " item changes need review; details discarded • "
            .. date("%d %b %Y", evidence.firstDiscarded)
            .. " – "
            .. date("%d %b %Y", evidence.lastDiscarded)
    end
    local count = evidence.count
    return count > 0 and (count .. " item changes need review • no gains guessed") or ""
end

local function renderBody(book, requestedKey)
    local scopeKey = (book.filter.realm or "") .. ":" .. (book.filter.character or "")
    if book.lastDetailScope ~= scopeKey then
        book.lastDetailScope = scopeKey
    end
    local journal = book.filter.view == "Journal"
    local evidence = book.filter.view == "Evidence"
    local gallery = book.filter.view == "Gallery"
    for _, control in ipairs({ book.scope, book.realmFilter, book.clearFilters }) do
        control:Show()
    end
    for _, control in ipairs({
        book.ownershipFilter,
        book.qualityFilter,
        book.methodFilter,
        book.sortFilter,
        book.ownershipHelp,
        book.place,
        book.sourceFilter,
    }) do
        control:SetShown(not journal and not evidence)
    end
    book.actionFilter:SetShown(journal)
    book.dateFilter:SetShown(journal)
    for _, control in ipairs(book.categories) do
        Widgets.enable(control, not journal and not evidence)
    end
    book.scope:SetText(book.filter.character or "All characters")
    book.realmFilter:SetText(book.filter.realm or "All realms")
    book.place:SetText(book.filter.place or "All places")
    book.ownershipFilter:SetText(choiceLabel("ownership", book.filter.ownership))
    book.qualityFilter:SetText(choiceLabel("quality", book.filter.quality))
    book.methodFilter:SetText(choiceLabel("method", book.filter.method))
    book.sortFilter:SetText(
        choiceLabel("sort", book.filter.sort or (book.filter.view == "Discoveries" and "discovered" or "name"))
    )
    book.actionFilter:SetText(choiceLabel("action", book.filter.action))
    book.dateFilter:SetText(book.filter.dateRange or "Any date")
    local size = pageSize(book)
    local result, pending = book.query:step(book.store, book.character, book.realm, book.filter)
    book.queryPending = pending
    if not result and pending then
        result = book.query:lastCompleteResult(book.store, book.character, book.realm, book.filter)
    end
    if not result then
        book.empty:SetText(
            evidence and "Loading item changes to review…"
                or journal and "Loading your Journal…"
                or "Loading your Collection…"
        )
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
        book.detailEmpty:Hide()
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
                evidence and (#result.rows == 1 and " item to review" or " items to review")
                or journal and (#result.rows == 1 and " entry" or " entries")
                or (#result.rows == 1 and " item" or " items")
            )
    )
    book.discoveries:SetText(result.discoveryCount .. (result.discoveryCount == 1 and " discovery" or " discoveries"))
    local journalContext = book.filter.historyKey and "This item's history • newest first"
        or (
            (book.filter.character or book.filter.realm) and "Recent activity for this view"
            or "Recent activity for all characters"
        )
    book.context:SetText(
        evidence and "Item changes to review"
            or journal and journalContext
            or (book.filter.category or (gallery and "Gear & pending items" or "All items"))
    )
    book.backToCollection:SetShown(journal and book.historyReturn ~= nil)
    book.quantityHeading:SetShown(not gallery and not evidence)
    book.quantityHeading:SetText(journal and "UNITS" or (book.filter.character and "CHAR CURRENT" or "ALL CURRENT"))
    local state = #result.rows == 0 and "No matching items. Try another search or clear your filters." or ""
    if gallery then
        state = "No matching gear. Try another search or clear your filters."
    end
    if result.discoveryCount == 0 then
        state = "Your collection starts here. Open your bags or bank to record items."
    end
    if journal then
        state = "No retained activity in this view. This does not mean no lifetime gains. "
            .. "Retention limits are in AddOns Settings."
    end
    if evidence then
        state = result.total == 0 and "No item changes need review in this view."
            or "No matching item changes. Try another search or character/realm filter."
        if result.discarded > 0 then
            state = state .. " Older details are no longer available."
        end
    end
    book.empty:SetText(state)
    book.empty:SetShown(#result.rows == 0)
    local loadingText = result.loading > 0 and (result.loading .. " items awaiting item data") or ""
    local sourceLabel = "All sources"
    for _, source in ipairs(result.sources or {}) do
        if source.key == book.filter.source then
            sourceLabel = source.label
        end
    end
    book.sourceFilter:SetText(
        book.filter.source and sourceLabel == "All sources" and "No gains from this source here" or sourceLabel
    )
    if not journal and not evidence and book.filter.source then
        loadingText = "Shows items gained from this source, not everything it can drop."
            .. (loadingText ~= "" and ("\n" .. loadingText) or "")
    end
    if journal and book.filter.dateFrom then
        local range = stamp(book.filter.dateFrom) .. " through " .. stamp(book.filter.dateTo - 1) .. " (inclusive)"
        loadingText = range .. (loadingText ~= "" and ("\n" .. loadingText) or "")
    end
    book.loading:SetText(loadingText)
    local warningText = warning(book)
    book.warning:SetText(warningText)
    book.warning:SetShown(warningText ~= "")
    if evidence then
        local discardedRange = stamp(result.firstDiscarded) .. " – " .. stamp(result.lastDiscarded)
        book.loading:SetText(
            result.discarded > 0 and (result.discarded .. " older item changes without details • " .. discardedRange)
                or "No older item changes without details."
        )
    end
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
        Widgets.tint(control.count, control.selected and colors.gold or colors.muted)
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
            Widgets.tint(row:GetFontString(), row.nameColor)
            Widgets.itemIcon(row.icon, not evidence and item.metadata.icon or nil)
            row.subtitle:SetText(
                evidence and (item.status .. " • " .. item.character .. "-" .. item.realm)
                    or journal and (stamp(item.at) .. " • " .. item.actors)
                    or (
                        book.filter.view == "Discoveries" and ("First seen " .. stamp(item.discoveredAt))
                        or (gallery and (item.loading and "Loading item details…" or item.ownership))
                        or item.category
                    )
            )
            local currentQuantity
            if book.filter.character then
                currentQuantity = item.characterCurrent
            else
                currentQuantity = item.allCharactersCurrent
            end
            row.quantity:SetText(
                evidence and "" or journal and tostring(item.recorded or "Unknown") or exactQuantity(currentQuantity)
            )
        end
    end
    book.pageLabel:SetText(book.page .. " / " .. pages)
    Widgets.enable(book.previous, book.page > 1)
    Widgets.enable(book.next, book.page < pages)
    if book.selected and not book.store:describe(book.selected) then
        book.selected = nil
    end
    if evidence then
        local selected = requestedKey or book.selectedEvidence
        book.detailPending = false
        if not result.positions[selected] then
            selected = result.rows[(book.page - 1) * size + 1] and result.rows[(book.page - 1) * size + 1].id
        end
        selectItem(book, selected)
    elseif journal then
        selectItem(book, requestedKey)
    else
        local selected = requestedKey or book.selected
        if not result.byKey[selected] then
            selected = result.rows[1] and result.rows[1].key
        end
        selectItem(book, selected)
    end
    book.dirty = pending or book.detailPending
end

render = function(book, requestedKey)
    return addon.Work.measure(book.api, "Book frame", function()
        return renderBody(book, requestedKey)
    end)
end

openHistory = function(book, key)
    local filter = {}
    for field, value in pairs(book.filter) do
        filter[field] = value
    end
    book.historyReturn = { filter = filter, page = book.page, key = key }
    book.filter = { view = "Journal", historyKey = key }
    book.search:SetText("")
    book.page, book.selectedSequence = 1, nil
    render(book)
end

local function change(book, field, value)
    if field == "view" then
        book.filter.historyKey = nil
        book.historyReturn = nil
    end
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
    renderMenu(book)
    book.menu:Show()
    Widgets.fade(book, book.menu, 0.25, 0.75)
end

local function scopeMenu(book, anchor, kind)
    if book.queryPending and book.filter.view == "Evidence" then
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
    if key == "F1" then
        closeMenu(book)
        book.search:ClearFocus()
        book.help:SetShown(not book.help:IsShown())
        return
    end
    if key == "ESCAPE" then
        if book.help:IsShown() then
            book.help:Hide()
            book.guided = true
        elseif book.menu:IsShown() then
            closeMenu(book)
        elseif book.search:HasFocus() then
            book.search:ClearFocus()
        else
            frame:Hide()
        end
        return
    end
    if book.help:IsShown() then
        if key == "ENTER" then
            book.help:Hide()
            book.guided = true
        else
            frame:SetPropagateKeyboardInput(true)
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
        if not Widgets.preferences.lockWindow then
            frame:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local px, py = api.UIParent:GetCenter()
        local scale = frame:GetScale()
        book.x, book.y = x * scale - px, y * scale - py
        fit(book)
        save(book)
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
    book.backToCollection = Widgets.button(book, sidebar, "Back to Collection", 6, 466, 166, 32, function()
        local previous = book.historyReturn
        if previous then
            book.filter, book.page, book.selected = previous.filter, previous.page, previous.key
            book.historyReturn, book.selectedSequence = nil, nil
            book.search:SetText(book.filter.search or "")
            book.page = previous.page
            render(book, previous.key)
        end
    end)
    Widgets.text(api, sidebar, "CATEGORIES", 12, 16, 154, 10, colors.muted)
    local categories =
        { "All items", "Weapons", "Armour", "Recipes", "Materials", "Consumables", "Junk", "Other", "Unknown" }
    for index, category in ipairs(categories) do
        local selectedCategory = category ~= "All items" and category or nil
        local control = Widgets.button(book, sidebar, category, 0, 42 + (index - 1) * 30, 178, 28, function()
            change(book, "category", selectedCategory)
        end)
        control.category = selectedCategory
        control:GetFontString():SetWidth(122)
        control.count = Widgets.text(api, control, "", 136, 10, 30, 11, colors.muted)
        control.count:SetJustifyH("RIGHT")
        book.categories[index] = control
    end
    Widgets.fill(sidebar, colors.edge, 12, 326, 154, 1, "ARTWORK")
    Widgets.text(api, sidebar, "ITEM HISTORY", 12, 337, 154, 10, colors.muted)
    book.sourceFilter = Widgets.dropdown(book, sidebar, "All sources", 6, 354, 166, function(self)
        if book.queryPending or not book.result then
            return
        end
        local choices = { { label = "All sources" } }
        for _, source in ipairs(book.result.sources or {}) do
            choices[#choices + 1] = { label = source.label, source = source.key }
        end
        showMenu(book, self, choices, function(choice)
            change(book, "source", choice.source)
        end)
    end)
    book.place = Widgets.dropdown(book, sidebar, "All places", 6, 398, 166, function(self)
        if book.queryPending or not book.result then
            return
        end
        local choices = { { label = "All places" } }
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
    Widgets.tint(book.search, colors.text)
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
    local function browseDropdown(field, parent, x, y, width)
        return Widgets.dropdown(book, parent, "", x, y, width, function(self)
            showMenu(book, self, browseChoices[field], function(choice)
                change(book, field, choice.value)
            end)
        end)
    end
    book.ownershipFilter = browseDropdown("ownership", sidebar, 6, 438, 132)
    book.qualityFilter = browseDropdown("quality", sidebar, 6, 474, 166)
    book.methodFilter = browseDropdown("method", sidebar, 6, 510, 166)
    book.sortFilter = browseDropdown("sort", frame, 218, 232, 160)
    book.actionFilter = browseDropdown("action", frame, 218, 232, 150)
    book.dateFilter = Widgets.dropdown(book, frame, "Any date", 376, 232, 164, function(self)
        local choices = { { label = "Any date" } }
        local now = api.GetServerTime and api.GetServerTime()
        if now then
            for _, range in ipairs({ { "Last 24 hours", 1 }, { "Last 7 days", 7 }, { "Last 30 days", 30 } }) do
                choices[#choices + 1] = { label = range[1], from = now - range[2] * 86400, to = now + 1 }
            end
        end
        showMenu(book, self, choices, function(choice)
            book.filter.dateFrom, book.filter.dateTo = choice.from, choice.to
            change(book, "dateRange", choice.from and choice.label or nil)
        end)
    end)
    book.clearFilters = Widgets.button(book, frame, "Clear filters", 548, 232, 110, 26, function()
        book.filter = { view = book.filter.view, historyKey = book.filter.historyKey }
        book.search:SetText("")
        book.page = 1
        closeMenu(book)
        render(book)
    end)
    book.count = Widgets.text(api, frame, "", 218, 274, 160, 12)
    book.context = Widgets.text(api, frame, "", 390, 274, 268, 11, colors.muted)
    book.context:SetJustifyH("RIGHT")
    book.quantityHeading = Widgets.text(api, frame, "ALL CURRENT", 558, 295, 90, 9, colors.muted)
    book.quantityHeading:SetJustifyH("RIGHT")
    book.empty = Widgets.text(api, frame, "", 248, 408, 380, 14, colors.muted)
    for index = 1, PAGE_SIZE do
        local row = itemButton(book, 218, 314 + (index - 1) * 42, 440, 40)
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
    book.ownership = Widgets.text(api, book.detailHeader, "", 26, 92, 348, 11, colors.green)
    book.ownershipDot = Widgets.fill(book.detailHeader, colors.green, 16, 96, 4, 4, "ARTWORK")
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
    local function count(label, y)
        local caption = Widgets.text(api, book.detailHeader, label, 18, y, 264, 10, colors.muted)
        local value = Widgets.text(api, book.detailHeader, "Unknown", 292, y - 1, 88, 12, colors.text)
        value:SetJustifyH("RIGHT")
        return value, caption
    end
    book.characterOverall = count("CHARACTER OVERALL", 116)
    book.allCharactersOverall = count("ALL CHARACTERS OVERALL", 134)
    book.characterCurrent = count("CHARACTER CURRENT", 152)
    book.allCharactersCurrent = count("ALL CHARACTERS CURRENT", 170)
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
        local record = book.selected and book.store:describe(book.selected)
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
    book.loading = Widgets.text(api, frame, "", 218, 656, 440, 10, colors.muted)
    book.loading:SetHeight(22)
    Widgets.button(book, frame, "Review item changes", 20, 680, 150, 18, function()
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
        save(book)
        book.search:ClearFocus()
        book.help:Hide()
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
    local helpText = "The Ledger tracks characters after you log in on them. "
        .. "Open each character's bank to check its contents.\n\n"
        .. "Character overall counts that character's first-seen units plus confirmed gains, after refunds. "
        .. "All characters overall adds those character totals.\n\n"
        .. "Current counts add the latest known quantities in bags, bank, and equipped gear "
        .. "for every tracked character, including offline characters.\n\n"
        .. "Character overall shows Unknown if saved history cannot separate a confirmed gain "
        .. "from the first recorded stock.\n\n"
        .. "Current counts use saved quantities, which can be from different times. "
        .. "Areas with no saved check add no known quantity.\n\n"
        .. "Historical only means the item was not found after all relevant bags, bank, and gear were checked."
    book.help = Widgets.panel(api, frame, 218, 146, 440, 500, colors.raised)
    book.help:SetFrameLevel(frame:GetFrameLevel() + 30)
    book.help:EnableMouse(true)
    Widgets.text(api, book.help, "About your Ledger", 18, 18, 400, 20, colors.gold)
    local explanation = Widgets.text(api, book.help, helpText, 18, 58, 400, 13)
    explanation:SetHeight(360)
    Widgets.button(book, book.help, "Got it", 18, 444, 130, 32, function()
        book.guided = true
        book.help:Hide()
    end)
    book.help:Hide()
    local function help()
        closeMenu(book)
        book.search:ClearFocus()
        book.help:Show()
    end
    Widgets.button(book, header, "Help (F1)", 520, 24, 90, 30, help)
    Widgets.button(book, header, "Settings", 620, 24, 90, 30, function()
        if addon.Settings and addon.Settings.open(api) then
            -- Keep the Settings panel visible after opening it from this window.
            frame:Hide()
        end
    end)
    local function helpButton(parent, x, y, height)
        local control = Widgets.button(book, parent, "?", x, y, 28, height, help)
        local font = control:GetFontString()
        font:ClearAllPoints()
        font:SetPoint("CENTER")
        font:SetWidth(24)
        font:SetJustifyH("CENTER")
        return control
    end
    book.ownershipHelp = helpButton(sidebar, 144, 438, 32)
    helpButton(frame, 566, 290, 20)
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
        local restoring = not active or active.store ~= store
        active = active or create(api)
        if restoring then
            local preferences = store:book()
            active.filter, active.scale = preferences.filter, preferences.scale
            active.x, active.y, active.guided = preferences.x, preferences.y, preferences.guided
            active.developerMode = preferences.developerMode
            active.selected, active.selectedSequence, active.selectedEvidence = nil, nil, nil
            active.historyReturn, active.focus, active.page = nil, nil, 1
            active.search:SetText(active.filter.search or "")
            closeMenu(active)
            active.search:ClearFocus()
        end
        active.store, active.character, active.realm = store, character, realm
        Widgets.applyPreferences(store:display())
        if filterCharacter or filterRealm then
            active.filter.character, active.filter.realm = filterCharacter, filterRealm
        end
        local days = { ["Last 24 hours"] = 1, ["Last 7 days"] = 7, ["Last 30 days"] = 30 }
        local now = api.GetServerTime and api.GetServerTime()
        local duration = days[active.filter.dateRange]
        active.filter.dateFrom = duration and now and now - duration * 86400 or nil
        active.filter.dateTo = duration and now and now + 1 or nil
        fit(active)
        render(active)
        local opening = not active.opened or not active.frame:IsShown()
        active.frame:Show()
        if opening then
            Widgets.fade(active, active.frame, 0.45, 0.75)
        end
        if not active.guided then
            active.help:Show()
        end
        active.opened = true
        return active.frame
    end)
end

---@param store ALStore
---@param character string
---@param realm string
---@param link string
---@return table?
function Book.openDiscovery(api, store, character, realm, link)
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    local key = itemID and addon.Item.key(link, itemID)
    if not key then
        return nil
    end
    local frame = Book.open(api, store, character, realm)
    if not frame then
        return nil
    end
    active.filter = { view = "Discoveries", sort = "discovered" }
    active.selected, active.page = key, 1
    active.search:SetText("")
    active.search:ClearFocus()
    render(active, key)
    return frame
end

function Book.save()
    if active then
        save(active)
    end
end

function Book.toggle(api, store, character, realm)
    if active and active.store == store and active.frame:IsShown() then
        active.frame:Hide()
    else
        Book.open(api, store, character, realm)
    end
end

function Book.reset(store, kind)
    local preferences = store:book()
    if kind == "layout" then
        preferences.scale, preferences.x, preferences.y = 1, 0, 0
    else
        preferences.filter = {}
    end
    if store:setBook(preferences) and active and active.store == store then
        active.scale, active.x, active.y, active.filter =
            preferences.scale, preferences.x, preferences.y, preferences.filter
        active.selected, active.selectedSequence, active.selectedEvidence = nil, nil, nil
        active.historyReturn, active.page = nil, 1
        active.search:SetText(active.filter.search or "")
        active.search:ClearFocus()
        closeMenu(active)
        fit(active)
        render(active)
    end
end

function Book.setDeveloperMode(store, enabled)
    if type(enabled) ~= "boolean" then
        return false
    end
    local preferences = store:book()
    preferences.developerMode = enabled
    if not store:setBook(preferences) then
        return false
    end
    if active and active.store == store then
        active.developerMode = enabled
        active.dirty = true
    end
    return true
end

function Book.setScale(store, scale)
    if type(scale) ~= "number" or not (scale >= 0.6 and scale <= 1.1) then
        return false
    end
    local preferences = store:book()
    preferences.scale = scale
    if not store:setBook(preferences) then
        return false
    end
    if active and active.store == store then
        active.scale = scale
        fit(active)
    end
    return true
end

function Book.applyPreferences(store)
    if active and active.store == store then
        Widgets.applyPreferences(store:display())
        Widgets.stopMotion(active)
        active.frame:StopMovingOrSizing()
        if active.character then
            render(active)
        end
    end
end

function Book.refresh(store, character, realm)
    if active then
        active.store = store
        active.character, active.realm = character or active.character, realm or active.realm
        active.dirty = true
    end
end

addon.Book = Book
