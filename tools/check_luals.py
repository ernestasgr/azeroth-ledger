"""Fail CI when LuaLS reports warnings or errors."""

from __future__ import annotations

import json
from pathlib import Path


report = json.loads(Path("check.json").read_text(encoding="utf-8"))
if isinstance(report, list):
    problems = [(diagnostic.get("uri", "<unknown>"), diagnostic) for diagnostic in report]
else:
    problems = [(uri, diagnostic) for uri, diagnostics in report.items() for diagnostic in diagnostics]
for uri, diagnostic in problems:
    print(f"{uri}: {diagnostic}")
if problems:
    raise SystemExit(f"LuaLS reported {len(problems)} warning/error diagnostics")
print("LuaLS diagnostics: passed")
