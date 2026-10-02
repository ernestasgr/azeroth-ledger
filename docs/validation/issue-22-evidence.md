# Issue #22: ambiguous evidence and corrections

Version 0.6.0 ends active correlation at 60 seconds or 256 incoming candidate signals per character. Signals that cannot match, expire, or exceed that limit remain durable unresolved evidence. The account keeps 2,000 detailed records; older records become a discarded count and date range, with a warning in the Collection and `/al status`. A new store ends unfinished correlation at login/reload. Completed purchases, sales and outgoing alt-transfer references remain available for later reversals or matching on another character.

The `AzerothLedgerCollection` WoWUnit group now includes expiry at the exact boundary, repeated receipts, candidate overflow, account retention overflow, character independence, failed/delayed intrinsic identity, reload before matching, competing same-item source shares, delayed slot-source proof, metadata enrichment, method/source corrections, duplicate correction across reload, identity mismatch, and correction underflow. Every transition checks committed quantities or evidence through public store queries. A partial multi-source take stays unattributed; a complete measured take of all slots can prove their quantities. Corrections validate the existing contribution and preserve Recorded units.

An item ID alone cannot identify an intrinsic gear variant. Truncated links remain unresolved. A readable snapshot records Seen facts, and exact identity metadata can enrich existing links without creating a gain. Historical unreadable evidence is resolved automatically only when the same snapshot time, storage slot, item ID and quantity identify it; a later item with the same ID alone cannot rewrite an uncertain historical variant.

The installed Forever export declares `GET_ITEM_INFO_RECEIVED` with an item ID and success flag, and `LOOT_SLOT_CHANGED`. Successful item-data notifications trigger a fresh storage check; failed callbacks leave unresolved evidence intact. Slot changes can enrich only the same item, slot and quantity in the current loot action. Overlapping actions cannot regain an invented source.

## Checks and installation, 2026-10-02

Lua 5.1 syntax, all ten `tests/*.lua` behavior files (including 41 companion replay cases), StyLua 2.5.2, LuaLS 3.19.1, package validation and all three Python installer tests pass locally. [The required verify run](https://github.com/ernestasgr/azeroth-ledger/actions/runs/37053995124) passes for code commit `37668ea`, including Luacheck 1.2.0-1, which ran only in CI. Standards and spec review findings were fixed; both reviews report no remaining blockers.

Before installation, the account SavedVariables validated as healthy schema 2 with 34 readable Collection records. The client flavor is `wow_classic_beta`. `tools/install_local.py` and its `--verify-only` run both succeeded against `C:/Program Files (x86)/World of Warcraft/_classic_beta_`: all 16 TOC-listed addon and test-companion files match the workspace hashes. WoWUnit and other addons were untouched. Version 0.6.0 is installed; these file checks do not establish an in-client pass.

## Live validation

The Forever client is not running and native app control is unavailable in this environment. No in-client result is claimed for this version.

| Check | Build | Locale | Result | Lua errors |
| --- | --- | --- | --- | --- |
| `AzerothLedgerCollection` genuine WoWUnit group | Pending | Pending | Unrun in client | Pending |
| Delayed/failed item-data callbacks | Pending | Pending | Unrun in client | Pending |
| Delayed item-specific source proof | Pending | Pending | Unrun in client | Pending |
| Two simultaneous same-item sources | Pending | Pending | Unrun in client | Pending |
| Expiry/overflow warning and reload | Pending | Pending | Unrun in client | Pending |

Start the Forever beta client, enable Lua errors, run `AzerothLedgerCollection`, and record `GetBuildInfo()`, `GetLocale()`, the test-group result and errors. Confirm the real callback order and Collection warning. Host replays and installed-file hashes do not substitute for these controls.
