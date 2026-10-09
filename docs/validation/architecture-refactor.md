# Architecture refactor

The Collection book now draws results from a query session. Last seen readers
share one projection of storage facts, and the inventory adapter owns scan
coordination. Item evidence rules and the SavedVariables schema stay unchanged.

## Modules and interfaces

- `BookQuery.new` creates a session whose `step` returns a completed, current
  result or pending work. `metadataChanged` invalidates item data. The session
  owns filter snapshots, store identity, store revisions, deferred invalidation,
  and Journal result assembly. Work still uses the existing frame budgets and
  cooperative sort. An invalidated running query finishes before replacement;
  its rows are never published. Changes of filter, view, character, or store
  replace obsolete work immediately.
- `LastSeen.project` combines selected characters, complete or partial storage
  checks, observations, check dates, and offline uncertainty. Collection list,
  detail, and text readers share these facts; tooltips use the same details.
  Ownership classification is separate from displayed wording. Historical
  filtering and book colors use classification. Checked units still refer to
  dated checks, and do not prove current ownership on an offline character.
- `Inventory.new` creates the client adapter. `check` establishes an immediate
  action baseline or checks all storage. `event` handles dirty bags or equipped
  slots, timer coalescing, bank access, and unreadable-item retries. Comparable
  bags and equipped checks share a date. Scan.reader retains selective caches;
  normalized snapshots go to the existing ledger store, the only writer.

These seams concentrate lifecycle, storage-truth, and scan-order knowledge that
previously spread through drawing, detail assembly, and event handling. They do
not introduce a module framework or a new persistence adapter.

## Local validation

- Lua 5.1 syntax for every addon, companion, and test file.
- All `tests/*.lua` behavior tests, including WoWUnit group replays.
- StyLua 2.5.2, Luacheck 1.2.0, and LuaLS 3.19.1 diagnostics.
- Package manifest/load order validation and installer behavior tests.
- The 10,000-entry selective-scan instruction regression, cooperative loading,
  cached paging, and permanent-fact retention regressions.
- `tests/architecture_spec.lua`: store changes and item-data changes during
  queries, cached metadata invalidation, filter/view/store replacement, Journal
  result indexes, agreement across Last seen readers, partial/offline/empty
  scopes, mixed bag/gear bursts, bank closure during queued work, unreadable
  retries, and immediate action baselines alongside queued work.
- A separate read-only comparison with the previous detail projection matched
  396 scan/scope cases. This supplements the committed regressions.

The account SavedVariables were checked as healthy schema 2 before installation.
The installer copied the 30 TOC-listed files for the addon and its companion to
the Forever beta; a separate `--verify-only` run matched every installed hash.
Protected SavedVariables and WoWUnit hashes were unchanged (15 files).

## Pending Forever checks

Local replays and installed-file hashes do not establish native-client behavior.
The available executable reports `1.60.1.70205`; the existing saved environment
records `enUS`. No WoW client was running during the local checks. Record a fresh
`GetBuildInfo()` result, locale, WoWUnit results, and Lua errors when validating:

- `AzerothLedgerCollection`, `AzerothLedgerPerformance`, and the reward, loot,
  vendor, exchange, Journal, and presentation groups.
- Search or view changes while a large query is loading; item-data arrivals and
  item gains during that work; completed-query paging and retained selection.
- Bag and gear changes in one burst, opening or closing the bank around queued
  work, delayed quest rewards moved into gear, and unreadable items becoming
  readable.
- Reload persistence and consistent list, details, and tooltip ownership text.

## Main refresh: 9 October 2026

Merged main at `e8bab8a` (mailbox fix #61) into the architecture branch.
`Inventory` still owns scan coordination. Its optional completion callback runs
once after each full queued flush, letting Main update mailbox progress and clear
overlap protection at the same point as the mailbox fix. Immediate action
baselines do not invoke the callback. `MAIL_SHOW` retains its explicit progress
update after the bag baseline. The mailbox fixture now loads `Inventory` and
`LastSeen` in production order.

The architecture regression covers callback ordering and coalescing, including
synchronous flushes. A production mailbox regression verifies that overlapping
takes before a deferred flush remain unresolved and that a fresh take after the
flush can count its uniquely proven gain.

Local checks passed: Lua 5.1 syntax for 48 files, all 19 Lua behavior suites
(including the 10,000-entry performance regression and WoWUnit replays), StyLua
2.5.2, Luacheck 1.2.0, LuaLS 3.19.1, package/load order validation, and all three
Python installer tests. Formatting was checked on an LF copy equivalent to the
CI checkout.

One account save opened as healthy schema 2 before installation. All 30
TOC-listed addon and companion files were installed and separately hash-verified
in Forever beta. The 15 protected SavedVariables and WoWUnit file hashes remained
unchanged. Native-client checks, fresh build/locale, WoWUnit results, and Lua
errors remain pending; this refresh was validated with host tests and installed
file hashes.
