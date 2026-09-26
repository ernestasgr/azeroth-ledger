# Issue 19: quest and craft gain validation

The [Forever capability trace](forever-client.md) was recorded on build **1.60.1.70009**, locale **enUS**. It showed a choice reward with `QUEST_LOOT_RECEIVED`, `QUEST_TURNED_IN`, chat, and an item-specific bag increase of one. It also showed one successful craft with a result payload and matching output increase. These are **passed capability observations**, recorded before this implementation. No in-client run of this version of Azeroth Ledger has been performed yet.

| New addon client path | Status | Next in-client check |
| --- | --- | --- |
| Choice quest reward, with or without `QUEST_LOOT_RECEIVED` | Unrun | Select a reward; verify one Quest gain with the quest ID and measured quantity. |
| Fixed quest reward | Unrun | Complete a fixed-reward quest; verify one Quest gain. |
| Declined quest | Unrun | Decline or abandon without receiving the item; verify no gain. |
| Single craft | Unrun | Craft one item; verify one Crafted gain, with recipe context when `TRADE_SKILL_CRAFT_BEGIN` provides it. |
| Short craft batch | Unrun | Craft several outputs, including a growing stack; verify the measured quantity is counted once. |
| Canceled craft | Unrun | Start and cancel before a result; verify no gain. |
| Duplicate quest, craft, and chat notifications | Unrun | Verify one gain per measured increase despite overlapping channels. |
| Partial-stack output | Unrun | Add output to an existing stack; verify only the increase is gained. |

Run `AzerothLedgerCollection` in WoWUnit after reloading the installed addon. Record the actual build and `GetLocale()` value, the result of each path, and any Lua errors. A local Lua replay passes the group but does not count as an in-client pass.

On 26 September 2026, PR #35's `verify` job passed, including Lua 5.1 behavior, StyLua, Luacheck, LuaLS, package validation, and installer tests. The addon and its WoWUnit companion were installed to the local `wow_classic_beta` client and the installer verified all TOC-listed file hashes. The installed root reports build **1.60.1.70009**; no client session was available to confirm the runtime build or locale. `AzerothLedgerCollection` and the client paths above remain **unrun** in the client, and Lua errors could not be observed.

After that installation, a chosen quest reward was reported as **Seen 1; Total gained 0**. The saved schema 2 ledger contained the item and no reward claim. The exact client event sequence was not captured. A deterministic Main event regression reproduced the same result when `QUEST_LOOT_RECEIVED` was absent. The follow-up fix captures the complete quest offer and bag baseline at `QUEST_COMPLETE`, then credits the unique offered choice whose bag count increases after turn-in. Ambiguous changes remain unconfirmed. The regression and WoWUnit replay pass locally; the updated PR `verify` passed. The follow-up files were installed and hash-verified against the same `wow_classic_beta` root. **The new version has not yet been exercised in the client.** Runtime build, locale, WoWUnit result, and Lua errors remain to be recorded after reload.
