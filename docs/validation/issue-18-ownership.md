# Issue #18: storage ownership in the Forever client

The player tested the installed addon on 26 September 2026, build **1.60.1.70009**, locale **enUS**. The build and locale were reported from `/al status`. The client flavor was `wow_classic_beta`. These results apply to this build and locale.

## In-client observations

- An initial Collection view at 20:36 showed bags and equipped gear checked, while the closed bank was incomplete. Items present in bags showed **Present** and initial Seen units with **Total gained 0**. The closed bank did not become a zero-quantity check.
- For Bottle of Dalaran Noir (item 2723), the Collection showed one initial unit, **Total gained 0**, and a bag → bank → bag sequence: bag **1 → 0 → 1**, bank **0 → 1 → 0**, dated 20:37 in the displayed observations. Ownership remained **Present**. After the bank closed, its latest area check was **Unknown**, while the readable bag still proved presence. The move did not add a Collection entry or a confirmed gain.
- A separate looted item showed bag **1 → 0 → 1** and equipped **0 → 1 → 0** around 20:48–20:49. Its Collection entry showed one **Looted** unit with a Young Wolf source and no second gain for the equip/unequip round trip.
- The player reported that the in-game `AzerothLedgerCollection` WoWUnit group **passed** after reload and that there were **no Lua errors**.

The evidence is the player's three Collection screenshots and test report in the issue #18 implementation chat. Screenshot timestamps are displayed to the minute. The WoWUnit panel output was reported by the player rather than captured in these screenshots. A stale offline character and unreadable slot were exercised by the normalized WoWUnit replay, not by these manual controls.

## Automated checks and installation

[PR #34's verify run](https://github.com/ernestasgr/azeroth-ledger/actions/runs/36259401982) passed Lua 5.1 syntax and behavior tests, StyLua, Luacheck, LuaLS, package validation, and Python installer tests. Before installation, the account SavedVariables file was checked as schema 2. The installer confirmed the Forever beta flavor and copied only TOC-listed Azeroth Ledger files; a second `--verify-only` run confirmed their hashes. This installation check is separate from the in-client observations above.
