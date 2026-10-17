local _, addon = ...

-- The book's view state: tab, filters, paging, selection, open menu position,
-- and window placement. Every transition returns a new view and leaves its
-- input untouched, so frames and handlers never share a half-changed filter.
local State = {}
State.PAGE_SIZE = 7
State.GALLERY_PAGE_SIZE = 6
State.MENU_SIZE = 8
State.MIN_SCALE = 0.6
State.MAX_SCALE = 1.1
State.WIDTH = 1100
State.HEIGHT = 700

local DATE_RANGES = { ["Last 24 hours"] = 1, ["Last 7 days"] = 7, ["Last 30 days"] = 30 }

local function copy(value)
    local result = {}
    for key, field in pairs(value) do
        result[key] = field
    end
    return result
end

local function withFilter(view)
    local nextView = copy(view)
    nextView.filter = copy(view.filter)
    return nextView
end

---@param preferences table
---@return table
function State.new(preferences)
    return {
        filter = preferences.filter or {},
        scale = preferences.scale or 1,
        x = preferences.x,
        y = preferences.y,
        guided = preferences.guided,
        developerMode = preferences.developerMode,
        page = 1,
        menu = { page = 1, index = 1 },
    }
end

-- Restores persisted preferences and drops selection that belonged to another store.
function State.restore(view, preferences)
    local nextView = State.new(preferences)
    nextView.collapsedContext, nextView.collapsedSections = view.collapsedContext, view.collapsedSections
    nextView.previewIndex = view.previewIndex
    return nextView
end

function State.reset(view, preferences)
    local nextView = copy(view)
    nextView.scale, nextView.x, nextView.y, nextView.filter =
        preferences.scale, preferences.x, preferences.y, preferences.filter
    nextView.selected, nextView.selectedSequence, nextView.selectedEvidence = nil, nil, nil
    nextView.historyReturn, nextView.page = nil, 1
    return nextView
end

---@return table preferences payload for store:setBook
function State.preferences(view)
    return {
        version = 1,
        scale = view.scale,
        x = view.x or 0,
        y = view.y or 0,
        filter = view.filter,
        guided = view.guided,
        developerMode = view.developerMode,
    }
end

function State.with(view, field, value)
    local nextView = copy(view)
    nextView[field] = value
    return nextView
end

function State.pageSize(view)
    return view.filter.view == "Gallery" and State.GALLERY_PAGE_SIZE or State.PAGE_SIZE
end

-- Filters --------------------------------------------------------------------

function State.change(view, field, value)
    local nextView = withFilter(view)
    if field == "view" then
        nextView.filter.historyKey = nil
        nextView.historyReturn = nil
    end
    nextView.filter[field] = value
    nextView.page = 1
    nextView.selectedSequence = nil
    return nextView
end

function State.choosePlace(view, place, kind)
    local nextView = State.change(view, "place", place)
    nextView.filter.placeKind = kind
    return nextView
end

function State.chooseDates(view, label, from, to)
    local nextView = State.change(view, "dateRange", from and label or nil)
    nextView.filter.dateFrom, nextView.filter.dateTo = from, to
    return nextView
end

-- Recomputes the date window for a saved relative range such as "Last 7 days".
function State.dateWindow(view, now)
    local nextView = withFilter(view)
    local duration = DATE_RANGES[view.filter.dateRange]
    nextView.filter.dateFrom = duration and now and now - duration * 86400 or nil
    nextView.filter.dateTo = duration and now and now + 1 or nil
    return nextView
end

