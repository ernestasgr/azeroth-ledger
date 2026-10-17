# Coding standards

These are judgement calls for review. `tools/verify.py` already enforces formatting (StyLua), lint (Luacheck), types (LuaLS), Lua 5.1 syntax and package order, so review skips those.

## Evidence over guesses

The ledger records only what the client proves. Any rule that attributes an item to a source, a gain, or a character must cite the event or read that proves it.

- When the proof is missing or ambiguous, the code marks the item unresolved or **Unknown**. It never picks the likeliest source. For example, `MailSession` marks overlapping takes unresolved.
- Treat a client read as **untrusted** until the client signals it is settled. A read taken at login before the first `BAG_UPDATE_DELAYED` proves nothing (see `Inventory.lua`). A new event dependency needs its Forever ordering confirmed from a trace or the client's `BlizzardInterfaceCode`, and that source is named in a comment or the PR.
- Parse what the client actually sends, not the textbook shape. Item links carry extra fields such as a crafter GUID, and sender names can carry a surname or omit the realm. Parsers accept the observed variants, and a spec covers each one.

## One count per unit

Every view counts each unit once, under one way it was obtained.

- **Total gained** excludes units present at the first check and **Transfers** between your own characters.
- A **Transfer** appears only in a single character's view. A view spanning both characters (a realm or all characters) treats it as an internal move.
- When a change touches the breakdown, the reviewer checks the single-character, realm and all-characters views together.

## Domain language

Code, tests, comments and player-facing text use the terms in `CONTEXT.md` (Collection, Journal, Seen, Looted, Obtained, Transfer, Source, Unknown...). A new player-facing label either matches an existing term or comes with a `CONTEXT.md` entry. Labels never contradict the glossary: "Total gained" never counts a Transfer.

## Module boundaries

- `*Session.lua` modules turn client events into store calls. `Store*.lua` modules own the rules and saved data. `Main.lua` only wires modules together. A rule that leaks into a Session or into `Main.lua` is a finding.
- Sessions and readers take the client through an injected `api` table, not globals, so specs can drive them.
- Each module starts with `local _, addon = ...`, then a comment saying what the module owns or what it proves.

## Saved data

- A new saved field is optional and is validated in `SchemaValidate.lua`, so existing saves stay valid without a migration.
- Changing an existing field's meaning or bumping `CURRENT_SCHEMA` needs a migration and a backup path in the same PR. `tools/install_local.py` refuses any other schema, and records are never silently discarded.

## Tests

- A bug fix adds a spec case that reproduces the live data (real names, links and event order from the save or trace) and fails without the fix.
- An assert message states the player-visible rule (`"a transfer must not count the same units twice"`), not the mechanics.
- A behaviour that needs the client (event order, UI) is recorded as in-client pending in the PR or in `docs/validation/` until a WoWUnit run confirms it.

## Comments

Comments explain why: the client quirk, the missing proof, the reason for the guard. Code that only restates the next line doesn't need a comment.
