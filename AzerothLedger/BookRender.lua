local _, addon = ...

-- Draws query results and the view state into the book's widgets. Wording
-- comes from pure helpers; drawing never starts queries or changes filters.
local Render = {}
local Widgets = addon.BookWidgets
local State = addon.BookState
local Frame = addon.BookFrame
local colors = Widgets.colors

local browseChoices = addon.Schema.bookChoices()
Render.browseChoices = browseChoices

local previewMessages = {
    ready = "Choose a saved link, then preview it in the native dressing room.",
    opened = "Opened the native dressing room.",
    loading = "Item data is not loaded yet. Preview when it becomes available.",
    ["not-wearable"] = "This item cannot be worn in the dressing room. Its saved link is available below.",
    unavailable = "Native preview is unavailable. Its saved link is available below.",
}
Render.previewMessages = previewMessages

local function choiceLabel(field, value)
    for _, choice in ipairs(browseChoices[field]) do
        if choice.value == value then
            return choice.label
        end
    end
    return browseChoices[field][1].label
end

local function stamp(at)
    return at and date("%d %b %Y  %H:%M", at) or "Unknown"
end
Render.stamp = stamp

local function exactQuantity(quantity)
    return quantity == nil and "Unknown" or tostring(quantity)
end

local function plural(count, one, many)
    return count .. (count == 1 and one or many)
end

local function visibleRows(book)
    return book.view.filter.view == "Gallery" and book.galleryRows or book.rows
end

-- Pure wording --------------------------------------------------------------------