function State.dateChoices(now)
    local choices = { { label = "Any date" } }
    if now then
        for _, range in ipairs({ { "Last 24 hours", 1 }, { "Last 7 days", 7 }, { "Last 30 days", 30 } }) do
            choices[#choices + 1] = { label = range[1], from = now - range[2] * 86400, to = now + 1 }
        end
    end
    return choices
end

-- A character choice keeps its realm; a realm choice clears the character.
function State.chooseScope(view, kind, choice)
    local nextView = withFilter(view)
    if kind == "character" then
        nextView.filter.character = choice.character
        if choice.character then
            nextView.filter.realm = choice.realm
        end
    else
        nextView.filter.realm = choice.realm
        nextView.filter.character = nil
    end
    nextView.page = 1
    return nextView
end

function State.scopeTo(view, character, realm)
    if not character and not realm then
        return view
    end
    local nextView = withFilter(view)
    nextView.filter.character, nextView.filter.realm = character, realm
    return nextView
end

function State.search(view, text)
    local nextView = withFilter(view)
    nextView.filter.search = text
    nextView.page = 1
    return nextView
end

function State.clearFilters(view)
    local nextView = copy(view)
    nextView.filter = { view = view.filter.view, historyKey = view.filter.historyKey }
    nextView.page = 1
    return nextView
end

function State.discovery(view, key)
    local nextView = copy(view)
    nextView.filter = { view = "Discoveries", sort = "discovered" }
    nextView.selected, nextView.page = key, 1
    return nextView
end

-- Item history is a Journal view that remembers how to return to the Collection.
function State.openHistory(view, key)
    local nextView = copy(view)
    nextView.historyReturn = { filter = copy(view.filter), page = view.page, key = key }
    nextView.filter = { view = "Journal", historyKey = key }
    nextView.page, nextView.selectedSequence = 1, nil
    return nextView
end

function State.returnFromHistory(view)
    local previous = view.historyReturn
    if not previous then
        return view
    end
    local nextView = copy(view)
    nextView.filter, nextView.page, nextView.selected = previous.filter, previous.page, previous.key
    nextView.historyReturn, nextView.selectedSequence = nil, nil
    return nextView
end

-- Paging and selection ---------------------------------------------------------

function State.turnPage(view, delta)
    local nextView = copy(view)
    nextView.page = view.page + delta
    nextView.selectedSequence = nil
    nextView.selectedEvidence = nil
    return nextView
end

function State.selectItem(view, key)
    local nextView = copy(view)
    if view.filter.view == "Evidence" then
        nextView.selectedEvidence = key
    else
        nextView.selected = key
        if view.selected ~= key then
            nextView.previewIndex = 1
        end
    end
    return nextView
end

function State.selectRow(view, sequence, key)
    local nextView = State.with(view, "selectedSequence", sequence)
    return State.selectItem(nextView, key)
end

-- Selects a Journal entry and turns to the list page that contains it.
function State.selectSequence(view, result, sequence)
    local nextView = copy(view)
    nextView.selectedSequence = sequence
    nextView.page = math.ceil(result.positions[sequence] / State.PAGE_SIZE)
    return nextView
end

function State.selectedIn(view)
    local kind = view.filter.view
    return kind == "Evidence" and view.selectedEvidence or kind == "Journal" and view.selectedSequence or view.selected
end

-- Moves the selection by one result row; returns nil when there is no row there.
---@return table? view
---@return string|number|nil requested
function State.step(view, result, delta)
    local selected = State.selectedIn(view)
    local index = result.positions and result.positions[selected] or 1
    index = math.max(1, math.min(#result.rows, index + delta))
    local row = result.rows[index]
    if not row then
        return nil
    end
    local nextView = copy(view)
    nextView.selectedSequence = row.sequence
    nextView.page = math.ceil(index / State.pageSize(view))
    return nextView, view.filter.view == "Evidence" and row.id or row.key
end

-- Fits the view to a completed result: the selected Journal entry, a valid
-- page, and the item whose details should be shown.
---@param exists fun(key: string): boolean
---@return table view
---@return string|number|nil target
---@return integer pages
function State.reconcile(view, result, requestedKey, exists)
    local nextView = copy(view)
    local size = State.pageSize(view)
    local kind = view.filter.view
    if kind == "Journal" then
        local selected = result.bySequence and result.bySequence[view.selectedSequence]
        selected = selected or result.rows[(view.page - 1) * size + 1] or result.rows[1]
        nextView.selectedSequence = selected and selected.sequence or nil
        requestedKey = selected and selected.key or nil
    end
    local pages = math.max(1, math.ceil(#result.rows / size))
    nextView.page = math.max(1, math.min(view.page, pages))
    if nextView.selected and not exists(nextView.selected) then
        nextView.selected = nil
    end
    local target
    if kind == "Evidence" then
        target = requestedKey or nextView.selectedEvidence
        if not result.positions[target] then
            local first = result.rows[(nextView.page - 1) * size + 1]
            target = first and first.id
        end
    elseif kind == "Journal" then
        target = requestedKey
    else
        target = requestedKey or nextView.selected
        if not result.byKey[target] then
            target = result.rows[1] and result.rows[1].key
        end
    end
    return nextView, target, pages
end

function State.isSelected(view, row, key)
    local kind = view.filter.view
    if kind == "Evidence" then
        return row.evidenceID == view.selectedEvidence
    elseif kind == "Journal" then
        return row.sequence == view.selectedSequence
    end
    return row.key == key
end

-- Detail sections stay collapsed while the same item stays in the same view.
function State.detailIdentity(view, key)
    local item = view.filter.view == "Journal" and view.selectedSequence or key
    return tostring(view.filter.view) .. "\031" .. tostring(item)
end

function State.sections(view, identity)
    if view.collapsedContext == identity and view.collapsedSections then
        return view
    end
    local nextView = copy(view)
    if view.collapsedContext ~= identity then
        nextView.collapsedContext = identity
        nextView.collapsedSections = {}
    end
    nextView.collapsedSections = nextView.collapsedSections or {}
    return nextView
end

function State.toggleSection(view, sectionKey)
    local nextView = copy(view)
    nextView.collapsedSections = copy(view.collapsedSections or {})
    nextView.collapsedSections[sectionKey] = not nextView.collapsedSections[sectionKey]
    return nextView
end

-- Choice menus -------------------------------------------------------------------

function State.openMenu(view)
    return State.with(view, "menu", { page = 1, index = 1 })
end

-- Keeps the menu page in range and the keyboard choice on the visible page.
---@return table view
---@return integer pages
function State.menuWindow(view, count)
    local menu = copy(view.menu)
    local pages = math.max(1, math.ceil(count / State.MENU_SIZE))
    menu.page = math.max(1, math.min(menu.page, pages))
    local first = (menu.page - 1) * State.MENU_SIZE + 1
    local last = math.min(count, first + State.MENU_SIZE - 1)
    if menu.index < first or menu.index > last then
        menu.index = first
    end
    return State.with(view, "menu", menu), pages
end

function State.menuPage(view, delta)
    local menu = copy(view.menu)
    menu.page = menu.page + delta
    return State.with(view, "menu", menu)
end

function State.menuCycle(view, count, direction)
    local menu = copy(view.menu)
    menu.index = (menu.index + direction - 1) % count + 1
    menu.page = math.ceil(menu.index / State.MENU_SIZE)
    return State.with(view, "menu", menu)
end

function State.menuMove(view, count, delta)
    local menu = copy(view.menu)
    menu.index = math.max(1, math.min(count, menu.index + delta))
    menu.page = math.ceil(menu.index / State.MENU_SIZE)
    return State.with(view, "menu", menu)
end

-- Window placement ---------------------------------------------------------------

-- Clamps the saved scale and offset to the screen. The saved scale is kept,
-- so the window grows back when the screen does.
---@return table view
---@return table placement { scale, maximum, x, y }
function State.place(view, parentWidth, parentHeight)
    local maximum = math.min(State.MAX_SCALE, parentWidth * 0.9 / State.WIDTH, parentHeight * 0.86 / State.HEIGHT)
    local scale = math.min(view.scale, maximum)
    local maxX = math.max(0, (parentWidth - State.WIDTH * scale) / 2)
    local maxY = math.max(0, (parentHeight - State.HEIGHT * scale) / 2)
    local nextView = copy(view)
    nextView.x = math.max(-maxX, math.min(maxX, view.x or 0))
    nextView.y = math.max(-maxY, math.min(maxY, view.y or 0))
    return nextView, { scale = scale, maximum = maximum, x = nextView.x, y = nextView.y }
end

function State.resize(view, currentScale, delta)
    local scale = delta < 0 and math.max(State.MIN_SCALE, currentScale + delta)
        or math.min(State.MAX_SCALE, currentScale + delta)
    return State.with(view, "scale", scale)
end

function State.moved(view, x, y)
    local nextView = copy(view)
    nextView.x, nextView.y = x, y
    return nextView
end

addon.BookState = State
