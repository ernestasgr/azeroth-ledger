# Store split

`Schema.lua` was 5,282 lines. Most of it was `Schema.open`, one ~3,650-line
closure: validation, the record index, the journal, evidence correlation,
loot, mail/trade, vendor, quest/reward, and scan settlement, all sharing closure
state. It is now split into single-purpose files. The public `store` API keeps
every method name, argument, and result. Evidence rules, the SavedVariables
layout, and `CURRENT_SCHEMA = 2` are unchanged.

## Modules

Load order follows the TOC and `tools/package.py`:

| File | Owns |
| --- | --- |
| `SchemaValidate.lua` | Pure `valid*` checks, copy helpers, source identity and grouping, display/color/book/retention option tables, `validJournal`, `sameSource`. Reads and writes no store. |
| `StoreKernel.lua` | `StoreKernel.open(raw, save)`: saved-data checks at open, `raw`, revision counter, runtime index (scope, actor, gain, and tooltip indexes), journal sequencing, and the single `saveFields` commit path. Returns the narrow interface the domains use. |
| `StorePreferences.lua` | `book`, `setBook`, `display`, `setDisplay`, `displayRevision`, `takeDiscoveries` |
| `StoreJournal.lua` | `retention`, `setRetention`, `journal` |
| `StoreEvidence.lua` | Unresolved evidence, correlation expiry (`expireEvidence`, `endCorrelation`), `visitEvidence`, `correctGain`, the 256-candidate limit, and `guardCandidates`, which wraps the seven candidate commands |
| `StoreRecords.lua` | `diagnostic`, `marker`, `environment`, `list`, `count`, `revision`, `cursor`, `find`, `describe`, `tooltipFacts`, `breakdown`, `area`, `characters`, `setMarker`, `setEnvironment` |
| `StoreLoot.lua` | `lootOpen`, `lootSourceProof`, `lootReceipt`, `lootClose`; returns `activeSession` and `award` for the scan |
| `StoreExchange.lua` | Mail/trade intents, confirmation, cancellation, `mailProgress`; returns `state` and `settle` |
| `StoreVendor.lua` | Vendor actions and receipts; returns `state` and `settle` |
| `StoreReward.lua` | Quest preparation and turn-in, reward and craft receipts; returns `sessions`, `award`, `choiceIsProven` |
| `StoreScan.lua` | `scan`: observations, identity evidence, and settlement of the other domains |
| `Schema.lua` | The public `addon.Schema` facade. `Schema.open` builds the kernel, installs each domain on one method table, runs the reload correlation boundary, then installs the candidate guards last. |

The kernel reassigns `raw` on every save, so domains read `kernel.raw()` at each
point of use rather than holding a snapshot. The validated record table
(`kernel.valid`) is shared by reference; domains still replace entries after
each save, as before. Helpers that do not need store state (`sessionIsLive`,
`attributeLoot`, `lootSlots`, `pruneExchange`, `vendorResult`,
`linkedVendorGain`, `choiceIsProven`, `retain`, `validCandidate`, the gain-plan
helpers, and quantity helpers) are now module-level pure functions.

Each domain body was copied by line range from the old closure. The only rewrites
were `raw` to `kernel.raw()`, reads of kernel-owned index state through the
kernel interface, and generated imports from `SchemaValidate`. Tests that loaded
`Schema` now load the twelve store files in TOC order. `tools/profile_repeated.py`
reads the store file list from the TOC at `--baseline`, so it still accepts refs
from before the split.

## Local validation

On this workstation (Python 3.12 with Lupa Lua 5.1, StyLua 2.5.2, Luacheck
1.2.0, LuaLS 3.19.1), every check in `.github/workflows/verify.yml` passed:

- Lua 5.1 syntax for all 79 addon, companion, and test files.
- All 27 `tests/*.lua` behavior specs, including `event_routing_spec` from the
  merged event-sessions split (#78). Their assertions did not change; only the
  source lists did.
- StyLua `--check` (LF staging), Luacheck, and LuaLS: no diagnostics.
- `tools/package.py` load order and archive contents, plus the installer unit
  tests (8 passed).

A one-off differential replay ran each spec against both versions at once. Every
`Schema.open` opened the original monolith (from `adb203d`) and the split store
on copies of the same input. Each public call ran on both, and the replay
compared results, callback arguments, cursor rows, and every saved payload, in
order. Across 26 specs that was 387 opens, about 80,000 store calls, and about
4,650 saves, with no differences. This was re-run after merging #78. Two specs passed only when both stores got
identically built copies, because the cursor's record order follows table
iteration order. Two others passed only when the original got the spec's own
table, because they check its identity. `performance_spec` was left out because
its instruction budget cannot cover two stores; on its own, it passes against
the split store.

## Local install

The account SavedVariables (`414268473#1`) were schema 2 before installation.
`.flavor.info` reports `wow_classic_beta`. `tools/install_local.py` copied the
54 TOC-listed and auto-loaded files for `AzerothLedger` and
`AzerothLedger_Tests`. A separate `--verify-only` run matched every installed
hash. WoWUnit was not touched. No WoW client was running.

## Pending Forever checks

This refactor adds files to the TOC, so the client must be restarted, not just
reloaded. The installed executable reports `1.60.1.70450`; the saved environment
records `enUS`. No in-client run was done. After a restart, record
`GetBuildInfo()`, the locale, WoWUnit results, and any Lua errors for:

- `AzerothLedgerCollection`, `AzerothLedgerExchange`, `AzerothLedgerJournal`,
  `AzerothLedgerPerformance`, `AzerothLedgerPresentation`, and
  `AzerothLedgerVendor`.
- A loot, quest-reward, vendor, and mail cycle, then `/reload`, to confirm that
  records and journal entries persist as before.
