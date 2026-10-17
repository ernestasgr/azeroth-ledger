"""Clear Azeroth Ledger Collection data from a local Forever client's SavedVariables.

Keeps the schema, appearance, window and retention settings, and every other saved
variable (such as the minimap button position). Writes a timestamped backup first.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_WOW_ROOT = Path("C:/Program Files (x86)/World of Warcraft/_classic_beta_")
VARIABLE = "AzerothLedgerDB"
SCHEMA = 2
# Settings only; every Collection, Journal and evidence field is dropped.
KEPT_FIELDS = ("schema", "book", "display", "retention")


class LuaParseError(ValueError):
    pass


class _Parser:
    """Parse the literal subset WoW writes to SavedVariables files."""

    def __init__(self, text: str) -> None:
        self.text = text
        self.pos = 0

    def error(self, message: str) -> LuaParseError:
        line = self.text.count("\n", 0, self.pos) + 1
        return LuaParseError(f"{message} at line {line}")

    def skip(self) -> None:
        text = self.text
        while self.pos < len(text):
            if text[self.pos].isspace():
                self.pos += 1
            elif text.startswith("--", self.pos):
                if text.startswith("--[[", self.pos):
                    end = text.find("]]", self.pos)
                    self.pos = len(text) if end < 0 else end + 2
                else:
                    end = text.find("\n", self.pos)
                    self.pos = len(text) if end < 0 else end + 1
            else:
                break

    def peek(self) -> str:
        self.skip()
        return self.text[self.pos : self.pos + 1]

    def expect(self, token: str) -> None:
        self.skip()
        if not self.text.startswith(token, self.pos):
            raise self.error(f"expected {token!r}")
        self.pos += len(token)

    def name(self) -> str:
        self.skip()
        start = self.pos
        while self.pos < len(self.text) and (self.text[self.pos].isalnum() or self.text[self.pos] == "_"):
            self.pos += 1
        if start == self.pos or self.text[start].isdigit():
            raise self.error("expected a name")
        return self.text[start : self.pos]

    def string(self) -> str:
        quote = self.text[self.pos]
        self.pos += 1
        out = []
        escapes = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}
        while True:
            if self.pos >= len(self.text):
                raise self.error("unterminated string")
            char = self.text[self.pos]
            self.pos += 1
            if char == quote:
                return "".join(out)
            if char != "\\":
                out.append(char)
                continue
            char = self.text[self.pos]
            if char.isdigit():
                end = self.pos
                while end < len(self.text) and end < self.pos + 3 and self.text[end].isdigit():
                    end += 1
                out.append(chr(int(self.text[self.pos : end])))
                self.pos = end
            elif char in escapes:
                out.append(escapes[char])
                self.pos += 1
            else:
                raise self.error("unknown string escape")

    def number(self) -> int | float:
        start = self.pos
        while self.pos < len(self.text) and (self.text[self.pos].isalnum() or self.text[self.pos] in ".-+"):
            if self.text[self.pos] in "-+" and self.pos > start and self.text[self.pos - 1] not in "eE":
                break
            self.pos += 1
        token = self.text[start : self.pos]
        try:
            if token.lower().lstrip("-").startswith("0x"):
                return int(token, 16)
            value = float(token)
        except ValueError as exc:
            raise self.error(f"bad number {token!r}") from exc
        return int(value) if value.is_integer() and "." not in token and "e" not in token.lower() else value

    def value(self):
        char = self.peek()
        if char == "{":
            return self.table()
        if char in "\"'":
            return self.string()
        if char == "-" or char.isdigit() or char == ".":
            return self.number()
        word = self.name()
        if word == "true":
            return True
        if word == "false":
            return False
        if word == "nil":
            return None
        raise self.error(f"unexpected {word!r}")

    def table(self) -> list:
        """Return ordered (key, value) pairs; positional entries use None keys."""
        self.expect("{")
        entries = []
        while self.peek() != "}":
            if self.peek() == "[":
                self.pos += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
                entries.append((key, self.value()))
            else:
                start = self.pos
                if self.peek().isalpha() or self.peek() == "_":
                    word = self.name()
                    if self.peek() == "=" and word not in ("true", "false", "nil"):
                        self.pos += 1
                        entries.append((word, self.value()))
                    else:
                        self.pos = start
                        entries.append((None, self.value()))
                else:
                    entries.append((None, self.value()))
            if self.peek() in (",", ";"):
                self.pos += 1
            elif self.peek() != "}":
                raise self.error("expected ',' or '}'")
        self.expect("}")
        return entries

    def statements(self) -> list[tuple[str, int, int]]:
        """Return (name, value start, value end) for each top-level assignment."""
        result = []
        while self.peek():
            name = self.name()
            self.expect("=")
            self.skip()
            start = self.pos
            self.value()
            result.append((name, start, self.pos))
        return result


def _serialize(value, indent: str = "") -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
        return f'"{escaped}"'
    inner = indent + "\t"
    lines = ["{"]
    for key, item in value:
        prefix = "" if key is None else f"[{_serialize(key)}] = "
        lines.append(f"{inner}{prefix}{_serialize(item, inner)},")
    lines.append(f"{indent}}}")
    return "\n".join(lines)


def cleared(text: str) -> str:
    """Return the SavedVariables text with only Azeroth Ledger settings kept."""
    statements = _Parser(text).statements()
    found = [entry for entry in statements if entry[0] == VARIABLE]
    if len(found) != 1:
        raise LuaParseError(f"expected one {VARIABLE} assignment, found {len(found)}")
    _, start, end = found[0]
    db = _Parser(text[start:end]).value()
    if not isinstance(db, list):
        raise LuaParseError(f"{VARIABLE} is not a table")
    fields = {key: item for key, item in db if isinstance(key, str)}
    if fields.get("schema") != SCHEMA:
        raise ValueError(f"{VARIABLE} schema is {fields.get('schema')!r}, expected {SCHEMA}; not touching it")
    kept = [(key, fields[key]) for key in KEPT_FIELDS if key in fields]
    kept += [("records", []), ("areas", [])]
    kept.sort(key=lambda entry: entry[0])
    out = []
    for name, value_start, value_end in statements:
        value = _serialize(kept) if name == VARIABLE else text[value_start:value_end]
        out.append(f"{name} = {value}\n")
    return "".join(out)


def wow_running() -> bool | None:
    """True/False on Windows; None where the check cannot run."""
    if os.name != "nt":
        return None
    result = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH"], check=True, capture_output=True, text=True, errors="replace"
    )
    return any(line.strip('"').lower().startswith("wow") for line in result.stdout.splitlines())


def saved_files(wow_root: Path) -> list[Path]:
    accounts = wow_root / "WTF" / "Account"
    if not accounts.is_dir():
        return []
    return sorted(accounts.glob("*/SavedVariables/AzerothLedger.lua"))


def reset(wow_root: Path, dry_run: bool = False, force: bool = False) -> list[Path]:
    client = wow_root.resolve(strict=True)
    flavor = (client / ".flavor.info").read_text(encoding="utf-8")
    if "wow_classic_beta" not in flavor:
        raise ValueError(f"Expected the Forever beta at {client}")
    running = wow_running()
    if running and not force:
        raise RuntimeError("Close WoW first: it rewrites SavedVariables on logout and would restore the data")
    if running is None:
        print("warning: cannot check for a running WoW here; make sure the client is closed", file=sys.stderr)

    targets = saved_files(client)
    if not targets:
        print("No Azeroth Ledger SavedVariables found; nothing to clear.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    for target in targets:
        original = target.read_bytes()
        text = original.decode("utf-8-sig")
        result = cleared(text).encode("utf-8")
        account = target.parents[1].name
        if result == original:
            print(f"{account}: already clear")
            continue
        if dry_run:
            print(f"{account}: would clear {target}")
            continue
        backup = target.with_name(f"{target.name}.pre-collection-reset-{stamp}.bak")
        with backup.open("xb") as handle:
            handle.write(original)
        if backup.read_bytes() != original:
            raise OSError(f"Backup does not match: {backup}")
        if target.read_bytes() != original:
            raise RuntimeError(f"{target} changed while resetting; backup kept, file untouched")
        target.write_bytes(result)
        print(f"{account}: cleared {target}")
        print(f"  backup {backup.name} (sha256 {hashlib.sha256(original).hexdigest()[:16]})")
    return targets


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow-root", type=Path, default=DEFAULT_WOW_ROOT)
    parser.add_argument("--dry-run", action="store_true", help="show what would change without writing")
    parser.add_argument("--force", action="store_true", help="reset even though WoW appears to be running")
    args = parser.parse_args()
    reset(args.wow_root, dry_run=args.dry_run, force=args.force)


if __name__ == "__main__":
    main()
