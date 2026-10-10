# Azeroth Ledger

A World of Warcraft: Forever development addon for tracking items across your characters. The Collection shows items found in bags, bank, or equipped gear. Confirmed gains stay separate from items already there on the first check.

The [completed plan](https://github.com/ernestasgr/azeroth-ledger/issues/1) links the decisions and staged build order. Release validation remains in progress.

Open the Ledger book with `/al`. Browse categories and places, search item names, switch account/character/realm views, and select an item to see its history. Discoveries show when an item version first appeared in your Collection. Found once means one confirmed gain with no earlier sighting. Historical only means the item was not found on complete checks of the selected characters' bags, bank, and gear.

The Journal shows recent gains, moves between your characters, and vendor sales, refunds, and buybacks, newest first. Select an entry to see who was involved and where the item came from. A purchase appears once as a gain. AddOns Settings → Azeroth Ledger controls how many recent entries to keep: gains default to 1,000 (0–5,000), transfers and vendor actions to 250 each (0–2,000). Zero keeps no recent entries in that category. Removing old Journal entries does not change Collection totals, dates, or sources.

Item tooltips show when an item was Seen, Looted, or Obtained, its confirmed total gains, current status, and known source. A newly discovered item shows a five-second toast. Items already there at the first check, moves between your characters, duplicate messages, and later gains of an existing item stay quiet. Native AddOns Settings → Azeroth Ledger has separate tooltip and toast controls; both default on and persist across reload. See [tooltip and toast validation](docs/validation/issue-25-presentation.md) for automated checks and pending client checks.

Select the book's warning or **Review item changes** to see gains the addon could not confirm. Search by item and filter by character or realm to read what happened and whether another check may help. Looking at an unconfirmed change never adds it to Total gained.

Character and realm filters show the latest checked quantities and focus item details on that view. A + means some bags, bank, or gear have older or missing checks. Use Character/Account (or Realm/Account) in the detail pane to compare that view with the account total. Item links let you compare versions, enchants, and gems. Icons load automatically from the client.

AddOns Settings → Azeroth Ledger includes an optional **Developer mode** setting. It shows internal item keys and recording details in item pages; it is off by default.

Use Ctrl+F to search, Up/Down to select items, Page Up/Page Down or the mouse wheel to browse results, and Tab/Shift+Tab then Enter to activate controls. Character, realm and place menus show named choices. Escape dismisses an open menu, then closes the book. Scale buttons fit the book to your screen. The [book preview](docs/validation/collection-redesign.md) shows the layout and interaction checks; [Collection validation](docs/validation/issue-23-collection.md) records semantic checks and pending in-client checks.

See [CONTEXT.md](CONTEXT.md) for the player-facing glossary. Client compatibility and saved data must be checked on the intended Forever release build.
