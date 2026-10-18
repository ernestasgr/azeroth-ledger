## Agent skills

### Issue tracker

Issues and specs live as GitHub issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default labels `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Player-facing terms live in `GLOSSARY.md`. See `docs/agents/domain.md`.

### WoW API reference

Use the [generated Blizzard API documentation](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated) as a general reference. For Forever beta behavior, check the installed client's `BlizzardInterfaceCode` export and confirm event order in-client; the `live` branch may differ from this build.

## Checks and in-game data

Run checks with `.venv/Scripts/python tools/verify.py`: it runs all of CI's checks, and passing spec paths runs only those specs (fast red/green). CI runs the same script. If `.venv` is missing, run `py -3.14 -m venv .venv` and then `.venv/Scripts/python -m pip install -r requirements-dev.txt`.

Enable the pre-commit hook once per clone with `git config core.hooksPath .githooks`. It refuses staged files whose code is over 5,000 tokens (bytes / 4) and prints how to split them. Whole-line comments and Lua `---@` type annotations don't count. Lockfiles, build output, binaries and files marked `linguist-generated` in `.gitattributes` are skipped.

For a bug seen in-game, start with `.venv/Scripts/python tools/inspect_saved.py --item <id or name>`. It prints the newest account save's record, the journal entries for the item, and its event trace lines.

## Finish addon implementations

Before finishing an implementation, make `tools/verify.py` pass. Then update the installed Forever beta addon:

```text
.venv/Scripts/python tools/install_local.py
.venv/Scripts/python tools/install_local.py --verify-only
```

If the installer refuses because a SavedVariables schema is incompatible, back up the file and resolve the data change explicitly instead of discarding records. A file copy alone is not an in-client test.

For changes that require in-client behavior, reload or restart the Forever client and run the relevant WoWUnit group, including `AzerothLedgerCollection` for Collection changes. Record the build, locale, test result, and any Lua errors. If the client cannot be exercised from this environment, say that the in-client check is pending rather than claiming it passed.
