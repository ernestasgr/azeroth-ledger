# Same-source loot slots, 0.11.3

The active Forever save inspected on 2026-10-04 records build 1.60.1.70205,
interface 16001 and enUS. Kaghan has seven confirmed Ruined Pelts: five with
Mottled Boar sources and two in gain `9:4865:0` with no source. The saved trace
contains two personal one-unit Ruined Pelt receipts in the same event burst,
followed by bag updates. It does not contain slot-source data for that burst,
so it cannot establish the precise cause of those historical Unknown units.
SavedVariables were inspected without changing them.

A replay through the production Main event adapter reproduces source loss
when two matching physical loot slots prove the same corpse but only part of
their combined quantity has been measured. The minimized store regression
uses two two-unit slots from one named creature, a two-unit personal receipt,
and a measured increase from five to seven bag units. Before the fix,
`SameCorpseSlotsKeepTheSourceOfPartialLoot` reports `2 ~= nil` for the named
source total; the event replay reports `Matching slots from the same corpse
left a measured partial gain Unknown`.

`attributeLoot` previously required complete collection of every share before
attributing any gain with multiple shares. Version 0.11.3 keeps the source of
a measured partial gain when every share has the same proven source. Mixed
sources and missing source evidence retain the existing complete-take rule.
The fix changes attribution without changing the measured gain quantity.
The historical Unknown units remain unchanged because their proof is absent.

Regression coverage is in `tests/loot_event_spec.lua` and the native WoWUnit
group `AzerothLedgerCollection` in `AzerothLedger_Tests/Evidence.lua`. Both
failed before the fix and passed afterward. Existing mixed-source, unknown
share, overlapping-session, late-proof, expiry and repeated-event cases pass.

Local verification on the isolated branch from main passes: Lua 5.1 syntax for all 39 Lua files, all 16 behavior
specs, StyLua 2.5.2, Luacheck 1.2.0 with zero warnings/errors, LuaLS 3.19.1 with
zero diagnostics, package validation, and all three Python installer tests.
The Collection query replay also now loads the native frame fixture and
BookWidgets required by its existing icon-layer regression.

Version 0.11.3 was installed with the repository installer after verification.
The installer confirmed the beta flavor and all 24 TOC-listed addon and test
files matched their source hashes. A separate `--verify-only` run passed.
The account save is healthy schema 2 with 26 readable records at installation
of the isolated branch (13 at the original investigation). Fourteen
protected SavedVariables and WoWUnit files retained their original SHA-256
hashes across installation.

Native execution of the new regression and fresh loot behavior remain pending.
Reload the Forever client, run `AzerothLedgerCollection`, and record build,
locale, test results and Lua errors. Host replay and installed file hashes do
not establish in-client behavior.
