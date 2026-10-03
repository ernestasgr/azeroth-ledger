# Early loot capture, 0.7.3

The native 0.7.2 screenshot shows Splintered Tusk on Mindria with Checked units 1+, Total gained 0 and First check 1. After the requested reload, the active schema 2 save contains a personal receipt for item 7098 at 13:24:45 marked `lootReceipt/unmatched`, followed by a one-unit bag observation at 13:24:46. The account's older confirmed tusk gain belongs to Aladora. The backup has no Mindria tusk observation. No saved facts have been changed to recover this gain.

The next client trace, on build 1.60.1.70205/enUS, captured a successful manual loot attempt:

| Seconds from open | Event | Evidence |
| --- | --- | --- |
| 0.000 | LOOT_OPENED | autoLoot=false; slots 117 (Tough Jerky) and 2651 (Flimsy Chain Bracers), one unit each, same creature source |
| 0.028 | CHAT_MSG_LOOT | Personal Tough Jerky receipt |
| 0.056 | LOOT_CLOSED twice, BAG_UPDATE_DELAYED | Bag check after close |
| 0.168 | CHAT_MSG_LOOT, BAG_UPDATE_DELAYED | Personal bracers receipt after close |

Both gains were counted once in the saved session. This trace did not reproduce the tusk failure and did not capture LOOT_READY. It rules out this particular delayed-receipt ordering as a cause.

The installed EllesmereUI QoL implementation loots at LOOT_READY, and the saved `quickLoot` setting is true. The installed client's API export documents LOOT_READY. A minimized replay through the real Main event adapter with a complete empty bag baseline, a readable tusk slot, LOOT_READY, personal receipt, close and one-unit bag increase failed on 0.7.2:

```text
python .tools/run_lua.py .tools/loot_ready_replay.lua
Splintered Tusk: checked units 1, Total gained 0
```

Changing only READY to OPENED passed with Total gained 1. This establishes a missing early-loot capture path, a likely explanation for the original miss; the original client event sequence was not captured, so its exact cause is not proven.

Version 0.7.3 captures readable item slots at READY or OPENED. Later notifications in the same open cycle add newly readable physical slots and enrich source proof without replacing the pre-gain baseline. The store retains the complete original bag and gain baseline, and measured increases for items whose loot links become readable later. A personal receipt arriving first stays unresolved within the active open cycle; it can be confirmed only when that same cycle supplies a proven slot and measured bag increase. Expired receipts and unrelated old unresolved evidence remain unchanged. New slots consume the existing candidate budget. Repeated slots do not add candidate quantities; overlapping sessions retain uncertain sources. Previously proven gains remain separate from ambiguous additional shares; when a complete take proves all shares, the same units acquire the complete source split. A wholly unknown physical-slot aggregate can receive a later complete source breakdown only when quantities match; corrected contributions are preserved. An empty/unreadable READY allows a later readable OPENED. Close releases the adapter capture flag while retained store evidence can still match a delayed receipt.

`tests/loot_event_spec.lua` covers the early-only path, repeated READY, OPENED after the bag increase, duplicate receipts, duplicate close with a late receipt, unreadable READY with OPENED fallback, partially readable READY with later new items or same-item slots, preservation of proven and unknown source shares, later source decomposition, receipt-before-slot ordering, rapid consecutive same-item cycles, expiry isolation, newest-reward arbitration before and after a pending receipt, and bag observations that must not invent gains. A later-readable egg with two initial units, a three-unit receipt and only a one-unit measured increase confirms exactly one gain. A captured unknown three-unit slot later resolves into source A one unit and source B two units without another gain. This host replay exercises production adapters and store code; it is not native-client execution.

Local Lua 5.1 syntax, all thirteen behavior specs, StyLua 2.5.2, LuaLS 3.19.1, package validation and three installer tests pass. Luacheck 1.2.0 runs only in CI on this workstation. Final review, CI and installation evidence will be recorded after completion. Native 0.7.3 quick-loot behavior, genuine AzerothLedgerEvidence/AzerothLedgerCollection WoWUnit results and Lua error status remain pending.
