"""Run the addon's CI checks locally and in CI.

Uses native `lua`, `luac` and `luacheck` when they are on PATH (CI). Otherwise
falls back to lupa's embedded Lua 5.1 (see requirements-dev.txt) and the
Luacheck sources in `.tools/luacheck/src`.

    python tools/verify.py                          # every check
    python tools/verify.py tests/mail_event_spec.lua  # just those specs
    python tools/verify.py --only stylua luacheck
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LUA_DIRS = ("AzerothLedger", "AzerothLedger_Tests", "tests")
CHECKS = ("syntax", "specs", "stylua", "luacheck", "luals", "package", "installer")
NATIVE_LUA = bool(shutil.which("lua") and shutil.which("luac"))
ENV = {**os.environ, "PYTHONIOENCODING": "utf-8"}

# Runs one Lua file in a fresh lupa Lua 5.1 runtime.
LUPA_RUN = r"""
import sys
from lupa.lua51 import LuaRuntime
LuaRuntime().execute("assert(loadfile(...))()", sys.argv[1])
"""

# Compiles every given Lua file without running it, like `luac -p`.
LUPA_SYNTAX = r"""
import sys
from lupa.lua51 import LuaRuntime
lua = LuaRuntime()
errors = [lua.execute("local _, err = loadfile(...) return err", path) for path in sys.argv[1:]]
errors = [error for error in errors if error]
sys.exit("\n".join(errors) if errors else 0)
"""

LUPA_LUACHECK = r"""
import sys
from lupa.lua51 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('package.path = ".tools/luacheck/src/?.lua;.tools/luacheck/src/?/init.lua;" .. package.path')
print(lua.execute('''
local files = ...
local rc = {}
setfenv(assert(loadfile(".luacheckrc")), rc)()
local luacheck = require("luacheck")
local report = luacheck.check_files(files, rc)
local out = {}
for i, file in ipairs(report) do
    for _, w in ipairs(file) do
        out[#out + 1] = files[i] .. ":" .. w.line .. ":" .. w.column .. ": " .. luacheck.get_message(w)
    end
end
out[#out + 1] = "warnings=" .. report.warnings .. " errors=" .. report.errors
return table.concat(out, string.char(10))
''', lua.table_from(sys.argv[1:])))
"""


def lua_files() -> list[str]:
    return sorted(p.relative_to(ROOT).as_posix() for d in LUA_DIRS for p in (ROOT / d).rglob("*.lua"))


def run(command: list[str]) -> tuple[bool, str]:
    result = subprocess.run(
        command, cwd=ROOT, env=ENV, capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    return result.returncode == 0, (result.stdout + result.stderr).strip()


def lupa_python() -> list[str]:
    try:
        import lupa.lua51  # noqa: F401
    except ImportError:
        raise SystemExit("No native Lua and no lupa: run `pip install -r requirements-dev.txt` in .venv")
    return [sys.executable, "-c"]


def tool(*patterns: str) -> str | None:
    for pattern in patterns:
        found = sorted(ROOT.glob(pattern))
        if found:
            return str(found[0])
    return None


def check_syntax(_specs: list[str]) -> tuple[bool, str]:
    files = lua_files()
    ok, output = run(["luac", "-p", *files] if NATIVE_LUA else [*lupa_python(), LUPA_SYNTAX, *files])
    return ok, output or f"{len(files)} files"


def check_specs(specs: list[str]) -> tuple[bool, str]:
    paths = specs or sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "tests").glob("*_spec.lua"))
    runner = ["lua"] if NATIVE_LUA else [*lupa_python(), LUPA_RUN]
    with ThreadPoolExecutor() as pool:
        results = pool.map(lambda path: (path, *run([*runner, path])), paths)
        failures = [f"FAIL {path}\n{output[-1500:]}" for path, ok, output in results if not ok]
    return not failures, "\n".join(failures) or f"{len(paths)} specs"


def check_stylua(_specs: list[str]) -> tuple[bool, str]:
    stylua = shutil.which("stylua") or tool(".tools/stylua/stylua", ".tools/stylua/**/stylua.exe")
    if not stylua:
        return False, "StyLua not found in .tools/stylua or on PATH"
    return run([stylua, "--check", *LUA_DIRS])


def check_luacheck(_specs: list[str]) -> tuple[bool, str]:
    if shutil.which("luacheck"):
        return run(["luacheck", *LUA_DIRS])
    if not (ROOT / ".tools/luacheck/src/luacheck").is_dir():
        return False, "Luacheck not on PATH and no sources in .tools/luacheck/src"
    ok, output = run([*lupa_python(), LUPA_LUACHECK, *lua_files()])
    return ok and output.endswith("warnings=0 errors=0"), output


def check_luals(_specs: list[str]) -> tuple[bool, str]:
    luals = tool(".tools/luals/bin/lua-language-server", ".tools/luals/**/lua-language-server.exe")
    if not luals:
        return False, "LuaLS not found in .tools/luals"
    report = ROOT / "check.json"
    report.unlink(missing_ok=True)
    ran, output = run(
        [
            luals,
            f"--check={ROOT}",
            "--checklevel=Warning",
            "--check_format=json",
            f"--check_out_path={report}",
            f"--logpath={ROOT}",
        ]
    )
    if not report.exists():
        return False, output
    clean, diagnostics = run([sys.executable, "tools/check_luals.py"])
    return ran and clean, diagnostics


def check_package(_specs: list[str]) -> tuple[bool, str]:
    return run([sys.executable, "tools/package.py", "--output", "dist/AzerothLedger.zip"])


def check_installer(_specs: list[str]) -> tuple[bool, str]:
    return run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"])


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("specs", nargs="*", help="spec files to run; implies --only specs")
    parser.add_argument("--only", nargs="+", choices=CHECKS, help="run just these checks")
    args = parser.parse_args()
    selected = args.only or (["specs"] if args.specs else list(CHECKS))

    failed = []
    for name in CHECKS:
        if name not in selected:
            continue
        ok, output = globals()[f"check_{name}"](args.specs)
        detail = output.splitlines()[-1] if ok and output else ""
        print(f"{'PASS' if ok else 'FAIL'} {name}{f'  ({detail})' if detail else ''}", flush=True)
        if not ok:
            failed.append(name)
            print(output, flush=True)
    if failed:
        raise SystemExit(f"failed: {', '.join(failed)}")


if __name__ == "__main__":
    main()
