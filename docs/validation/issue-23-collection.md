# Issue #23: native Collection book

The current book is version 0.7.2. Its visual and interaction redesign is documented in [collection-redesign.md](collection-redesign.md); the 0.7.0 evidence below records the original implementation and installation.

Version 0.7.0 replaces the scrolling Collection dump with navigation, twelve searchable item rows per page, and persistent details. Categories use numeric item classes and quality from the installed client's `C_Item.GetItemInfo` declaration; missing, failed or delayed metadata remains Unknown and searchable. Item-data events refresh the visible projection without saving metadata or changing quantities.

The query reads permanent Collection records. Account discovery count counts keys, independently of units, filtered results and retained activity rows. The separate Recent discoveries view orders first-seen facts; character and realm views use their earliest selected first-seen date. Ties use name and variant key. All full links remain in details, including changed enchants on the same intrinsic variant. Details expose account totals and independent method/source buckets, known dates, strongest recorded evidence, and dated storage checks for selected characters. Offline positive observations remain Unknown for current ownership.

Place navigation contains only confirmed gain locations, never scan locations. New gain contexts capture zone/dungeon classification through the client port using `GetRealZoneText` and `IsInInstance`; only party/raid instances are classified as dungeons. Older named locations without classification are labelled Recorded place. No static drop lists or inferred dungeon sources are added. Scope filters also restrict the gain evidence behind place groups.

## Automated checks, 2026-10-02

The first query test failed with `attempt to call field 'query' (a nil value)`. Query and native-frame port replay now pass for 400 starting units, later two-unit loot with unknown source, two variants, changed enchant, search/categories, character/realm scope, stale alt, Historical only, account-wide Found once, purchase/refund, recorded dungeon evidence, pruning to zero, and separate discovery versus quantity counts. Browsing makes no SavedVariables writes. The native-frame replay additionally checks paging, persistent details, empty/loading states, keyboard controls and scaling.

Lua 5.1 syntax, all twelve `tests/*.lua` behavior files, StyLua 2.5.2, LuaLS 3.19.1, package/load order and three Python installer tests pass locally. Each behavior file runs in an independent Lua runtime, matching CI's separate `lua` invocations; running all adapter fixtures in one reused runtime leaks game globals between fixtures. [The complete verify run](https://github.com/ernestasgr/azeroth-ledger/actions/runs/37056690849) passes for code commit `f4d7176`, including Luacheck 1.2.0-1, which ran only in CI. Its first run found an unused argument in the native-frame test helper; the corrected replay and rerun pass.

The new query cases are included in genuine `AzerothLedgerCollection` WoWUnit registration and in the host companion replay. Host execution does not establish an in-client pass.

The standards and specification reviews compare the implementation with starting commit `a54ea80`. The specification review identified stale filter labels after Reset filters; the labels now derive from the filter projection, and a failing-then-passing frame replay covers both toggles. Both reviews report no remaining implementation blockers. Live acceptance is still pending.

Before installation, the account SavedVariables validate as healthy schema 2 with 34 readable records, and the client flavor is `wow_classic_beta`. After verify passed, both prescribed installer commands succeeded against `C:/Program Files (x86)/World of Warcraft/_classic_beta_`: all 18 TOC-listed addon and test-companion files match the workspace SHA-256 hashes. Twelve before/after SHA-256 comparisons also confirm the SavedVariables files and WoWUnit files are unchanged. Version 0.7.0 is installed. These file checks do not establish an in-client pass.

## Live validation

Native app control is unavailable in this environment. The current build, locale, in-client test result and Lua errors remain pending for version 0.7.0.

| Check | Build | Locale | Result | Lua errors |
| --- | --- | --- | --- | --- |
| `AzerothLedgerCollection` genuine WoWUnit group | Pending | Pending | Unrun in client | Pending |
| `/al` search, categories, places and scoped views | Pending | Pending | Unrun in client | Pending |
| Persistent details, full links and empty/loading states | Pending | Pending | Unrun in client | Pending |
| Keyboard access and screen/UI scaling | Pending | Pending | Unrun in client | Pending |
| Real outdoor/dungeon gain versus later scan location | Pending | Pending | Unrun in client | Pending |
| Reload and complete exit/relaunch | Pending | Pending | Unrun in client | Pending |

After installation, enable Lua errors, record `GetBuildInfo()` and `GetLocale()`, run `AzerothLedgerCollection`, then exercise the book. Use an item with initial stock plus loot, two sword variants, a changed enchant, a stale alt and a refunded purchase. Verify the same Collection and discovery dates across `/reload` and a complete process restart. Record the exact test result and any errors; file hashes and host replays are separate evidence.
