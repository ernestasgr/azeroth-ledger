# Issue #52: mailbox retrieval and returns

Implementation: 0.11.5. Validation date: 9 October 2026.

## Evidence and behavior

Both reported failures were reproduced with synthetic events through production
`Main.lua` hooks, the native API adapter, inventory scanning, and public store and
Journal queries. Modified-click retrieval originally produced Total gained 0;
retrieving returned starting stock originally produced a false external gain.
The committed regressions now pass.

The installed Forever `BlizzardInterfaceCode` export uses `AutoLootMailItem` for
modified-click retrieval and `TakeInboxItem` for attachment retrieval. Its
`GetInboxHeaderInfo` call names return value 10 `wasReturned` and value 12
`canReply`. Its invoice UI treats `GetInboxInvoiceInfo` type `buyer` as a purchase.
These observations establish available adapters, not live event ordering.

A take captures the cached exact attachment variants and quantities. Generic
`MAIL_SUCCESS` needs matching disappearance from a readable inbox and a measured
bag increase before any credit. Inbox totals use the header and variant rather
than movable message indexes. Only a unique subset of whole attachments can
complete a partial retrieval; ambiguous subsets, overlapping commands, and
unreadable attachments remain unresolved. A partial bag observation cannot
complete a multi-unit attachment. The full stack can settle on a later complete
observation; a competing take ends that uncertain correlation. Failed attempts
can be retried, and expired waiting references do not block later independent
mail. Each stored area check has an increasing ID, so disposed neutral returns
cannot reserve later gains with the same numeric baseline or server timestamp.

Returned mail consumes a unique, confirmed outgoing mail reference belonging to
the receiving character, with the matching variant, peer, and available units.
It adds no external gain, transfer row, or discovery notification. Missing or
competing outgoing references leave the return unresolved. Consumed outgoing
units cannot prove another return.

A buyer invoice records an Obtained gain with durable Auction purchase evidence
in the Journal and Collection totals. It does not invent a player source from
the auction house sender. Other non-replyable or unreadable system mail, including auction
returns without a buyer invoice, stays unresolved. No auction listing lifecycle
or subject-text inference was added; unproven expired/canceled listings are not
classified as external gains. Ordinary outside mail and proven alt transfers
retain their existing behavior.

## Automated and installation checks

- Lua 5.1 syntax: 44 addon, companion, and host-test files passed.
- All 18 `tests/*.lua` files passed, including the 10,000-entry performance test
  and WoWUnit companion replay.
- StyLua 2.5.2, Luacheck 1.2.0, and LuaLS 3.19.1: passed locally.
- Package contents/load order and all 3 Python installer tests: passed locally.
- Production mailbox controls: individual/modified-click retrieval, multiple
  variants, complete/partial equal and unequal stacks, success before/after inbox
  and bag updates, duplicate signals, overlap, money-command interference, inbox
  reordering, failed retries, exact-variant mismatch, unreadable attachments,
  proven/unproven returns, buyer invoices, expired/canceled auction uncertainty,
  alt transfers, partial possession updates, expiry, and disposal/reacquisition
  after a neutral return in the same second.
- The Forever beta account save opened as healthy schema 2 before installation.
  Schema 2 remains in use; no records were reset or migrated.
- The addon and companion were installed in `_classic_beta_` and every TOC-listed
  installed file was hash-verified. SavedVariables and WoWUnit hashes were
  unchanged across installation (15 protected files).

## Native client validation: pending

The client cannot be exercised from this environment. Build, locale, mailbox
results, and Lua errors from a genuine client run are **not recorded**. The host
fixtures' build 70009 / enUS values are synthetic, not native evidence.

After reloading/restarting Forever, run `AzerothLedgerExchange` and
`AzerothLedgerCollection`, then exercise individual and modified-click retrieval,
partial/multiple attachment retrieval, an own-item return, ordinary outside mail,
an alt transfer, and buyer/expired/canceled auction mail. Confirm counts, Journal
rows, and discovery notifications, and record actual build, locale, results, and
Lua errors. In particular, verify the timing of `MAIL_SUCCESS`,
`MAIL_INBOX_UPDATE`, `MAIL_FAILED`, and bag updates against the real client.

## Standards review

No remaining documented-standard violations or substantive maintainability
findings. The optional repeated auction classification guards were consolidated.
The review's reproduced partial-stack completion finding was fixed by requiring
whole-attachment measurement, with a production regression.

## Specification review

The review reproduced three additional cases: partial stack measurement ending
overlap protection early, expired waiting IDs suppressing later mail, and a
disposed neutral return reserving a later outside gain. All three have passing
production regressions and fixes. No remaining specification gaps were found.
Native client evidence remains pending.
