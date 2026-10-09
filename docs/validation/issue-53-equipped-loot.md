# Issue #53: loot equipped before the inventory check

Implementation: 0.11.6. Validation date: 9 October 2026.

## Reproduction and settlement

A synthetic replay through production `Main.lua`, loot APIs, deferred inventory
events, and the public store reproduced the reported sword as Total gained 0.
The regression now records initial stock 0, one Looted gain, Recorded 1, the
proven source, and one queued discovery notification.

Loot sessions preserve known bag and gear stock for the bag threshold. They
enable combined settlement only when both baseline checks are complete and
share a date. Complete comparable checks after
loot measure their combined change. A complete bag increase can still settle
immediately when it exceeds all pre-loot possessions; moving already owned gear
into bags cannot satisfy that threshold. An explicitly partial or incomparable
equipment baseline blocks loot settlement for that session, including bag
increases. A later complete observation cannot prove the missing starting stock.
Normalized callers that supply only bag evidence keep their existing bag path.
Known gear stock remains in that threshold, but gear cannot establish credit.
Credits still require exact
intrinsic identity, a matching loot slot and personal receipt, and room after
competing confirmed gains.

Delayed slot identification keeps the original baseline. Source shares, award
limits, reward arbitration, and discovery persistence use the existing rules.
The optional possession baseline is validated and saved within schema 2; no
historical Unknown record is reclassified without matching saved evidence.
Reload retains committed gains and ends unsettled correlation conservatively.

## Automated and installation evidence

- Lua 5.1 syntax: all 48 addon, companion, and test files passed.
- All 19 `tests/*.lua` behavior suites passed, including WoWUnit companion replay
  and the 10,000-entry performance regression.
- StyLua 2.5.2, Luacheck 1.2.0, and LuaLS 3.19.1 passed locally.
- Package contents/load order and all 3 Python installer tests passed.
- Production event/scan cases cover normal bag loot, equip before checking,
  delayed receipts/slots, repeats, bag/gear moves, committed and unsettled reloads,
  incomplete/incomparable baselines, incomplete observations and recovery,
  existing gear, variant mismatch, missing slot/receipt, and a competing craft.
- The specification review reproduced owned gear moved into bags after a partial
  or differently dated gear baseline, including completely unreadable starting
  gear. Production regressions failed before the fixes and now pass. Known stock
  remains in the bag threshold and an uncertain equipment baseline blocks awards.
- `AzerothLedgerCollection` includes the combined-possession case with two
  different proven sources, retained enchanted links, one discovery, duplicate
  receipt/movement safety, and reopen persistence. Its host replay passed.
- The Forever root reports flavor `wow_classic_beta`; the account save has
  schema 2. Schema 2 remains in use and installation did not convert/reset data.
- The addon and companion were installed in `_classic_beta_`. A separate
  `--verify-only` run matched all 30 TOC-listed installed files. The installer
  copies only those files and does not touch WoWUnit or SavedVariables.

## Forever client evidence: pending

Native UI control is unavailable in this environment. No genuine client build,
locale, timing result, WoWUnit result, or Lua-error result was recorded for this
change. The replay's 70205/enUS values are synthetic fixtures.

Start or reload Forever and run `AzerothLedgerCollection` and
`AzerothLedgerEvidence`. Loot and immediately equip a newly discovered item
before its deferred bag observation, then confirm one Looted gain, Recorded 1,
source evidence, and at most one toast. Repeat bag/gear moves and reload/restart;
confirm the gain and source survive without another gain or toast. Exercise normal
and quick loot as controls. Record actual `GetBuildInfo()`, locale, test results,
and Lua errors separately from this host evidence.

## Standards review

No remaining documented-standard violations or substantive maintainability
findings. Shared private helpers consolidate the repeated possession arithmetic.

## Specification review

No remaining code findings. The reviewer rechecked partial, incomparable, and
fully unreadable equipment baselines, normal gains from complete comparable
baselines, duplicates, moves, and reopen persistence. The reproduced baseline
gaps have passing production regressions. Genuine Forever evidence remains pending.
