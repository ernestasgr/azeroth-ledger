# Large Collection performance (#27)

The addon coalesces inventory bursts with a next-frame timer, reads changed containers, and assembles complete area snapshots from checked containers. Missing or unreadable containers still make the area incomplete. Equipment snapshots share the bag check time so delayed quest rewards can settle after equipping. Item-data events retry unreadable storage rather than rescanning readable storage.

The store updates changed records and uses runtime indexes for held items and known characters. Loot and quest baselines capture currently held items eagerly and previously unheld items before their first change. Validation and index rebuilding happen once when opening saved data. Journal pruning never removes Collection records, full links, permanent contributions, or source totals.

The shared Work module builds Collection, search, metadata, Journal, and sort results in resumable steps with a starting budget of 2 ms. Paging reuses completed results and background refreshes preserve the current page. New item-data events coalesce while a query is running; filters cancel the old query. The UI shows a loading message while preparing results. One indivisible record operation and rendering the visible page can exceed the work budget; timings report the actual maximum. Startup validation remains synchronous and is measured separately.

## Host evidence

Run `python tools/profile_ledger.py --lua-path .tools/lupa --output docs/validation/issue-27-host.json` with Python 3.12 and the installed Lupa Lua 5.1 build. The JSON records this workstation's host replay, using native-frame test ports and synthetic metadata. It does not measure the WoW client or its SavedVariables writer.

The fixture has 10,000 entries, 5,000 gain rows, 2,000 transfer rows, and 2,000 vendor rows. It retains 20,000 exact full links, 20,000 nonzero item/source pairs including initial stock, and 20,000 lifetime gained units. On this run: the Collection loading interface opened in 7 ms; maximum budgeted query step 2 ms; maximum book frame 4 ms; maximum storage update 1 ms; store validation/open 201 ms. Preparing the usable results took 167 work frames and 255 ms CPU time in the host replay. The 7 ms interface-open measurement excludes that preparation time. Cached keyboard paging measured below the host clock's 1 ms resolution.

The fixture serialized to an 8,253,855-byte compact Lua table surrogate: 1,022 ms serialization and 235 ms parsing. These timings characterize the host serializer only. The test parses it again and verifies all 10,000 entries remain readable. Real SavedVariables size, save time, and restore time must still be measured in the client.

`tests/performance_spec.lua` first failed because a normal scan used 5,954,000 Lua instructions. The changed scan passes a 250,000-instruction ceiling at the same fixture and maximum Journal limits. The test also checks budgeted opening, deterministic sorting, and permanent links/source/lifetime totals after all Journal categories are pruned and the store is reopened. `tests/loot_event_spec.lua` checks an event burst waits, coalesces, and reads only the changed container. `AzerothLedgerPerformance` provides a genuine WoWUnit stress group; its host replay is separate from its in-client result.

All 43 Lua files passed Lua 5.1 syntax checks. All 17 behavior test files, StyLua 2.5.2, Luacheck 1.2.0 (zero warnings/errors), LuaLS 3.19.1 (zero diagnostics), package validation, and three Python installer tests passed locally. The account SavedVariables were checked read-only: healthy schema 2, 62 readable records. The installer confirmed the Forever beta flavor, copied only manifest-listed addon and companion files, and verified every installed hash. SavedVariables and WoWUnit hashes were unchanged.

## Standards review

No remaining documented-standard violations or code-smell findings. Review fixes preserved navigation during loading, moved shared work utilities out of Collection, factored container-cache helpers, and simplified the loading text.

## Spec review

One partial requirement remains: target-client measurements and native WoWUnit checks below. The review also found a lazy quest-baseline regression; a corrected one-cloak equipment fixture reproduced the lost gain before the fix and now verifies zero initial units, one quest unit gained, and one Recorded unit. Sparse save-callback failures restore the previous record map and leave the public query/index revision unchanged.

Review totals: Standards 0; Spec 1 partial requirement, target-client validation.

## Target-client checks: pending

No native client interaction is available in this environment. No target hardware budget is revised based on host measurements. Keep the initial 2 ms work budget and Collection-open target below 250 ms until measured client evidence supports a change.

With the development companion enabled, `/alperf` opens the anonymous 10,000-entry fixture without changing production SavedVariables. Use `/al profile` to report fixture load, Collection open, query steps, book frames, inventory updates, and individual event-handler timings. The viewer remains synthetic: return to `/al collection` before measuring actual loot, equipment, bag, and bank events. Synthetic construction is deliberate test setup and may stall; it is not a normal event.

Record the current build, interface, locale, hardware, addon revision, genuine `AzerothLedgerPerformance` and `AzerothLedgerCollection` results, and Lua errors. Measure first open and subsequent open, keyboard/mouse paging, searches, Gallery and Journal, uncached item callbacks, and repeated bag/equipment/bank events. Check whether the 2 ms work and 250 ms open targets pass; optimize misses or explicitly revise them using those measurements.

For actual SavedVariables measurements, use an isolated test account/profile with the synthetic fixture; record native file bytes, reload/cold-login restore time, logout/save time, and item/source-pair growth. Preserve account data and redact real player names, GUIDs, and account paths from shared reports. Reopen the saved fixture and query distinct links, source totals, and lifetime counts after pruning. Native writer timings and these in-client checks remain pending.
