# Repeated-item histories (#60)

Journal assembly now indexes acquisition roots instead of searching lifetime gains
for each retained row. Journal preparation reads detached item descriptions and
shares one description and metadata result per item within its completed query.
Quantity-only scans share unchanged internal gain histories. Ordinary acquisitions
stage detached contributions for the current root, update saved arrays with sparse
undo information, then publish runtime gains and indexes only after saving. Retained
gain history uses sorted insertion rather than sorting every row again. Public
queries never expose mutable saved contributions. Indexed actor totals also avoid
traversing lifetime gains to prepare mail/trade baselines.

Healthy schema-2 observations retain the first positive observation per character
and the latest dated observation per character/storage area, in their original order.
For valid out-of-order arrays, the last array observation also survives so existing
scan reconciliation and dated Last Seen projections both keep their measured facts.
This preserves first-check units, current quantities, and dated last-known facts.
Existing character first/latest dates and area completeness dates remain separate.
Compaction is persisted when a record is next changed, after validation; opening
data alone does not rewrite it. The schema remains 2. Unsupported schemas remain
read-only and damaged records keep their existing diagnostics.

All gain contributions, correction IDs, refund references, full links, source
identities, discovery dates, and unresolved summaries remain permanent. They are
not merged into approximate totals: an old pruned gain can still be corrected,
and a pruned vendor purchase can still be refunded. Pruning activity never rebuilds
it from those contributions. Startup validation, historical source corrections,
refund lookup and serialization still scale with permanent contributions. Ordinary
acquisition settlement is bounded by active evidence and retained activity rather
than lifetime history. Source-share edits refresh only the current root and the
positions shifted by its removal; historical corrections retain full validation.

Collection record copying, gain/place traversal, and selected-item inspection now
yield within a single item. Details cache by item, character/realm scope and store
revision, so paging the same item's activity reuses its completed inspection.
Item-data refresh still coalesces and preserves the page. Native tooltips read
indexed methods/source facts and bounded storage descriptions instead of inspecting
all gains synchronously. Lua 5.1 cannot yield
inside a generic-for iterator, so cooperative Collection copying calls its cursor
in a regular while loop.

## Host measurements, 10 October 2026

Windows AMD64, AMD Family 25 Model 97, Python 3.12.14, Lupa Lua 5.1. The clock has
approximately 1 ms resolution; zero means below that resolution. These are
synthetic host results, not Forever timings or an established client budget.
The baseline is `a6f7b8d`, the main revision at the start of this work.

| Fixture | Measurement | Before | After |
| --- | --- | ---: | ---: |
| 1 item, 100 gains, 100 retained | Journal assembly | 4 ms | <1 ms |
| 1 item, 5,000 gains, 1,000 retained | Journal assembly | 1,640 ms | 3 ms |
| Same | Book Journal query | 17,351 ms | 17 ms |
| Same | Maximum book-query step | 41 ms | 2 ms |
| Same | Changed-quantity scan instructions | 1,176,000 | 2,000 |
| 1 item, 5,000 gains, 5,000 retained | Journal assembly | 8,435 ms | 18 ms |
| Same | Book Journal query | memory exhaustion; stopped | 96 ms |
| Same | Stored observations after scan | 5,001 | 2 |
| 3 items, 50,000 gains each, zero retained gains | Scan instructions | 35,243,000 | 4,000 |
| Same | Maximum Collection-query step | 86 ms | 2 ms |
| Same | Stored observations after scan | 150,003 | 6 |
| 1 item, 5,000 gains, maximum retained gains | Confirmed craft scan instructions | 2,017,000 | 130,000 |
| Same | Tooltip instructions | 1,186,000 | about 1,000 |
| 3 items, 50,000 gains each, zero retained gains | Confirmed craft scan instructions | 15,665,000 | 4,000 |
| Same | Tooltip instructions | 11,849,000 | about 1,000 |

The three-item measurement also retains three vendor and three transfer rows;
the behavior regression separately prunes all three categories to zero and reopens
the data. The baseline maximum-retention book run exhausted host memory; it was
stopped and omitted from the completed baseline profiler run. There is no invented
baseline time for that case.

