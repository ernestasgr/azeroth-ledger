local _, addon = ...

-- Draws query results and the view state into the book's widgets. Wording
-- comes from pure helpers; drawing never starts queries or changes filters.
local Render = {}
local Widgets = addon.BookWidgets
local State = addon.BookState
local colors = Widgets.colors

local browseChoices = addon.StorePreferences.bookChoices()
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
Render.exactQuantity = exactQuantity

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
