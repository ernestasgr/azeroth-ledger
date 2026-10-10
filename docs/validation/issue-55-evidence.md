# Unresolved evidence inspection (#55)

The Ledger book's warning and **Inspect evidence** open a paged, read-only view. Character/realm menus include actors found only in evidence. Item search includes saved readable names/links, item IDs and unresolved variant keys. Select a row for its candidate action, units, actor, date, reason and supported next steps.

Live loot, reward, vendor and exchange candidates use the same projection as retained evidence. Each candidate has its own stable identity; sharing an item or time does not prove that two independent signals are one record. A quest preparation represented by its linked reward candidates is not shown again. Ended candidates leave the live engine and appear once in retained evidence.

Expired, reload-ended, queue-overflow and stopped vendor matching are distinct from active candidates. An unreadable identity may become Seen after item data and another relevant storage check; it does not establish a gain. Unmatched receipts alone do not prove an action. No controls confirm, retry or attribute gains. Overflow's discarded count/date range stays explicitly account-wide under filters; discarded details cannot be searched.

## Automated evidence

- `tests/evidence_query_spec.lua`: lifecycle transitions, no writes or gains during queries, item/actor filters, pending and stopped vendor/exchange actions, reload boundaries, malformed/unavailable identity and payloads, conservative unknown exchange actions, exact linked quest preparation suppression and a full 2,000-record retained queue spread across cooperative frames.
- `tests/book_ui_spec.lua`: warning entry point, selection, search empty states, live refresh, keyboard selection/page navigation and returning to Collection through native frame ports. A full 2,000-row UI queue also checks input while loading, actors found only in evidence and separate overflow/warning lines.
- `AzerothLedgerCollection.BookEvidenceShowsActiveAndEndedMatchesWithoutGains`: WoWUnit coverage for active/expired/reload-ended queries and unchanged totals. Executed by the replay suite; this is not native-client evidence.
- Lua 5.1 syntax, all `tests/*.lua` behavior tests, StyLua 2.5.2, Luacheck 1.2.0, LuaLS 3.19.1 diagnostics, package/load-order validation and installer unit tests run locally.

## Forever validation

SavedVariables schema remains 2. The local installer checks existing account files for schema compatibility and verifies the beta flavor before copying only TOC-listed addon and test files. Both installation and a separate verify-only pass compare file hashes. No SavedVariables conversion or reset is part of this change.

Version 0.11.7 was installed into `_classic_beta_` on 10 October 2026. The existing account file reported schema 2, flavor was `wow_classic_beta`, and installation plus the separate verify-only pass both succeeded. Both review axes have no remaining actionable findings after the malformed-payload, overflow layout, stopped-exchange and linked quest presentation fixes.

Native validation is pending: this environment cannot operate the Forever client. No current build, locale, native WoWUnit result or Lua-error result was observed. Reload the installed client, run `AzerothLedgerCollection`, `AzerothLedgerVendor` and `AzerothLedgerExchange`, and record the build, locale, results and Lua errors separately from replays. Check active/stopped vendor evidence, unresolved mail/trade, malformed item data, competing loot sources, expired/reload-ended rows, overflow count/date range, filters, keyboard access and live refresh in the book.
