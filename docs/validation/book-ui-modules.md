# Book UI modules

The Collection window (`Book.lua`, previously 1,648 lines) is now split by
responsibility. Behavior, wording, layout, Tab order, and saved preferences are
unchanged. Load order: `BookWidgets`, `BookQuery`, `BookState`, `BookFrame`,
`BookRender`, `Book`.

## Modules

- `BookState` holds the view state: tab and filters, paging, selection (item,
  Journal entry, evidence), the history return point, saved-link preview index,
  collapsed detail sections, the open menu's page and choice, and window
  placement and scale. Each transition returns a new view and does not change
  its input. `reconcile` fits a view to a completed query result, choosing the
  Journal entry, a valid page, and which item's details to show. `place` clamps
  scale and offset to the screen and keeps the saved scale. The module touches
  no frames.
- `BookFrame` builds the window: layout, anchors, the sidebar, tabs, search,
  filters, list rows, gallery cards, the detail panel, the menu, help, and
  scripts. Controls report input through an actions table and hold no view state.
  `ItemRowMixin` (list rows and gallery cards) and `DetailRowMixin` (detail rows
  by kind: note, pair, date, section, link, action, evidence line) give the
  reused row widgets their layout. `BookWidgets.mixin` follows the client's
  `Mixin` contract. It is local so loading and the native-frame test port do not
  depend on a FrameXML global.
- `BookRender` draws query results into the widgets. Pure helpers build row
  models, empty/context/footnote/warning text, and detail-row lists. Detail
  actions are data (`{ "history", key }`, `{ "sequence", n }`); the controller
  runs them. Drawing steps the cooperative query but changes no filters.
- `Book` is the controller. It turns input into state transitions, then draws.
  The public API (`open`, `openDiscovery`, `toggle`, `refresh`, `save`, `reset`,
  `setDeveloperMode`, `setScale`, `applyPreferences`) is unchanged.

`Work.measure` still wraps "Collection open" and every "Book frame" draw. The
`OnUpdate` redraw still runs only while the query or the details are pending.

## Local validation (17 October 2026)

- Lua 5.1 syntax (lupa 2.5) for every addon, companion, and test file.
- All 27 `tests/*.lua` behavior tests passed. These include the existing
  `book_ui`, `gallery_ui`, `book_preferences`, `settings`, `presentation`,
  `performance`, and `wowunit_replay` specs, which replay the
  `AzerothLedgerCollection` and Presentation groups. The new `book_state_spec`
  checks that transitions never change their input, plus history round trips,
  scope choices, date windows, reconcile, section collapse, menu windows, and
  placement.
- A mutation check confirmed that `book_ui_spec` fails when detail wording
  changes.
- StyLua 2.5.2 (on an LF copy of the CRLF checkout), Luacheck 1.2.0 (60 files,
  0 warnings), LuaLS 3.19.1 (no problems).
- `tools/package.py` manifest and load order, and the installer unit tests (8).

## Local install

The account SavedVariables were healthy schema 2 (7 records) before
installation. `install_local.py` copied the TOC-listed files to the Forever beta
(`wow_classic_beta`, client file version `1.60.1.70450`). A separate
`--verify-only` run matched all 35 installed hashes. SavedVariables and WoWUnit
hashes did not change (21 files).

## Pending in-client checks

No WoW client was running, so nothing here was tested in the client and no
visual comparison was made. When validating, record `GetBuildInfo()`, the locale,
WoWUnit results, and any Lua errors for:

- `AzerothLedgerCollection` and Presentation WoWUnit groups after `/reload`.
- Switching tabs, filters, search, and paging (wheel, PageUp/PageDown), and
  arrow-key selection while a large query loads.
- Detail section collapse, linked Journal entries, item history and Back to
  Collection, gallery saved-link preview, and the evidence review view.
- Moving and resizing the window, plus persistence after reload.
- A visual check that layout matches the previous build.
