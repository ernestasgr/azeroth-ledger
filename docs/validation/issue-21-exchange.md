# Issue #21: mail and trade validation

The `AzerothLedgerExchange` WoWUnit group replays an alt mail send, message opening without retrieval, an attachment take with repeated success, outside mail into an existing stack, completed and canceled trade, competing same-item actions, uncertain alt stock, unknown player source, and reload. The host Lua 5.1 replay passes. These are simulated APIs and bag snapshots, not in-client results.

## Forever beta adapter status

| Adapter | Build | Locale | Live result | Lua errors |
| --- | --- | --- | --- | --- |
| Outgoing alt mail capture and measured sender decrease | Pending | Pending | Unrun with this addon version | Pending |
| Inbox attachment take, duplicate `MAIL_SUCCESS`, and partial stack | Pending | Pending | Unrun with this addon version | Pending |
| Outside mail and realm-qualified player source | Pending | Pending | Unrun | Pending |
| Completed trade and measured recipient increase | Pending | Pending | Unrun | Pending |
| Canceled trade with no gain | Pending | Pending | Unrun | Pending |
| `AzerothLedgerExchange` WoWUnit group | Pending | Pending | Unrun in client | Pending |
| `AzerothLedgerCollection` WoWUnit group | Pending | Pending | Unrun with this addon version | Pending |

The earlier build 70009 trace in `forever-client.md` established an alt mail x3 send and take with repeated `MAIL_SUCCESS`; it did not exercise this implementation. The exported client UI source shows the inbox item count in the fourth `GetInboxItem` result, the send item count in the fourth `GetSendMailItem` result, and the trade item count in the third trade item info result. It also uses `GetUnitName("NPC")` for the trade partner. Trade completion, partner realm, and whether attaching outgoing mail changes bag quantities before `SendMail` still need live checks.

After installation, restart or reload the Forever beta client, enable Lua errors, run both WoWUnit groups, and record `GetBuildInfo()`, `GetLocale()`, group results, and any Lua errors. Exercise each adapter row separately and record the before/after bag quantities and Collection totals. A copied addon and a host replay do not mark any live row passed.
