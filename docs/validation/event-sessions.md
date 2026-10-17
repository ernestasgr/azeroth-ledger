# Event sessions

`Main.lua` was a 980-line event hub: twenty shared mutable locals for the merchant,
mailbox, trade, loot, quest, and crafting windows; one `OnEvent` `if/elseif`
chain; slash commands, the minimap button, and trace diagnostics in the same
file. It is now a 210-line composition root. Item evidence rules, store calls,
event order, and the SavedVariables schema are unchanged.

## Modules

- `Events` merges per-session route tables (`{ EVENT = handler }`) into handler
  lists, registers them on one frame, installs secure hooks, and runs the
  one-second evidence expiry on `C_Timer.NewTicker` (frame `OnUpdate` when the
  client lacks it). Unusable APIs become `/al status` issues.
- `Runtime` reads the player, clock, NPC name, and TOC version, and binds the
  store actions sessions share (exchange intent/confirm, reward receipt). The
  saved environment revision now comes from the TOC `Version`, which fixes the
  `0.11.6`/`0.11.7` drift.
- `MerchantSession`, `MailSession`, `TradeSession`, `LootSession`,
  `QuestSession`, `CraftSession` each own their window's state in a closure and
  return `{ events, snapshot?, flushed? }`. Creation order is hook order.
- `Commands` is an ordered route list; `Diagnostics.status` returns status lines
  as data; `MinimapButton` keeps its saved-angle defaults and geometry in pure
  functions.

A mail take that turns ambiguous no longer passes a nil player to the store when
the player cannot be read; that intent is skipped like the others.

## Local validation

Run on 17 October 2026 with the repository's lupa Lua 5.1 runtime:

- Lua 5.1 syntax for 68 addon, companion, and test files.
- All 27 `tests/*.lua` behavior specs, including the new
  `event_routing_spec.lua` (route order, registration and hook failures, timer
  fallback, command parsing, minimap geometry, TOC revision).
- StyLua 2.5.2 (LF copy), Luacheck 1.2.0, LuaLS 3.19.1 diagnostics.
- Package/load order validation and the 8 Python installer tests.

The installer found healthy schema 2 saves, then copied the 43 TOC-listed addon
and companion files to the Forever beta (`wow_classic_beta`); a separate
`--verify-only` run matched every installed hash.

## Pending Forever checks

No WoW client was running. Native-client behavior is unverified. Record
`GetBuildInfo()`, locale, WoWUnit results, and Lua errors after `/reload` for the
Smoke, Vendor, Exchange, Evidence, `AzerothLedgerCollection`, Journal, and
Presentation groups, and check `/al status` lists no new API issues.
