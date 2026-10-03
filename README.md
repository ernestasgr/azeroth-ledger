# Azeroth Ledger

A World of Warcraft: Forever development addon for tracking items across your characters. Its Collection shows items you have seen; recorded item activity keeps loot, purchases, transfers, and vendor actions separate from starting stock.

The [completed plan](https://github.com/ernestasgr/azeroth-ledger/issues/1) links the decisions and staged build order. Release validation remains in progress.

Open the native Ledger book with `/al`. Browse categories and recorded places, search names or variant keys, switch account/character/realm views, and select an item for permanent history. Recent discoveries use first-seen facts separately from the Journal. Found once uses account-wide gains; Historical only requires complete relevant storage checks.

Use Ctrl+F to search, Up/Down to select items, Page Up/Page Down or the mouse wheel to browse results, and Tab/Shift+Tab then Enter to activate controls. Character, realm and place menus show named choices. Escape dismisses an open menu, then closes the book. Scale buttons fit the book to your screen. The [book preview](docs/validation/collection-redesign.md) shows the layout and interaction checks; [Collection validation](docs/validation/issue-23-collection.md) records semantic checks and pending in-client checks.

See [CONTEXT.md](CONTEXT.md) for the plain-language glossary. Client compatibility and saved data must be checked on the intended Forever release build.