---@return table model for ItemRowMixin:present
function Render.rowModel(api, view, item)
    local kind = view.filter.view
    local journal, evidence, gallery = kind == "Journal", kind == "Evidence", kind == "Gallery"
    local subtitle
    if evidence then
        subtitle = item.status .. " • " .. item.character .. "-" .. item.realm
    elseif journal then
        subtitle = stamp(item.at) .. " • " .. item.actors
    elseif kind == "Discoveries" then
        subtitle = "First seen " .. stamp(item.discoveredAt)
    elseif gallery then
        subtitle = item.loading and "Loading item details…" or item.ownership
    else
        subtitle = item.category
    end
    local currentQuantity = view.filter.character and item.characterCurrent or item.allCharactersCurrent
    return {
        key = item.key,
        evidenceID = evidence and item.id or nil,
        sequence = journal and item.sequence or nil,
        fullLink = evidence and item.link or (not evidence and item.record.links[#item.record.links]),
        text = (journal or evidence) and (item.action .. " • " .. item.name) or item.name,
        color = evidence and colors.text or Widgets.quality(api, item.metadata.quality),
        icon = not evidence and item.metadata.icon or nil,
        subtitle = subtitle,
        quantity = evidence and "" or journal and tostring(item.recorded or "Unknown") or exactQuantity(
            currentQuantity
        ),
    }
end

function Render.emptyState(view, result)
    local kind = view.filter.view
    local state = #result.rows == 0 and "No matching items. Try another search or clear your filters." or ""
    if kind == "Gallery" then
        state = "No matching gear. Try another search or clear your filters."
    end
    if result.discoveryCount == 0 then
        state = "Your collection starts here. Open your bags or bank to record items."
    end
    if kind == "Journal" then
        state = "No retained activity in this view. This does not mean no lifetime gains. "
            .. "Retention limits are in AddOns Settings."
    end
    if kind == "Evidence" then
        state = result.total == 0 and "No item changes need review in this view."
            or "No matching item changes. Try another search or character/realm filter."
        if result.discarded > 0 then
            state = state .. " Older details are no longer available."
        end
    end
    return state
end

function Render.context(view)
    local filter = view.filter
    if filter.view == "Evidence" then
        return "Item changes to review"
    elseif filter.view == "Journal" then
        return filter.historyKey and "This item's history • newest first"
            or (
                (filter.character or filter.realm) and "Recent activity for this view"
                or "Recent activity for all characters"
            )
    end
    return filter.category or (filter.view == "Gallery" and "Gear & pending items" or "All items")
end

function Render.footnote(view, result)
    local filter = view.filter
    if filter.view == "Evidence" then
        local discardedRange = stamp(result.firstDiscarded) .. " – " .. stamp(result.lastDiscarded)
        return result.discarded > 0
                and (result.discarded .. " older item changes without details • " .. discardedRange)
            or "No older item changes without details."
    end
    local text = result.loading > 0 and (result.loading .. " items awaiting item data") or ""
    if filter.view ~= "Journal" and filter.source then
        text = "Shows items gained from this source, not everything it can drop."
            .. (text ~= "" and ("\n" .. text) or "")
    end
    if filter.view == "Journal" and filter.dateFrom then
        local range = stamp(filter.dateFrom) .. " through " .. stamp(filter.dateTo - 1) .. " (inclusive)"
        text = range .. (text ~= "" and ("\n" .. text) or "")
    end
    return text
end

function Render.warning(store)
    local diagnostic = store:diagnostic()
    local evidence = store:evidenceStatus()
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

-- Lists the detail rows for an item as { kind, left, right, command } entries.
-- Commands are { "history", key }, { "sequence", sequence }; sections toggle.
function Render.detailLines(view, result, model, key)
    local lines = {}
    local function write(kind, left, right, command)
        lines[#lines + 1] = { kind = kind, left = left, right = right, command = command }
    end
    local developerMode = view.developerMode == true
    local record = model.record
    if view.filter.view == "Journal" then
        local activity
        for _, row in ipairs(result.rows) do
            if row.sequence == view.selectedSequence then
                activity = row
                break
            end
        end
        if activity then
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
                local retained = sequence and result.bySequence[sequence]
                if retained then
                    write("action", label .. " • " .. stamp(retained.at), nil, { "sequence", sequence })
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
        end
    else
        write("action", "View item history", nil, { "history", key })
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
        return addon.Collection.methodLabel(label)
    end)
    breakdown("Where it came from", model.breakdown.sources, "No source details recorded in this view.", function(label)
        return addon.Collection.sourceLabel(label)
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
    return lines
end

function Render.evidenceLines(item)
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
    return lines
end

-- Drawing ---------------------------------------------------------------------------

function Render.preview(book)
    local view = book.view
    local record = view.selected and book.store:describe(view.selected)
    local selection =
        addon.Collection.gallerySelection(book.result, view.selected, record and record.links[view.previewIndex or 1])
    local link = selection and selection.link
    book.view = State.with(view, "previewIndex", selection and selection.index or 1)
    book.previewLink = link
    book.savedLink:SetText("Saved link " .. (book.view.previewIndex or 1) .. " of " .. (record and #record.links or 0))
    local status = addon.Client.previewStatus(book.api, link)
    Widgets.enable(book.preview, status == "ready")
    book.previewMessage:SetText(previewMessages[status])
end

function Render.previewResult(book, status)
    book.previewMessage:SetText(previewMessages[status])
end

---@param previous string|number|nil the evidence id shown before this selection
function Render.evidence(book, previous)
    local id = book.view.selectedEvidence
    local oldScroll = book.detailScroll:GetVerticalScroll()
    book.detailHeader:Hide()
    book.previewPanel:Hide()
    local index = book.result.positions[id]
    local item = index and book.result.rows[index]
    book.detailEmpty:SetShown(not item)
    book.detailScroll:SetShown(item ~= nil)
    Frame.detailArea(book, 16, 520)
    Frame.hideDetailRows(book)
    if not item then
        return
    end
    local lines = Render.evidenceLines(item)
    local y = 0
    for number, text in ipairs(lines) do
        local row = Frame.detailRow(book, number)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        y = y + row:presentLine(text, number == 1, item.link and number == #lines and item.link or nil)
    end
    book.detailBody:SetHeight(math.max(1, y))
    book.detailScroll:SetVerticalScroll(previous == id and math.min(oldScroll, math.max(0, y - 520)) or 0)
end

local function header(book, model)
    local record = model.record
    local info = addon.Client.itemMetadata(book.api, record)
    local itemName = record.links[1]:match("%[([^%]]+)%]") or ("Item " .. record.itemID)
    book.itemTitle:SetText(itemName)
    Widgets.tint(book.itemTitle, Widgets.quality(book.api, info.quality))
    book.itemCategory:SetText(info.category .. "  •  " .. model.scopeLabel)
    Widgets.itemIcon(book.itemIcon, info.icon)
    book.itemLink = record.links[#record.links]
    local present = model.ownershipState == "present"
    book.ownership:SetText("Status: " .. model.ownership)
    Widgets.tint(book.ownership, present and colors.green or colors.gold)
    Widgets.tint(book.ownershipDot, present and colors.green or colors.gold, true)
    book.characterOverall:SetText(exactQuantity(model.characterOverall))
    book.allCharactersOverall:SetText(exactQuantity(model.allCharactersOverall))
    book.characterCurrent:SetText(exactQuantity(model.characterCurrent))
    book.allCharactersCurrent:SetText(exactQuantity(model.allCharactersCurrent))
end

---@param previous string? the item key shown before this selection
function Render.details(book, previous, actions)
    local view = book.view
    local key = view.selected
    local oldScroll = book.detailScroll:GetVerticalScroll()
    local scope = { character = view.filter.character, realm = view.filter.realm }
    local model, pending = book.query:inspect(book.store, key, book.character, book.realm, scope)
    book.detailPending = pending
    book.detailEmpty:SetText(pending and "Loading item details…" or "Select an item to explore\nits history.")
    if pending then
        book.dirty = true
    end
    book.detailEmpty:SetShown(not model)
    book.detailHeader:SetShown(model ~= nil)
    book.detailScroll:SetShown(model ~= nil)
    local gallery = view.filter.view == "Gallery"
    book.previewPanel:SetShown(gallery and model ~= nil)
    Frame.detailArea(book, gallery and 292 or 208, gallery and 236 or Frame.DETAIL_HEIGHT)
    Frame.hideDetailRows(book)
    if not model then
        book.previewLink = nil
        return
    end
    if previous ~= key then
        Widgets.fade(book, book.detailHeader, 0.35, 0.65)
        Widgets.fade(book, book.detailScroll, 0.35, 0.65)
    end
    if gallery then
        Render.preview(book)
    end
    header(book, model)
    book.view = State.sections(book.view, State.detailIdentity(book.view, key))
    local collapsedSections = book.view.collapsedSections
    local index, y, sectionIndex, collapsed = 0, 0, 0, false
    for _, line in ipairs(Render.detailLines(book.view, book.result, model, key)) do
        index = index + 1
        local row = Frame.detailRow(book, index)
        if line.kind == "section" then
            sectionIndex = sectionIndex + 1
            collapsed = collapsedSections[sectionIndex] == true
            local sectionKey = sectionIndex
            row.onClick = function()
                actions.toggleSection(sectionKey)
            end
        elseif line.command then
            local command = line.command
            row.onClick = function()
                actions.command(command)
            end
        else
            row.onClick = nil
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        y = y + (row:present(line.kind, line.left, line.right, collapsed) or 0)
    end
    Frame.finishDetails(book, y, previous == key, oldScroll)
end

function Render.selection(book, key)
    for _, row in ipairs(visibleRows(book)) do
        Widgets.select(row, State.isSelected(book.view, row, key))
    end
end

local function loading(book, evidence, journal)
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
end

local function controls(book, journal, evidence)
    local filter = book.view.filter
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
    book.scope:SetText(filter.character or "All characters")
    book.realmFilter:SetText(filter.realm or "All realms")
    book.place:SetText(filter.place or "All places")
    book.ownershipFilter:SetText(choiceLabel("ownership", filter.ownership))
    book.qualityFilter:SetText(choiceLabel("quality", filter.quality))
    book.methodFilter:SetText(choiceLabel("method", filter.method))
    book.sortFilter:SetText(
        choiceLabel("sort", filter.sort or (filter.view == "Discoveries" and "discovered" or "name"))
    )
    book.actionFilter:SetText(choiceLabel("action", filter.action))
    book.dateFilter:SetText(filter.dateRange or "Any date")
end

local function summary(book, result, journal, evidence, gallery)
    local view = book.view
    local filter = view.filter
    book.count:SetText(
        evidence and plural(#result.rows, " item to review", " items to review")
            or journal and plural(#result.rows, " entry", " entries")
            or plural(#result.rows, " item", " items")
    )
    book.discoveries:SetText(plural(result.discoveryCount, " discovery", " discoveries"))
    book.context:SetText(Render.context(view))
    book.backToCollection:SetShown(journal and view.historyReturn ~= nil)
    book.quantityHeading:SetShown(not gallery and not evidence)
    book.quantityHeading:SetText(journal and "UNITS" or (filter.character and "CHAR CURRENT" or "ALL CURRENT"))
    book.empty:SetText(Render.emptyState(view, result))
    book.empty:SetShown(#result.rows == 0)
    local sourceLabel = "All sources"
    for _, source in ipairs(result.sources or {}) do
        if source.key == filter.source then
            sourceLabel = source.label
        end
    end
    book.sourceFilter:SetText(
        filter.source and sourceLabel == "All sources" and "No gains from this source here" or sourceLabel
    )
    book.loading:SetText(Render.footnote(view, result))
    local warningText = Render.warning(book.store)
    book.warning:SetText(warningText)
    book.warning:SetShown(warningText ~= "")
    Widgets.select(book.collectionTab, not evidence and not journal and not gallery and filter.view ~= "Discoveries")
    Widgets.select(book.discoveryTab, filter.view == "Discoveries")
    Widgets.select(book.journalTab, journal)
    Widgets.select(book.galleryTab, gallery)
    for _, control in ipairs(book.categories) do
        local category = control.category
        Widgets.select(control, filter.category == category)
        control.count:SetText(tostring(category and (result.categories[category] or 0) or result.matchedCount))
        Widgets.tint(control.count, control.selected and colors.gold or colors.muted)
    end
end

-- Steps the query and draws the list. Returns the item whose details should
-- be shown, and whether a result was available to draw.
---@return string|number|nil target
---@return boolean drawn
function Render.list(book, requestedKey)
    local filter = book.view.filter
    local journal, evidence, gallery = filter.view == "Journal", filter.view == "Evidence", filter.view == "Gallery"
    controls(book, journal, evidence)
    local result, pending = book.query:step(book.store, book.character, book.realm, filter)
    book.queryPending = pending
    if not result and pending then
        result = book.query:lastCompleteResult(book.store, book.character, book.realm, filter)
    end
    if not result then
        loading(book, evidence, journal)
        return nil, false
    end
    local target, pages
    book.result = result
    book.view, target, pages = State.reconcile(book.view, result, requestedKey, function(key)
        return book.store:describe(key) ~= nil
    end)
    summary(book, result, journal, evidence, gallery)
    for _, row in ipairs(gallery and book.rows or book.galleryRows) do
        row:Hide()
    end
    local size, page = State.pageSize(book.view), book.view.page
    for index, row in ipairs(visibleRows(book)) do
        local item = result.rows[(page - 1) * size + index]
        row:present(item and Render.rowModel(book.api, book.view, item) or nil)
    end
    book.pageLabel:SetText(page .. " / " .. pages)
    Widgets.enable(book.previous, page > 1)
    Widgets.enable(book.next, page < pages)
    if evidence then
        book.detailPending = false
    end
    return target, true
end

function Render.menu(book)
    local count = #book.menuChoices
    local pages
    book.view, pages = State.menuWindow(book.view, count)
    local menu = book.view.menu
    local offset = (menu.page - 1) * State.MENU_SIZE
    for index, row in ipairs(book.menuRows) do
        local choice = book.menuChoices[offset + index]
        row.choice = choice
        row:SetShown(choice ~= nil)
        if choice then
            row:SetText(choice.label)
            Widgets.select(row, offset + index == menu.index)
        end
    end
    local shown = math.min(State.MENU_SIZE, count - offset)
    book.menu:SetHeight(shown * 30 + 48)
    book.menu.background:SetHeight(book.menu:GetHeight())
    book.menuPrevious:ClearAllPoints()
    book.menuPrevious:SetPoint("TOPLEFT", 8, -(shown * 30 + 10))
    book.menuNext:ClearAllPoints()
    book.menuNext:SetPoint("TOPLEFT", 172, -(shown * 30 + 10))
    Widgets.enable(book.menuPrevious, menu.page > 1)
    Widgets.enable(book.menuNext, menu.page < pages)
end

addon.BookRender = Render
