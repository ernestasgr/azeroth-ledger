# Azeroth Ledger

A World of Warcraft: Forever development addon for tracking items across your characters. Its Collection shows items you have seen; recorded item activity keeps loot, purchases, transfers, and vendor actions separate from starting stock.

The [completed plan](https://github.com/ernestasgr/azeroth-ledger/issues/1) links the decisions and staged build order. Release validation remains in progress.

Open the native Ledger book with `/al`. Browse categories and recorded places, search names or variant keys, switch account/character/realm views, and select an item for permanent history. Recent discoveries use first-seen facts separately from the Journal. Found once uses account-wide gains; Historical only requires complete relevant storage checks.

The Journal tab shows account-wide recent gains, alt transfers, and vendor sales, refunds and buybacks, newest first. Select an activity to see its known actors and evidence alongside the item's lifetime facts. A purchase appears once as a gain. AddOns Settings → Azeroth Ledger controls each history separately: gains default to 1,000 (0–5,000), transfers and vendor actions to 250 each (0–2,000). Zero keeps no recent rows in that category. Reducing a limit removes the oldest rows permanently; increasing it records future activity. Collection dates, units, source totals and refund references survive pruning.

Item tooltips show Seen, Looted or Obtained facts, net confirmed gains, ownership and source from the account Collection. A newly proven account discovery shows a five-second toast. Initial stock, alt moves, duplicate signals and later gains of an existing item stay quiet. Native AddOns Settings → Azeroth Ledger has separate tooltip and toast controls; both default on and persist across reload. See [tooltip and toast validation](docs/validation/issue-25-presentation.md) for automated evidence and pending client checks.

Character and realm filters show dated checked quantities and default item details to that scope. A + marks older or unchecked storage. Use Character/Account (or Realm/Account) in the detail pane to compare checked units and confirmed gains with lifetime account Recorded totals. Item links group identical versions; Show all recorded links exposes the preserved originals. Icons load automatically from the client.

Use Ctrl+F to search, Up/Down to select items, Page Up/Page Down or the mouse wheel to browse results, and Tab/Shift+Tab then Enter to activate controls. Character, realm and place menus show named choices. Escape dismisses an open menu, then closes the book. Scale buttons fit the book to your screen. The [book preview](docs/validation/collection-redesign.md) shows the layout and interaction checks; [Collection validation](docs/validation/issue-23-collection.md) records semantic checks and pending in-client checks.

See [CONTEXT.md](CONTEXT.md) for the plain-language glossary. Client compatibility and saved data must be checked on the intended Forever release build.
