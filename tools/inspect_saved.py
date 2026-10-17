"""Print what the Forever client saved about the ledger, without paging the whole file.

    python tools/inspect_saved.py                    # summary of the newest account save
    python tools/inspect_saved.py --item 2453        # record, related entries, trace lines
    python tools/inspect_saved.py --item "Healing Herb"
    python tools/inspect_saved.py --trace BAG_UPDATE --last 40

Needs lupa (requirements-dev.txt) to read the SavedVariables Lua file.
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime
from pathlib import Path

from install_local import DEFAULT_WOW_ROOT


def newest_save(wow_root: Path) -> Path:
    saves = sorted(
        (wow_root / "WTF" / "Account").glob("*/SavedVariables/AzerothLedger.lua"), key=lambda p: p.stat().st_mtime
    )
    if not saves:
        raise SystemExit(f"No AzerothLedger SavedVariables under {wow_root / 'WTF' / 'Account'}")
    return saves[-1]


def load(path: Path) -> dict:
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime()
    lua.execute("dofile(...)", str(path))
    is_table = lua.eval("function(v) return type(v) == 'table' end")

    def convert(value):
        if not is_table(value):
            return value
        return {key: convert(child) for key, child in value.items()}

    globals_ = lua.globals()
    return {name: convert(globals_[name]) for name in ("AzerothLedgerDB", "AzerothLedgerTraceDB")}


def dump(value, indent: str = "") -> str:
    if not isinstance(value, dict):
        return repr(value)
    lines = []
    for key in sorted(value, key=lambda k: (isinstance(k, str), k)):
        child = value[key]
        if isinstance(child, dict):
            lines.append(f"{indent}{key}:" + ("" if child else " {}"))
            if child:
                lines.append(dump(child, indent + "  "))
        else:
            lines.append(f"{indent}{key} = {child!r}")
    return "\n".join(lines)


def mentions(value, needles: tuple[str, ...]) -> bool:
    if isinstance(value, dict):
        return any(mentions(child, needles) for child in value.values())
    return isinstance(value, str) and any(needle in value for needle in needles)


def related(node, needles: tuple[str, ...], path: str = ""):
    """Yield the smallest tables outside `records` that hold a value naming the item."""
    for key, child in node.items():
        here = f"{path}.{key}" if path else str(key)
        if not isinstance(child, dict) or here == "records":
            continue
        leaves = [v for v in child.values() if not isinstance(v, dict)]
        if any(mentions(v, needles) for v in leaves):
            yield here, child
        else:
            yield from related(child, needles, here)


def summary(db: dict, trace: dict, path: Path) -> None:
    saved = datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds")
    print(f"file: {path}\nsaved: {saved}")
    print(f"schema: {db.get('schema')}  environment: {db.get('environment')}")
    print(f"records: {len(db.get('records', {}))}")
    print("areas:", ", ".join(sorted(db.get("areas", {}))))
    lines = trace.get("lines", {}) if trace else {}
    print(f"trace: enabled={trace.get('enabled') if trace else None} lines={len(lines)}")


def find_records(db: dict, query: str) -> list[dict]:
    records = db.get("records", {})
    if query in records:
        return [records[query]]
    if query.isdigit():
        return [r for r in records.values() if str(r.get("itemID")) == query]
    lowered = query.lower()
    return [r for r in records.values() if any(lowered in str(link).lower() for link in r.get("links", {}).values())]


def trace_lines(trace: dict) -> list[str]:
    lines = (trace or {}).get("lines", {})
    return [lines[i] for i in sorted(lines)]


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wow-root", type=Path, default=DEFAULT_WOW_ROOT)
    parser.add_argument("--file", type=Path, help="a specific AzerothLedger.lua instead of the newest save")
    parser.add_argument("--item", help="record key (2453:0), item ID, or part of the item name")
    parser.add_argument("--trace", help="regex to filter trace lines")
    parser.add_argument("--last", type=int, default=30, help="trace lines to show (default 30)")
    args = parser.parse_args()

    path = args.file or newest_save(args.wow_root)
    saved = load(path)
    db, trace = saved["AzerothLedgerDB"] or {}, saved["AzerothLedgerTraceDB"] or {}

    if not args.item and not args.trace:
        summary(db, trace, path)
        return

    pattern = re.compile(args.trace) if args.trace else None
    if args.item:
        records = find_records(db, args.item)
        if not records:
            raise SystemExit(f"No record matches {args.item!r}")
        for record in records:
            key, item_id = record.get("key"), record.get("itemID")
            print(f"== record {key}\n{dump(record, '  ')}")
            needles = (f"item:{item_id}:", str(key))
            for where, entry in related(db, needles):
                print(f"== {where}\n{dump(entry, '  ')}")
            item = re.compile(rf"item:{item_id}:|key={re.escape(str(key))}\b")
            pattern = re.compile(f"(?:{pattern.pattern})|(?:{item.pattern})") if pattern else item

    matches = [line for line in trace_lines(trace) if pattern.search(line)]
    print(f"== trace ({len(matches)} matching, last {args.last})")
    print("\n".join(matches[-args.last :]))


if __name__ == "__main__":
    main()
