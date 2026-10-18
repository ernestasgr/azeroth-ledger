"""Refuse staged files over the token limit so no file outgrows an agent's reading budget.

Tokens are estimated as bytes / 4 of the staged content (not the working tree).
Lockfiles, generated files and binaries are skipped: agents don't author them.
Mark other generated files with `linguist-generated` in .gitattributes.

    python tools/check_file_size.py               # the staged files (the pre-commit hook)
    python tools/check_file_size.py path.lua ...  # these staged paths
"""

from __future__ import annotations

import fnmatch
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAX_TOKENS = 5000
BYTES_PER_TOKEN = 4
NOT_AGENT_AUTHORED = (
    # Lockfiles
    "*.lock",
    "*-lock.json",
    "*-lock.yaml",
    "*.lockb",
    "go.sum",
    # Generated, vendored or built output
    "dist/*",
    ".tools/*",
    "*.min.js",
    "*.min.css",
    "*.map",
    "*.generated.*",
    "*_pb2.py",
)

SPLIT_INSTRUCTIONS = f"""\
Each file must stay under {MAX_TOKENS:,} tokens ({MAX_TOKENS * BYTES_PER_TOKEN:,} bytes) so an
agent can read it whole. Split each file above before committing. Don't minify, strip
comments or squeeze formatting to get under the limit.

How to split:
  1. Find the seams: group the file's functions by the one responsibility each serves
     (a rule, a saved-data domain, a UI panel, an event family). Each group becomes a file.
  2. Move each group into a new file named for what it owns, next to the original
     (e.g. StoreLoot.lua -> StoreLoot.lua + StoreLootGroup.lua). Keep the original file as
     the entry point other modules already call, so callers don't change.
  3. Addon modules (AzerothLedger/, AzerothLedger_Tests/):
     - start the new file with `local _, addon = ...` and a comment saying what it owns;
     - share functions through the `addon` table, never globals;
     - list the new file in the folder's .toc before the files that use it
       (tools/verify.py's package check refuses files the TOC doesn't list).
  4. Specs (tests/*_spec.lua): split by behaviour into new `<topic>_spec.lua` files and move
     shared fixtures into tests/support/. Every *_spec.lua is picked up automatically.
  5. Python tools: move helpers into a sibling module and import it.
  6. Docs: split by topic into separate files and link them from the original.
  7. Run `.venv/Scripts/python tools/verify.py`, stage the new files, and commit again.

Only if a file is generated or a lockfile, mark it `linguist-generated` in .gitattributes
instead of splitting it. Don't bypass this hook with --no-verify."""


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8"
    ).stdout


def staged_paths() -> list[str]:
    # Added, copied, modified or renamed: deleted files have nothing to measure.
    return [path for path in git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").split("\0") if path]


def attributes(paths: list[str]) -> dict[str, dict[str, str]]:
    found: dict[str, dict[str, str]] = {path: {} for path in paths}
    if not paths:
        return found
    output = git("check-attr", "-z", "--cached", "text", "linguist-generated", "--", *paths).split("\0")
    for path, name, value in zip(output[0::3], output[1::3], output[2::3]):
        found[path][name] = value
    return found


def agent_authored(path: str, attrs: dict[str, str]) -> bool:
    name = path.rsplit("/", 1)[-1]
    if any(fnmatch.fnmatch(path, pattern) or fnmatch.fnmatch(name, pattern) for pattern in NOT_AGENT_AUTHORED):
        return False
    # `binary` in .gitattributes unsets text; generated files opt out explicitly.
    return attrs.get("text") != "unset" and attrs.get("linguist-generated") not in ("set", "true")


def staged_tokens(path: str) -> int:
    return int(git("cat-file", "-s", f":{path}")) // BYTES_PER_TOKEN


def oversized(paths: list[str]) -> list[tuple[str, int]]:
    attrs = attributes(paths)
    checked = [path for path in paths if agent_authored(path, attrs[path])]
    return [(path, tokens) for path in checked if (tokens := staged_tokens(path)) > MAX_TOKENS]


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    too_big = oversized(sys.argv[1:] or staged_paths())
    if not too_big:
        return
    lines = [f"  {path}: ~{tokens:,} tokens (limit {MAX_TOKENS:,})" for path, tokens in too_big]
    print("Commit refused: staged files over the token limit (bytes / 4).", *lines, "", SPLIT_INSTRUCTIONS, sep="\n")
    raise SystemExit(1)


if __name__ == "__main__":
    main()
