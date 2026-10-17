-- Book view state: transitions return new views and never change their input.
local addon = {}
assert(loadfile("AzerothLedger/BookState.lua"))("AzerothLedger", addon)
local State = addon.BookState

-- Serializes a view so a test can prove a transition left it unchanged.
local function frozen(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for key, field in pairs(value) do
        parts[#parts + 1] = tostring(key) .. "=" .. frozen(field)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

local view = State.new({ filter = { view = "Collection", search = "ore" }, scale = 1, x = 20, y = -10 })
local before = frozen(view)

local changed = State.change(view, "category", "Weapons")
assert(changed.filter.category == "Weapons" and changed.page == 1)
assert(view.filter.category == nil and frozen(view) == before)

local paged = State.turnPage(State.with(view, "selectedSequence", 4), 2)
assert(paged.page == 3 and paged.selectedSequence == nil)
assert(frozen(view) == before)

local history = State.openHistory(State.with(view, "page", 3), "20000:0")
assert(history.filter.view == "Journal" and history.filter.historyKey == "20000:0" and history.page == 1)
local returned = State.returnFromHistory(history)
assert(returned.filter.view == "Collection" and returned.filter.search == "ore")
assert(returned.page == 3 and returned.selected == "20000:0" and returned.historyReturn == nil)
assert(State.change(history, "view", "Gallery").historyReturn == nil)

local scoped = State.chooseScope(State.scopeTo(view, "Ada", "A"), "realm", { realm = "B" })
assert(scoped.filter.realm == "B" and scoped.filter.character == nil)
local character = State.chooseScope(view, "character", { character = "Bo", realm = "C" })
assert(character.filter.character == "Bo" and character.filter.realm == "C")

local dated = State.dateWindow(State.change(view, "dateRange", "Last 7 days"), 1000000)
assert(dated.filter.dateFrom == 1000000 - 7 * 86400 and dated.filter.dateTo == 1000001)
assert(#State.dateChoices(nil) == 1 and #State.dateChoices(5) == 4)

-- Reconcile clamps the page and picks the item whose details are shown.
local result = {
    rows = { { key = "a" }, { key = "b" } },
    byKey = { a = true, b = true },
    positions = { a = 1, b = 2 },
}
local reconciled, target, pages = State.reconcile(State.with(view, "page", 9), result, nil, function()
    return true
end)
assert(reconciled.page == 1 and pages == 1 and target == "a")
local stepped, requested = State.step(State.with(view, "selected", "a"), result, 1)
assert(stepped.page == 1 and requested == "b")
assert(frozen(view) == before)

local journal = {
    rows = { { key = "a", sequence = 7 }, { key = "b", sequence = 8 } },
    bySequence = {},
    positions = { [7] = 1, [8] = 2 },
}
journal.bySequence[8] = journal.rows[2]
local journalView = State.with(State.change(view, "view", "Journal"), "selectedSequence", 8)
local _, journalTarget = State.reconcile(journalView, journal, nil, function()
    return true
end)
assert(journalTarget == "b")

-- Section collapse belongs to one item in one view.
local identity = State.detailIdentity(view, "a")
local sections = State.toggleSection(State.sections(view, identity), 2)
assert(sections.collapsedSections[2] == true and State.sections(sections, identity) == sections)
assert(next(State.sections(sections, State.detailIdentity(view, "b")).collapsedSections) == nil)

-- Menus keep the keyboard choice on the visible page.
local menu = State.menuPage(State.openMenu(view), 5)
local windowed, menuPages = State.menuWindow(menu, 10)
assert(menuPages == 2 and windowed.menu.page == 2 and windowed.menu.index == 9)
assert(State.menuCycle(windowed, 10, 1).menu.index == 10)
assert(State.menuCycle(State.menuCycle(windowed, 10, 1), 10, 1).menu.index == 1)

-- Placement clamps to the screen without forgetting the saved scale.
local placed, placement = State.place(State.with(view, "scale", 1.1), 1000, 600)
assert(placed.scale == 1.1 and placement.scale < 1.1 and placement.maximum == placement.scale)
assert(State.resize(view, 0.65, -0.1).scale == State.MIN_SCALE)
assert(State.preferences(placed).version == 1 and State.preferences(placed).filter == view.filter)
assert(frozen(view) == before)
print("book_state_spec: pure view transitions passed")
