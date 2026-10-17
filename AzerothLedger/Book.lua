local _, addon = ...

-- The Collection window's controller: turns input into BookState transitions,
-- then asks BookRender to draw. BookFrame builds the widgets.
local Book = {}
local active
local Widgets = addon.BookWidgets
local State = addon.BookState
local Frame = addon.BookFrame
local Render = addon.BookRender

local function save(book)
    if book.store then
        book.store:setBook(State.preferences(book.view))
    end
end

local function fit(book)
    local parent = book.api.UIParent
    local placement
    book.view, placement = State.place(book.view, parent:GetWidth(), parent:GetHeight())
    Frame.place(book, placement)
end

local closeMenu = Frame.closeMenu

-- Shows one item's details and marks its list row.
local function show(book, key)
    local previous = book.view
    book.view = State.selectItem(book.view, key)
    if book.view.filter.view == "Evidence" then
        Render.evidence(book, previous.selectedEvidence)
    else
        Render.details(book, previous.selected, book.actions)
    end
    Render.selection(book, key)
end

local function render(book, requestedKey)
    return addon.Work.measure(book.api, "Book frame", function()
        local target, drawn = Render.list(book, requestedKey)
        if not drawn then
            book.dirty = true
            return
        end
        show(book, target)
        book.dirty = book.queryPending or book.detailPending
    end)
end

-- The search box mirrors filter.search; restoring a filter sets its text.
local function setSearch(book, text)
    book.search:SetText(text or "")
end

local function change(book, view)
    book.view = view
    closeMenu(book)
    render(book)
end

local function openHistory(book, key)
    book.view = State.openHistory(book.view, key)
    setSearch(book, "")
    render(book)
end

local function turnPage(book, delta)
    book.view = State.turnPage(book.view, delta)
    render(book)
end

local function showMenu(book, anchor, choices, selectChoice)
    if book.menuAnchor == anchor and book.menu:IsShown() then
        closeMenu(book)
        return
    end
    book.menuAnchor, book.menuChoices, book.choose = anchor, choices, selectChoice
    book.view = State.openMenu(book.view)
    Frame.anchorMenu(book, anchor)
    Render.menu(book)
    book.menu:Show()
    Widgets.fade(book, book.menu, 0.25, 0.75)
end

local function scopeMenu(book, anchor, kind)
    local filter = book.view.filter
    if book.queryPending and filter.view == "Evidence" then
        return
    end
    local choices = { { label = kind == "character" and "All characters" or "All realms" } }
    local seen = {}
    for _, actor in ipairs(filter.view == "Evidence" and book.result.actors or book.store:characters()) do
        if kind == "character" or not seen[actor.realm] then
            if kind ~= "character" or not filter.realm or actor.realm == filter.realm then
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
        book.view = State.chooseScope(book.view, kind, choice)
        closeMenu(book)
        render(book)
    end)
end

local function focusControl(book, index)
    if book.focus then
        book.controls[book.focus]:UnlockHighlight()
    end
    book.focus = index
    book.controls[index]:LockHighlight()
end

local function dismissHelp(book)
    book.help:Hide()
    book.view = State.with(book.view, "guided", true)
end

local function menuKey(book, key)
    local count = #book.menuChoices
    if key == "TAB" then
        local direction = book.api.IsShiftKeyDown and book.api.IsShiftKeyDown() and -1 or 1
        book.view = State.menuCycle(book.view, count, direction)
    elseif key == "PAGEUP" or key == "PAGEDOWN" then
        book.view = State.menuPage(book.view, key == "PAGEUP" and -1 or 1)
    else
        book.view = State.menuMove(book.view, count, key == "UP" and -1 or 1)
    end
    Render.menu(book)
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
            dismissHelp(book)
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
            dismissHelp(book)
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
            menuKey(book, key)
            return
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
        focusControl(book, index)
        return
    end
    if key == "ENTER" and book.menu:IsShown() then
        book.choose(book.menuChoices[book.view.menu.index])
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
        if book.menu:IsShown() then
            menuKey(book, key)
        else
            turnPage(book, key == "PAGEUP" and -1 or 1)
        end
        return
    end
    if key == "UP" or key == "DOWN" then
        if book.queryPending or not book.result then
            return
        end
        if book.menu:IsShown() then
            menuKey(book, key)
            return
        end
        local view, requested = State.step(book.view, book.result, key == "UP" and -1 or 1)
        if view then
            book.view = view
            render(book, requested)
        end
        return
    end
    frame:SetPropagateKeyboardInput(true)
end

