# Issue 20: vendor evidence and live controls

The WoWUnit `AzerothLedgerVendor` group replays sale followed by purchase, purchase and refund, sale and buyback, failed purchase, duplicate reversal, ambiguous refund, and Journal pruning. The local Lua 5.1 replay passes. These are simulated events and bag snapshots, not in-client results.

## Observed failure, 2026-09-27

The user bought a Mining Pick from Brother Danil. The Collection screenshot shows item 2901 in a bag, first seen at 15:07, with Total gained 0. The saved account data records build 1.60.1.70009, locale enUS, addon revision 0.4.0, a complete bag scan with one Mining Pick, and an empty vendor action list. The purchase click path, chat receipt, WoWUnit result, and Lua errors were not captured. The replay now covers both `PickupMerchantItem` and `BuyMerchantItem` followed by an item increase without a chat receipt.

A second right-click purchase of Thin Cloth Bracers from Dermot Johns at 15:43 also left Total gained at 0 and the vendor action list empty. `/al status` reported no hook installation issue. The client has `C_MerchantFrame.GetItemInfo`; the addon's purchase adapter required the removed `GetMerchantItemInfo` global and silently returned no action. Version 0.4.1 uses the Forever API. Its replay runs with only `C_MerchantFrame.GetItemInfo` available and verifies that the right-click action and measured bag increase produce one gain.

After installing 0.4.1, a Thin Cloth Gloves purchase at 16:01 displayed Total gained 1, Method total Vendor 1, and Source total Vendor 1. This confirms live purchase credit, but the merchant name was missing. With Dermot Johns's merchant window open, `UnitName("npc")` returned `Dermot Johns`. Version 0.4.2 stores that name with new vendor actions and gains and displays it in the source total and activity detail. The user confirmed that the merchant name appeared in-client.

After a full client restart, the user reported that sources for loot, crafts, and purchases had disappeared. The 16:12:58 SavedVariables backup contains a confirmed named vendor gain; the 16:14:03 file contains a fresh ledger with no gains. The addon opened `AzerothLedgerDB` at Lua file scope, before WoW made SavedVariables available. Version 0.4.3 opens the store on this addon's `ADDON_LOADED` event. The new replay test supplies saved data after the Lua file runs, then verifies that the named vendor gain is restored. The in-client restart check is pending. A separate recovery copy of the 16:12:58 backup was preserved outside the game directory before any further test.

The earlier Forever trace on build 70009 recorded an item-specific `CHAT_MSG_LOOT` receipt for five Tough Hunks of Bread and a matching bag increase during an open merchant session. It also included gray-item sales. This trace predates the issue 20 code and did not record a locale, refund, buyback, or failed purchase. See [the original trace summary](forever-client.md).

## Pending in-client controls

Run the updated addon and `AzerothLedgerVendor` WoWUnit group in the Forever beta client. Record build, `GetLocale()`, group result, and any Lua errors. Then record each action's before/after bag quantity, native call, optional chat receipt, Collection totals, and recent activity:

| Control | Expected result | Status |
| --- | --- | --- |
| Buy one item and one stack | One Vendor gain per item-specific purchase action and measured increase, with or without a chat line; no duplicate vendor activity row | One-item purchase passed on 0.4.1; stack pending |
| Capture merchant name | Named vendor source total and purchase detail when `UnitName("npc")` is available | Passed on 0.4.2 before restart; 0.4.3 persistence retest pending |
| Open merchant and trigger money or merchant updates | No gain without a purchase action and measured increase | Pending |
| Sell, then purchase the same item | Sale activity and a separate new gain | Pending |
| Refund a uniquely linked purchase | Refund activity and a matching debit from Total gained, method, and source totals | Pending |
| Refund a purchased equipped item | Equipped-item decrease and the same linked debit | Pending |
| Sell and buy back | Two activity rows and no new gain for the buyback | Pending |
| Full-bag failed purchase | No gain; unresolved evidence retained | Pending |
| Two eligible same-item purchases followed by one refund | No guessed debit; unresolved evidence retained | Pending |

The hooks run after the native merchant and container calls. The addon keeps the last merchant-session bag-slot, equipped-slot, and buyback snapshots so a native call that removes an item immediately does not erase its action identity. The live controls must confirm those snapshots are current and that bag updates, equipment changes, and any chat receipts arrive in the expected order. The code leaves evidence unresolved when a unique link cannot be established.
