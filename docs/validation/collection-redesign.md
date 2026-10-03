# Collection book redesign, 0.7.1

The book uses a charcoal surface, restrained gold accents, item icons and rarity colors. A counted category sidebar leads into search, named scope menus, seven item rows and a persistent detail pane. Recorded quantities stay beside each item; the detail pane separates Recorded, Total gained and Initially Seen before showing scrollable history, sources, ownership checks and full links.

![Collection book preview](collection-redesign.png)

This preview renders the production Lua frame tree with sample records through the native-frame test port. Browser fonts and substitute icon glyphs approximate the layout; it is not a WoW screenshot. The client supplies its own fonts, item art and scroll bar.

## Automated evidence

Lua 5.1 syntax, all twelve behavior specs in independent runtimes, StyLua 2.5.2, LuaLS 3.19.1, package/load order and three Python installer tests pass locally on 2026-10-03. [Full verify passes](https://github.com/ernestasgr/azeroth-ledger/actions/runs/37113451669) for code commit `e59750c`, including Luacheck 1.2.0-1, which runs only in CI on this workstation.

The public UI replay covers search, category counts, named scope menus, mouse and keyboard paging, menu selection and dismissal, empty/loading states, full item details, small-screen fitting and immediate scale changes. Selecting a new item resets its detail scroll; refreshing the same item preserves it. Tab starts at browsing controls, and Clear filters updates both checkboxes. Query and companion replays verify that browsing makes no saved-data writes and retains conservative ownership and independent method/source facts.

Final review found that short menus painted beyond their bounds and mouse paging retained a hidden keyboard selection. Both are fixed: the background follows the menu height, and mouse/page-key navigation selects a visible choice. A failing-then-passing interaction replay covers short menus and accounts with ten additional characters. CI also identified two shadowed local names; the detail title now uses a distinct name.

## Intended-client evidence

Native app control is unavailable in this environment. In-client appearance, keyboard behavior and the genuine AzerothLedgerCollection WoWUnit group remain pending. Record build, locale, test result and Lua errors when exercising 0.7.1. Use `/reload` then `/al`, inspect short and long item histories, open scope/place menus, change filters, and check the book at a small viewport and a different UI scale.

Before installation, the account SavedVariables validate as healthy schema 2 with 50 readable Collection records, and the client flavor is `wow_classic_beta`. After verify passed, both prescribed installer commands succeeded against `C:/Program Files (x86)/World of Warcraft/_classic_beta_`: all 19 TOC-listed addon/companion files match the workspace SHA-256 hashes. Twelve before/after comparisons confirm that SavedVariables and WoWUnit files are unchanged. Version 0.7.1 is installed; these checks do not establish an in-client pass.

Standards and Spec reviews against user-approved baseline `a54ea80` report no remaining actionable implementation findings after the menu fixes. The original semantic validation matrix remains in [issue-23-collection.md](issue-23-collection.md).
