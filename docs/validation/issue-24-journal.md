# Issue #24: Journal and independent retention

The Journal tab merges account-wide gains, alt transfers and vendor sales, refunds and buybacks, newest first by recorded time and a persisted account sequence. Purchases appear once in gain history. Selecting a row shows quantity, observed actors and evidence with the item's permanent Collection details.

AddOns Settings → Azeroth Ledger uses the installed Forever export's `Settings.RegisterProxySetting` and native sliders. Gain history defaults to 1,000 (0–5,000); transfers and vendor actions default to 250 each (0–2,000). Zero disables future history retention for that category. Raising a limit does not restore pruned rows. Lifetime contributions, corrections, refund links, discovery dates and breakdowns stay separate from the retained rows.

## Automated evidence

- Lua 5.1 syntax and every `tests/*.lua` spec passed locally, with each spec in a separate process.
- `AzerothLedgerJournal` WoWUnit cases passed under the host replay runner: purchase has one gain row; limits are independent; tied times follow sequence; persisted zero survives reopening the store; pruning preserves dates and breakdowns; source corrections do not resurrect rows; a refund still reverses its purchase after gain pruning; transfer pruning keeps lifetime stock.
- Native frame replay passed for Journal navigation, empty state, account-wide activity, search, activity evidence, settings refresh and returning to Collection.
- Settings callback replay passed for all three controls, ranges, defaults, explicit zero, store persistence and missing API handling.
- StyLua, LuaLS, package order/contents and installer behavior tests passed locally. Luacheck requires the PR's pinned CI toolchain on this workstation.
- The installed account SavedVariables were checked as healthy schema 2 before installation. This change adds optional history references and retention settings without changing the schema version or removing permanent records.

Host replay and installed-file verification do not establish in-client behavior.

## In-client checks: pending

Native client control is unavailable in this environment. No new build, locale, genuine WoWUnit result or Lua-error result is claimed.

1. Reload Forever and record `/al status` build, interface, locale and revision 0.8.0. Run genuine `AzerothLedgerJournal`, `AzerothLedgerCollection`, `AzerothLedgerVendor` and `AzerothLedgerExchange` WoWUnit groups; record pass/fail and Lua errors.
2. Make a purchase, sale and alt transfer. Open `/al`, select Journal, confirm quantity, known actors, evidence and chronological ties; the purchase must appear only once.
3. Open AddOns Settings → Azeroth Ledger. Check defaults and maximums. Reduce each limit separately, including zero, and compare Collection discovery dates, Recorded units, method totals and source totals before and after. Check that new activity with zero retention creates no row in that category.
4. Reload, switch characters and fully restart the client. Confirm limits persist, sequence ordering remains stable and lifetime totals survive. Restore desired retention limits afterward.
5. Where available, refund a purchase or buy back a sale whose Journal row was pruned; confirm permanent totals follow the original contribution without restoring an old history row.
