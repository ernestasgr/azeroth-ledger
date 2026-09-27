# Issue 20: vendor evidence and live controls

The WoWUnit `AzerothLedgerVendor` group replays sale followed by purchase, purchase and refund, sale and buyback, failed purchase, duplicate reversal, ambiguous refund, and Journal pruning. The local Lua 5.1 replay passes. These are simulated events and bag snapshots, not in-client results.

The earlier Forever trace on build 70009 recorded an item-specific `CHAT_MSG_LOOT` receipt for five Tough Hunks of Bread and a matching bag increase during an open merchant session. It also included gray-item sales. This trace predates the issue 20 code and did not record a locale, refund, buyback, or failed purchase. See [the original trace summary](forever-client.md).

## Pending in-client controls

Run the installed addon and `AzerothLedgerVendor` WoWUnit group in the Forever beta client. Record build, `GetLocale()`, group result, and any Lua errors. Then record each action's before/after bag quantity, native call, receipt, Collection totals, and recent activity:

| Control | Expected result | Status |
| --- | --- | --- |
| Buy one item and one stack | One Vendor gain per item-specific receipt and measured increase; no duplicate vendor activity row | Pending |
| Open merchant and trigger money or merchant updates | No gain without receipt and increase | Pending |
| Sell, then purchase the same item | Sale activity and a separate new gain | Pending |
| Refund a uniquely linked purchase | Refund activity and a matching debit from Total gained, method, and source totals | Pending |
| Refund a purchased equipped item | Equipped-item decrease and the same linked debit | Pending |
| Sell and buy back | Two activity rows and no new gain for the buyback | Pending |
| Full-bag failed purchase | No gain; unresolved evidence retained | Pending |
| Two eligible same-item purchases followed by one refund | No guessed debit; unresolved evidence retained | Pending |

The hooks run after the native merchant and container calls. The addon keeps the last merchant-session bag-slot, equipped-slot, and buyback snapshots so a native call that removes an item immediately does not erase its action identity. The live controls must confirm those snapshots are current and that bag updates, equipment changes, and chat receipts arrive in the expected order. The code leaves evidence unresolved when a unique link cannot be established.