-- Input handlers the frame calls; each closes over the one book it serves.
local function actions(book)
    local api = book.api
    local handlers = {}
    function handlers.moved(x, y)
        book.view = State.moved(book.view, x, y)
        fit(book)
        save(book)
    end
    function handlers.returnFromHistory()
        local previous = book.view.historyReturn
        if previous then
            book.view = State.returnFromHistory(book.view)
            setSearch(book, book.view.filter.search)
            -- Search edits return to the first page; history returns to its own.
            book.view = State.with(book.view, "page", previous.page)
            render(book, previous.key)
        end
    end
    function handlers.change(field, value)
        change(book, State.change(book.view, field, value))
    end
    function handlers.sourceMenu(anchor)
        if book.queryPending or not book.result then
            return
        end
        local choices = { { label = "All sources" } }
        for _, source in ipairs(book.result.sources or {}) do
            choices[#choices + 1] = { label = source.label, source = source.key }
        end
        showMenu(book, anchor, choices, function(choice)
            handlers.change("source", choice.source)
        end)
    end
    function handlers.placeMenu(anchor)
        if book.queryPending or not book.result then
            return
        end
        local choices = { { label = "All places" } }
        local kinds = { zone = "Zone", dungeon = "Dungeon", place = "Place" }
        for _, place in ipairs(book.result.places) do
            choices[#choices + 1] =
                { label = kinds[place.kind] .. ": " .. place.name, place = place.name, kind = place.kind }
        end
        showMenu(book, anchor, choices, function(choice)
            change(book, State.choosePlace(book.view, choice.place, choice.kind))
        end)
    end
    function handlers.scopeMenu(anchor, kind)
        scopeMenu(book, anchor, kind)
    end
    function handlers.browseMenu(anchor, field)
        showMenu(book, anchor, Render.browseChoices[field], function(choice)
            handlers.change(field, choice.value)
        end)
    end
    function handlers.dateMenu(anchor)
        local choices = State.dateChoices(api.GetServerTime and api.GetServerTime())
        showMenu(book, anchor, choices, function(choice)
            change(book, State.chooseDates(book.view, choice.label, choice.from, choice.to))
        end)
    end
    function handlers.clearFilters()
        book.view = State.clearFilters(book.view)
        setSearch(book, "")
        closeMenu(book)
        render(book)
    end
    function handlers.searchChanged(text)
        book.view = State.search(book.view, text)
        book.dirty = true
    end
    function handlers.render()
        render(book)
    end
    function handlers.focusControl(control)
        for index, candidate in ipairs(book.controls) do
            if candidate == control then
                focusControl(book, index)
                break
            end
        end
    end
    function handlers.rowClicked(row, mouseButton)
        if row.evidenceID or row.key then
            if mouseButton == "RightButton" then
                Widgets.openLink(api, row.fullLink, mouseButton)
            else
                book.view = State.with(book.view, "selectedSequence", row.sequence)
                show(book, row.evidenceID or row.key)
            end
        end
    end
    function handlers.turnPage(delta)
        turnPage(book, delta)
    end
    function handlers.savedLinkMenu(anchor)
        local record = book.view.selected and book.store:describe(book.view.selected)
        if not record then
            return
        end
        local choices = {}
        for index, link in ipairs(record.links) do
            choices[#choices + 1] = { label = link, index = index }
        end
        showMenu(book, anchor, choices, function(choice)
            book.view = State.with(book.view, "previewIndex", choice.index)
            closeMenu(book)
            Render.preview(book)
        end)
    end
    function handlers.preview()
        Render.previewResult(book, addon.Client.previewItem(api, book.previewLink))
    end
    function handlers.resize(delta)
        book.view = State.resize(book.view, book.frame:GetScale(), delta)
        fit(book)
    end
    function handlers.choose(choice)
        book.choose(choice)
    end
    function handlers.menuPage(delta)
        book.view = State.menuPage(book.view, delta)
        Render.menu(book)
    end
    function handlers.key(key)
        keyboard(book, key)
    end
    function handlers.update()
        if book.dirty then
            render(book)
        end
    end
    function handlers.event(event)
        if not event or event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
            book.query:metadataChanged()
        end
        book.dirty = true
        fit(book)
    end
    function handlers.hidden()
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
    end
    function handlers.dismissHelp()
        dismissHelp(book)
    end
    function handlers.help()
        closeMenu(book)
        book.search:ClearFocus()
        book.help:Show()
    end
    function handlers.settings()
        if addon.Settings and addon.Settings.open(api) then
            -- Keep the Settings panel visible after opening it from this window.
            book.frame:Hide()
        end
    end
    function handlers.toggleSection(sectionKey)
        book.view = State.toggleSection(book.view, sectionKey)
        show(book, book.view.selected)
    end
    function handlers.command(command)
        if command[1] == "history" then
            openHistory(book, command[2])
        elseif command[1] == "sequence" then
            book.view = State.selectSequence(book.view, book.result, command[2])
            render(book)
        end
    end
    return handlers
end

local function create(api)
    local book = { api = api, view = State.new({}), query = addon.BookQuery.new(api) }
    book.actions = actions(book)
    Frame.build(book, book.actions)
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
            active.view = State.restore(active.view, store:book())
            active.focus = nil
            setSearch(active, active.view.filter.search)
            closeMenu(active)
            active.search:ClearFocus()
        end
        active.store, active.character, active.realm = store, character, realm
        Widgets.applyPreferences(store:display())
        active.view = State.scopeTo(active.view, filterCharacter, filterRealm)
        active.view = State.dateWindow(active.view, api.GetServerTime and api.GetServerTime())
        fit(active)
        render(active)
        local opening = not active.opened or not active.frame:IsShown()
        active.frame:Show()
        if opening then
            Widgets.fade(active, active.frame, 0.45, 0.75)
        end
        if not active.view.guided then
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
    active.view = State.discovery(active.view, key)
    setSearch(active, "")
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
        active.view = State.reset(active.view, preferences)
        setSearch(active, active.view.filter.search)
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
        active.view = State.with(active.view, "developerMode", enabled)
        active.dirty = true
    end
    return true
end

function Book.setScale(store, scale)
    if type(scale) ~= "number" or not (scale >= State.MIN_SCALE and scale <= State.MAX_SCALE) then
        return false
    end
    local preferences = store:book()
    preferences.scale = scale
    if not store:setBook(preferences) then
        return false
    end
    if active and active.store == store then
        active.view = State.with(active.view, "scale", scale)
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
