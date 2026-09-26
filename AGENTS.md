## Agent skills

### Issue tracker

Issues and specs live as GitHub issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default labels `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Use the single-context layout. See `docs/agents/domain.md`.

## Finish addon implementations

Before finishing an implementation, run the checks in `.github/workflows/verify.yml`: Lua 5.1 syntax and all `tests/*.lua` behavior tests, StyLua, Luacheck, LuaLS diagnostics, and package validation. If a tool is unavailable locally, wait for the PR's `verify` check and report which checks ran only in CI. Fix failures before calling the work done.

On this workstation, update the installed Forever beta addon after the checks pass:

```text
python tools/install_local.py --wow-root "C:/Program Files (x86)/World of Warcraft/_classic_beta_"
python tools/install_local.py --wow-root "C:/Program Files (x86)/World of Warcraft/_classic_beta_" --verify-only
```

The installer copies only TOC-listed files for `AzerothLedger` and `AzerothLedger_Tests`. Keep `WoWUnit` and other addons untouched. Check the account SavedVariables schema before installing; if it is incompatible, back up the file and resolve the data change explicitly instead of silently discarding records. Confirm the beta flavor and installed-file hashes; a file copy alone is not an in-client test.

For changes that require in-client behavior, reload or restart the Forever client and run the relevant WoWUnit group, including `AzerothLedgerCollection` for Collection changes. Record the build, locale, test result, and any Lua errors. If the client cannot be exercised from this environment, say that the in-client check is pending rather than claiming it passed.
