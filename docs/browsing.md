# Browsing recorded items and activity

Collection, Discoveries and Gallery share search, character/realm, category,
recorded place, ownership, quality, acquisition method, Found once and sorting.
Gallery additionally restricts results to gear and items awaiting classification.
Journal defaults to account-wide retained activity, newest first. Search,
character/realm, action and date range combine; they never change saved facts.

Clear filters resets the current view, including scope and sorting. In exact item
history it keeps the intrinsic item/variant key; Back to Collection restores the
previous browsing inputs, page and selection. Switching tabs keeps shared inputs;
controls irrelevant to a view do not restrict its query.

## Filter meanings

- Ownership uses the same scoped storage checks as item details: Present,
  Unknown or Historical only. Offline or unreadable checks do not prove absence.
- Unknown quality means item quality is unavailable. A numeric quality matches
  only that measured quality. Item-data arrivals can change these results.
- Acquisition methods match confirmed gains in the character/realm scope with
  positive quantity after refunds. Obtained includes gains whose exact means are
  unknown. Initial stock (Seen) matches account initial stock, within the selected
  item/character scope; it does not imply an acquisition by that character.
- Found once remains account-wide: no initial stock and exactly one net gained
  unit. Changing scope cannot turn a repeatedly gained item into Found once.
- Journal action and actor must match the same gain contribution. A grouped gain
  stays one complete event, with all its contributions visible in details.
  Transfers match either sender or recipient. Unknown channels match
  Obtained (way unknown), never Mail or Trade.
- Journal ranges are the last 24 hours, 7 days or 30 days as of choosing the range.
  The exact inclusive bounds appear below the list, in the client's local time.
  The query accepts inclusive `dateFrom` and exclusive `dateTo` timestamps;
  unknown/missing dates cannot match a bounded range. Reset restores Any date.

## Sort meanings

Name sorts ascending by the retained item name. Discovery and latest confirmed
gain date sort newest first in the selected character/realm scope. An account
view uses the account discovery date. An item without a confirmed gain date
sorts after dated items.

Quantity sorts largest first. Account views use Recorded (initial stock plus net
lifetime gains), not current ownership. Character/realm views use checked stock
at the latest check date. A `+` marks a known subtotal with older or unchecked
storage; it sorts by that subtotal. Unknown quantities sort last, and readable
zero sorts as zero. A stale observation never becomes checked stock.

Every Collection sort breaks equal values by ascending retained name, then
intrinsic item/variant key. Journal breaks equal event dates by descending commit
sequence. Results are deterministic across refreshes and reloads.

## Selection and refresh

Page changes can retain an item selected elsewhere in the same result set.
Excluding it selects the first matching item; zero results clear details and
preview links. Journal selection is a retained event sequence, not just an item
key. During cooperative refresh, rows and details hide until a current result
is ready. Input snapshots include all filters and sorting; item-data and ledger
changes invalidate work before results can be published.

## Forever validation still required

Reload the installed addon and record `GetBuildInfo()`, `GetLocale()`, WoWUnit
results for AzerothLedgerCollection and AzerothLedgerJournal, and any Lua errors.
Exercise all four tabs, menus with more than eight choices, keyboard navigation,
search, date bounds, quantity headings, reset, excluded selection, empty results,
item-data loading and a refresh while changing filters. Host replays and matching
installed hashes do not replace this check.