The compact Lua serialization surrogate for 5,000 gains/1,000 retained shrank from
1,782,786 to 1,285,091 bytes (serialization 75 to 49 ms; parse 22 to 16 ms). For
three 50,000-gain items it shrank from 51,865,739 to 36,509,642 bytes (serialization
5,205 to 4,740 ms; parse 691 to 498 ms). These surrogate measurements vary
between runs and do not characterize the native writer. Gain references still dominate persistent growth.

Reproduce with Python and Lupa:

```text
python tools/profile_repeated.py --lua-path .tools/lupa --baseline a6f7b8d --output docs/validation/issue-60-before.json
python tools/profile_repeated.py --lua-path .tools/lupa --output docs/validation/issue-60-after.json
python tools/profile_ledger.py --lua-path .tools/lupa --output distinct-host.json
```

The JSON reports are checked in beside this document. The existing 10,000-item
host fixture still retains 20,000 links, 20,000 lifetime gained units and 20,000
nonzero item/source pairs; its maximum cooperative query step was 2 ms, maximum
book frame 8 ms and cached paging below 1 ms in this run.

## Validation

The repeated-item scan guard first failed at 1,176,000 instructions and now passes
the existing 250,000 ceiling. Maximum Journal lookup is guarded below 4,000,000
instructions (measured 1,999,000 for 5,002 activities). Coverage also exercises
three long-lived items, maximum/zero retention, first/latest dates, exact method
and source totals, independent public copies, old and retained corrections,
cooperative Collection/details, cached visible paging, background metadata refresh,
and failed-save rollback/retry for crafts, vendor purchases, mail and loot, including
receipts arriving after the quantity scan. Confirmed craft settlement at maximum
retention uses about 130,000 instructions with either 5,000 or 50,000 prior gains;
tooltip reads stay around 1,000. Those paths now share the 250,000 guard.
Existing refund, unresolved-evidence, discovery and
dated-bank regressions remain in the full suite.

Local checks: all 50 Lua files compile as Lua 5.1; all 21 behavior test files pass;
StyLua 2.5.2, Luacheck 1.2.0, LuaLS diagnostics, package validation and all three
Python installer tests pass. Windows sandbox path-resolution restrictions required
LuaLS and installer tests to run outside the sandbox. The Forever beta account
data validates as healthy schema 2. Installed TOC files and native Bindings.xml
hashes match; SavedVariables and WoWUnit hashes remain unchanged.

## Review

Standards: no remaining actionable findings. Spec: no remaining actionable
production findings; native validation below remains pending. Both reviewers
independently reran all 21 behavior files. Their fixes added timestamp-order
preservation, ordinary acquisition and tooltip cost guards, typed descriptions,
and complete action-state rollback/retry alongside sparse gain rollback.

## Native validation pending

No native WoW interaction is available in this environment. Genuine
`AzerothLedgerPerformance` and `AzerothLedgerCollection` results, reload/cold-start
behavior, build/interface/locale, hardware, Lua errors, actual SavedVariables file
growth, native restore and logout/save times remain pending. Keep the PR draft.

With the companion enabled, `/alperf` uses the distinct-item fixture;
`/alperf repeated` uses three items with 50,000 gains each and maximum retained
gains; `/alperf repeated zero` prunes all Journal categories. These use synthetic
stores and leave production SavedVariables untouched. Use `/al profile` for
fixture-load, Journal, changed-scan, cooperative query, detail and book-frame
timings, including a confirmed craft settlement and native tooltip projection.
Synthetic fixture construction and validation may pause the client and
are setup work, separate from the normal scan/query measurements.

Measure actual SavedVariables growth/load/save only with an isolated test profile
and a recoverable backup. Record native file bytes and cold-login, reload and
logout times for both fixtures; query totals, sources, links, dated storage,
refund/correction references and zero activity after reopening. Return to
`/al collection` before measuring real inventory events.
