# Native Lua addon toolchain and WoWUnit

Research date: 25 September 2026. Scope: [Determine the native Lua toolchain and WoWUnit validation approach](https://github.com/ernestasgr/azeroth-ledger/issues/3). The user has selected native Lua without TypeScript or Effect. This report recommends development tooling and validation gates; it does not implement or certify a working addon. Client/API feasibility is covered separately in [Forever feasibility](https://github.com/ernestasgr/azeroth-ledger/blob/11ee69b9bd4e212cb935891f815f4b5066885d82/docs/research/forever-feasibility.md).

## Recommended baseline

Use native Lua, LuaCATS annotations checked by Lua Language Server (LuaLS), StyLua formatting, Luacheck linting, and Jaliborc's WoWUnit for behavioral tests. Keep tools outside the shipped runtime. Pin tool versions and API-definition revisions when scaffolding; this investigation did not install or execute them.

| Concern | Evidence | Project recommendation |
| --- | --- | --- |
| Type-oriented development | LuaLS understands annotated parameters, return values, aliases, unions, table structures, optional fields and exact classes. [Annotations](https://luals.github.io/wiki/annotations/) | Annotate module boundaries, normalized events, persisted records, settings and adapter contracts. Use finite literal values for provenance, acquisition method and ownership state. |
| Static checking | LuaLS checks inferred and annotated types, but explicitly describes its checker as less complete than TypeScript's type system. [Type checking](https://luals.github.io/wiki/type-checking/) | Describe this honestly as statically checked, annotated Lua. Validate SavedVariables and external event payloads at runtime; comments do not enforce runtime types. |
| CI diagnostics | LuaLS supports a command-line workspace check and emits `check.json`, using the workspace configuration. [Diagnosis report](https://luals.github.io/wiki/diagnosis-report/) | Check the same `.luarc.json` in editor and CI; fail on selected warning/error diagnostics after verifying the pinned binary's reporting behavior. |
| Formatting | StyLua supports Lua 5.1 syntax and a non-mutating `--check` mode that returns failure when formatting differs. [StyLua](https://github.com/JohnnyMorganz/StyLua) | Commit `.stylua.toml`; run `stylua --check` for source and tests. Start with `Lua51` syntax and verify it against the target client. |
| Linting | Luacheck detects undefined globals, unused/uninitialized values and unreachable code, with configurable project globals and Lua versions. [Luacheck](https://github.com/lunarmodules/luacheck) | Commit `.luacheckrc`; allow only intentional addon/SavedVariables globals and verified client APIs. Avoid blanket unknown-global suppression. |
| WoW declarations | Ketho's WoW API project supplies LuaLS annotations, WoW's Lua 5.1 environment and generated Blizzard API information; it is a third-party tool. [Maintainer README](https://github.com/Ketho/vscode-wow-api) | Use a pinned declaration set as a starting point, supplemented by the actual Forever export. Do not mistake Mainline declarations or editor completion for Forever compatibility. |

The Lua 5.1 tooling target is a conservative starting recommendation, not a substitute for recording `_VERSION`, `GetBuildInfo()` and the target client's API export during the feasibility gate.

## Modular native Lua design

Recommended architecture, rather than a requirement imposed by a library:

1. Keep item identity, acquisition reconciliation, collection aggregation, ownership evaluation and journal retention in independent domain modules. Pass plain records in and return results or explicit errors; avoid WoW globals in these modules.
2. Put event registration, bag/bank reads, asynchronous item data, time, character identity and SavedVariables access behind small injected adapter tables. Capture acquisition context immediately, before asynchronous metadata completion.
3. Give each mutable store a single owning module. Expose operations and read models instead of letting UI code edit persisted tables directly.
4. Compose modules in one bootstrap with explicit load order. Use the addon's private namespace for cooperation between files, avoiding a global for every module. Do not add a custom module framework unless a demonstrated need exceeds ordinary tables and functions.
5. Keep native frames, Settings registration, tooltip hooks, toasts and dressing-room integration in presentation adapters. Those modules consume collection/journal queries and issue commands; they do not calculate acquisition totals.
6. Validate persisted data and configuration at their boundary. Record a schema version, reject malformed values with a recoverable diagnostic, and preserve a usable collection when a single record is damaged. Define data evolution explicitly; do not conflate supporting old clients with preserving users' recorded discoveries.

This structure supports meaningful tests through injected data and deterministic clocks. It needs neither inheritance-heavy frameworks nor a runtime dependency for every module.

## WoWUnit: verified source facts and limits

Use **Jaliborc/WoWUnit**, identified explicitly to avoid confusion with the unrelated older `wowUnit` project. The maintainer documents callable test groups, event-triggered execution, equality/truth assertions, temporary replacements and optional addon dependency integration. [WoWUnit README](https://github.com/Jaliborc/WoWUnit)

The retrieved TOC now declares **version 12.1** and interfaces `120100, 50504, 40402, 30404, 20506, 16001, 11509`. Thus its current source explicitly includes interface **16001**, superseding the older no-16001 snapshot recorded in the feasibility note. This is an upstream declaration, **not our successful Forever test run**. Pin an exact revision during implementation because these `master` URLs can change. [WoWUnit TOC](https://raw.githubusercontent.com/Jaliborc/WoWUnit/master/WoWUnit.toc)

The implementation defaults groups without explicit event arguments to `PLAYER_LOGIN`; explicitly supplied events register those events. `AreEqual` recursively compares tables. `Replace` stores originals for later restoration by `ClearReplaces`. The core calls WoW helpers such as `tinsert`, `wipe`, `FindInTableIf`, and frame event methods; its TOC also loads XML and panel files before the test classes and core. Consequently this is an in-client framework, not evidence of a ready-made standalone Lua CLI runner. [WoWUnit implementation](https://raw.githubusercontent.com/Jaliborc/WoWUnit/master/WoWUnit.lua), [TOC](https://raw.githubusercontent.com/Jaliborc/WoWUnit/master/WoWUnit.toc)

Recommended packaging: a development-only `AzerothLedger_Tests` companion addon requiring Azeroth Ledger and WoWUnit. Keep the user's normal release free of automatic tests and test fixtures. If tests instead live in the main addon, use the maintainer's documented optional-dependency guard. Install WoWUnit separately rather than silently embedding or modifying it: the current TOC marks its license All Rights Reserved. [Integration guidance](https://github.com/Jaliborc/WoWUnit), [license declaration](https://raw.githubusercontent.com/Jaliborc/WoWUnit/master/WoWUnit.toc)

## What to test and where

Proposed WoWUnit behavioral suites should exercise public module operations with realistic input sequences:

- Initial observations create discoveries with unknown acquisition dates and no discovery toast; later evidenced acquisitions retain the earlier observation while updating acquisition information.
- Duplicate evidence and differing event order produce one acquisition; two actual acquisitions of the same quantity remain distinct.
- Bag rearrangement, equip/unequip and bag-bank transfers change holdings without creating acquisitions.
- Intrinsic suffix/bonus variants remain distinct while enchant/gem changes preserve the same collection identity; keep full observed links separately.
- Journal eviction and configured retention reductions preserve permanent totals, first/last dates and discovery counts.
- Unvisited/offline storage produces last-known or Unknown ownership as appropriate, never a fabricated proof of absence.
- Item-data failure, delayed completion and repeated callbacks do not lose, duplicate or misattribute acquisitions.
- Search/filter queries distinguish Collection entries from Journal quantities and acquisition-event counts.

Local CI can immediately enforce formatting, lint, LuaLS diagnostics and package/TOC consistency without a game client. Running the **same WoWUnit tests** headlessly would need a proven host adapter that loads the real framework with its necessary WoW environment and reports failures correctly; no supported upstream headless runner was established by the examined README/core/TOC. Treat that as a bounded tooling spike, not an already available capability. Do not substitute a homegrown assertion table named `WoWUnit` and claim WoWUnit coverage.

In-client gates remain necessary: load the pinned WoWUnit on the exact Forever build, deliberately demonstrate both passing and failing tests, run the suite, verify the actual event traces and SavedVariables reload behavior, and inspect native Settings, tooltips, toasts and model previews. Mocked unit tests cannot establish real event ordering, persistence behavior, appearance or client API availability.

## Decisions still requiring implementation evidence

1. Capture the Forever build/export and pin API declarations plus the exact WoWUnit revision. Confirm its 16001 declaration by actually executing tests.
2. Verify LuaLS warning/error CI behavior and define narrow, documented suppression rules. Pin all tool versions before the first build ticket is considered complete.
3. Choose whether headless execution provides enough value to justify an adapter. Keep genuine in-client WoWUnit execution mandatory regardless.
4. Agree a reproducible client test record: build, locale, addon/framework revision, fixture scenario, pass/fail output and any manually verified UI/persistence observations.

The native Lua decision is settled. None of these gates reopens TypeScript or Effect as a requirement.
