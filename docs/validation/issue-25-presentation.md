# Issue #25: Truthful tooltips and first-discovery toasts

Revision 0.9.0 adds one account Collection line to native item tooltips: Seen starting stock, Looted evidence, Obtained with the recorded method, net gains, ownership, and known source or Unknown. Missing full links wait for the native rebuild; an item ID alone cannot choose a gear variant. The post-call checks actual tooltip text to avoid duplicate lines after repeated callbacks or ClearLines rebuilds.

The installed Forever `BlizzardInterfaceCode` export provides `TooltipDataProcessor.AddTooltipPostCall`, `Enum.TooltipDataType.Item`, `TooltipUtil.GetDisplayedItem`, and Settings proxy checkboxes. Comparison tooltips use `TooltipDataHandlerMixin` without `GameTooltipDataMixin:GetItem`, so the adapter uses the shared helper. `TooltipDataHandlerMixin:InternalProcessInfo` clears lines before normal rebuilds, runs post-calls after item lines, and then shows the tooltip. The local `wow-ui-source` reference was consulted first; installed-export behavior governs this adapter.

The store marks a discovery only when reconciliation proves its first external gain. After the SavedVariables save succeeds, it exposes a transient discovery notification. The permanent marker prevents repeated announcements; notifications are never restored at reload. Initial scans and alt transfers create no marker or toast. Muting suppresses notifications while keeping permanent facts. A visible update driver consumes notifications and shows native five-second toasts, with up to 20 waiting links to bound display work.

The store persists validated `tooltips` and `toasts` booleans, both default true, behind native AddOns Settings checkboxes. Optional display values and discovery markers remain in schema 2. Unsupported schemas stay read-only; malformed display values receive a diagnostic and safe defaults. No old account records are rewritten as new discoveries.

## Automated evidence

- Lua 5.1 syntax and all 15 `tests/*.lua` specs pass locally, each spec in its own process.
- Eleven `AzerothLedgerPresentation` WoWUnit cases pass in host replay: Seen versus Obtained; delayed loot proof and Unknown source; quest and craft discovery with zero Journal retention; outside versus alt mail; variants versus enchant changes; refund followed by repurchase; duplicate/reload suppression; muted discoveries; display persistence and validation; native checkbox callbacks; damaged and unsupported saved settings.
- Native boundary replay checks a comparison tooltip without GetItem, an uncached item, repeated post-calls, ClearLines rebuilds, next-interaction tooltip toggles, toast appearance in the frame port, timed dismissal and no toast on another gain of the same entry. The comparison fixture reproduced a missing-GetItem error before the shared helper fix.
- StyLua 2.5.2, LuaLS 3.19.1, package/load order and three Python installer tests pass locally. Luacheck uses the PR's pinned CI toolchain.

Host replay and installed-file hashes do not prove live-client behavior.

## In-client checks: pending

Native client control is unavailable in this environment. No current build, locale, genuine WoWUnit result or Lua-error result is claimed. The inspected UI export is API evidence only.

1. Reload Forever and record `/al status` build, interface, locale and revision 0.9.0. Run genuine `AzerothLedgerPresentation` and `AzerothLedgerCollection`; record results and Lua errors.
2. Hover an initial-stock item, a personally looted item, a quest reward and a vendor purchase. Check Seen, Looted and Obtained text, known and Unknown sources, stale-alt/closed-bank ownership, and intrinsic variants. Hover again and force native comparison/rebuilds; each tooltip must have at most one ledger line.
3. Hover an uncached item and wait for its native data refresh. Confirm the full-link variant appears once without Lua errors. Check GameTooltip, ItemRefTooltip and comparison tooltips.
4. Gain a previously unseen item with matched evidence. Confirm a five-second toast, then duplicate the signal, dispose of and regain the item, refund and repurchase it, and relog another character: no second first-discovery toast. Initial bag/bank/equipment scans and known alt mail/trade must stay quiet. Check queued discoveries and toast readability at the user's UI scale.
5. Toggle each display control separately in AddOns Settings → Azeroth Ledger. Confirm the next hover or discovery follows it; muted discoveries must not replay when enabled. Compare Collection facts before and after. Reload and fully restart the client; both controls must persist and old discoveries must stay quiet.
