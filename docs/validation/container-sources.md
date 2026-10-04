# Container source rows, 0.11.4

The five Cactus Apple source GUIDs in the reported screenshot share GameObject
entry ID `171938`. Their final fields identify different spawned objects.
`store:breakdown` used the full GUID as an unnamed source label, producing
five one-unit rows for the same container type.

`ContainerSpawnsShareOneSourceTotalWithoutLosingTheirGUIDs` replays those five
GUIDs through the production loot store, restores the saved ledger, and checks
for one five-unit row. Before the fix, the host WoWUnit replay failed with
`1 ~= 5` on its source-row count. It passes after grouping container sources
by entry ID. Each original gain and complete source GUID remains recorded.
Existing schema 2 records use the new grouping directly without a migration.

Unnamed container types display as `Container #171938`. A recorded name on a
spawn labels other spawns of that type within the selected item and scope.
Different entry IDs remain separate even when their names match; conflicting
names fall back to the entry ID. Character and realm filters still apply.
Collection detail lines and Journal source text use the same container label.

The loot adapter accepts names from target, interacting NPC, or mouseover
units only when `UnitGUID` matches the exact GUID returned for that loot share.
It can also read `C_TooltipInfo.GetWorldCursor` when the Object tooltip's GUID
matches exactly. A nearby tooltip or another spawn of the same type cannot
name the source. Missing or failed lookups retain the unnamed source.
`LaterUnreadableContainerNameKeepsTheObservedName` also reproduces and fixes
loss of a previously captured name when a later same-session lookup supplies
the same GUID without a name. These lookups cannot increase gained units.

API references were checked in the local `wow-ui-source` checkout and the
installed Forever `BlizzardInterfaceCode` export. The generated
[TooltipInfo documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua)
includes `GetWorldCursor`, and the installed TooltipInfoShared documentation
defines the Object tooltip type. Availability of matching object GUID/name
data during Forever loot still requires live confirmation.

Local verification passes Lua 5.1 syntax for 43 files, all 17 behavior specs
(including the 10,000-entry performance regression), StyLua 2.5.2, Luacheck
1.2.0 with no warnings or errors, LuaLS 3.19.1 with no diagnostics, package
validation, and all three Python installer tests. StyLua checks an LF copy
of the Windows checkout to match CI line endings.

A read-only host replay of the active healthy schema 2 save shows
`Container #171938` with five Cactus Apples and retains all five original
gains and their full GUIDs. The query issues no saves, and the on-disk
SavedVariables SHA-256 hash remains unchanged.

Version 0.11.4 was installed into the verified Forever beta flavor with the
repository installer. The separate `--verify-only` check confirms all 27
TOC-listed addon and companion files match the workspace. All 13 protected
SavedVariables and WoWUnit files retain their pre-installation SHA-256 hashes.

Native validation remains pending: reload the installed 0.11.4 addon, run
`AzerothLedgerCollection`, inspect the existing Cactus Apple source row, and
loot fresh containers of the same and different types. Record build, locale,
WoWUnit results, and Lua errors. Host replay and installed file hashes do not
prove native name capture or live event order.
