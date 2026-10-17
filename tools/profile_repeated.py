"""Measure repeated-item histories on the host, including a Lua save surrogate."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import subprocess
import sys


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-path", type=Path)
    parser.add_argument("--baseline", help="Load production modules from this Git ref")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.lua_path:
        sys.path.insert(0, str(args.lua_path.resolve()))
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    addon = lua.table()
    def read(path: str) -> str:
        if args.baseline:
            return subprocess.check_output(["git", "show", f"{args.baseline}:{path}"], text=True, encoding="utf-8")
        return Path(path).read_text(encoding="utf-8")

    # The store spans several files after the Schema split; take that ref's TOC order.
    listed = [line.strip()[:-4] for line in read("AzerothLedger/AzerothLedger.toc").splitlines()
              if line.strip().endswith(".lua")]
    store = [name for name in listed[: listed.index("Schema") + 1] if name.startswith(("Schema", "Store"))]
    for name in ("Item", "Work", *store, "Client", "LastSeen", "Collection", "Journal", "BookQuery", "Presentation"):
        source = read(f"AzerothLedger/{name}.lua")
        lua.execute('assert(loadstring((...)))("AzerothLedger", select(2, ...))', source, addon)
    cases = lua.execute(r'''
        local addon, baseline = ...
        date = os.date
        local companion = {}
        assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))("Tests", companion)
        local function serialize(value)
            if type(value) == "string" then return string.format("%q", value) end
            if type(value) ~= "table" then return tostring(value) end
            local parts = {}
            for key, child in pairs(value) do
                parts[#parts + 1] = "[" .. serialize(key) .. "]=" .. serialize(child)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        local function timed(action)
            collectgarbage("collect")
            local started = os.clock()
            local result = action()
            return result, (os.clock() - started) * 1000
        end
        local function complete(step)
            local result, maximum, frames = nil, 0, 0
            repeat
                local started = os.clock()
                result = step()
                maximum = math.max(maximum, (os.clock() - started) * 1000)
                frames = frames + 1
            until result
            return { rows = #(result.rows or {}), frames = frames, maximumStepMs = maximum }
        end
        local function counted(action)
            local instructions = 0
            local started = os.clock()
            debug.sethook(function() instructions = instructions + 1000 end, "", 1000)
            local result = action()
            debug.sethook()
            return result, (os.clock() - started) * 1000, instructions
        end
        local cases = {}
        for _, config in ipairs({ {100, 100, 1}, {5000, 1000, 1}, {5000, 5000, 1}, {50000, 0, 3} }) do
            local count, retained, items = unpack(config)
            local raw = companion.repeatedFixture(count, retained, items)
            local store, load = timed(function()
                return addon.Schema.open(raw, function(value) raw = value end)
            end)
            assert(store:diagnostic().kind == "healthy")
            local rows, journalMs = timed(function() return store:journal() end)
            local api = { debugprofilestop = function() return os.clock() * 1000 end }
            local session = addon.BookQuery.new(api)
            local skipBook = baseline and count == 5000 and retained == 5000
            local book, bookMs = {}, nil
            if not skipBook then
                book, bookMs = timed(function()
                    return complete(function() return session:step(store, "Fixture", "Test", {view="Journal"}) end)
                end)
            end
            local query = addon.Collection.startQuery(api, store, "Fixture", "Test", {}, function()
                return { category = "Materials", loading = false }
            end)
            local collection, collectionMs = timed(function() return complete(function() return query:step() end) end)
            local instructions, started = 0, os.clock()
            debug.sethook(function() instructions = instructions + 1000 end, "", 1000)
            assert(store:scan({ character="Fixture", realm="Test", area="bags", seenAt=60000, complete=true,
                items={{itemID=10001,link="|Hitem:10001::::::::|h[Item 00001]|h",quantity=count+1}} }))
            debug.sethook()
            local scanMs = (os.clock() - started) * 1000
            local serialized, saveMs = timed(function() return "return " .. serialize(raw) end)
            local restored, parseMs = timed(function() return assert(loadstring(serialized))() end)
            assert(addon.Schema.open(restored, function() end):count() == items)
            local observations = 0
            for _, record in pairs(raw.records) do observations = observations + #record.observations end
            local _, tooltipMs, tooltipInstructions = counted(function()
                return addon.Presentation.line(store, "|Hitem:10001::::::::|h[Item 00001]|h", "Fixture", "Test")
            end)
            assert(store:rewardReceipt({ key="10001:0", quantity=1, method="Crafted",
                context={kind="recipe",id=123} }, 60001,
                {character="Fixture",realm="Test",level=1,place="Test zone"}))
            local accepted, gainMs, gainInstructions = counted(function()
                return store:scan({character="Fixture",realm="Test",area="bags",seenAt=60002,complete=true,
                    items={{itemID=10001,link="|Hitem:10001::::::::|h[Item 00001]|h",quantity=count+2}}})
            end)
            assert(accepted and store:breakdown("10001:0").methods.Crafted == 1)
            cases[#cases + 1] = {
                gainsPerItem=count, items=items, retainedGains=retained, journalRows=#rows,
                schemaOpenMs=load, journalMs=journalMs, scanMs=scanMs, scanInstructions=instructions,
                bookQueryMs=bookMs, bookMaximumStepMs=book.maximumStepMs, bookFrames=book.frames,
                bookQuerySkipped=skipBook and "Baseline maximum-retention query exceeded host memory in an earlier run" or nil,
                collectionQueryMs=collectionMs, collectionMaximumStepMs=collection.maximumStepMs,
                collectionFrames=collection.frames, observations=observations,
                surrogateBytes=#serialized, surrogateSerializeMs=saveMs, surrogateParseMs=parseMs,
                confirmedGainScanMs=gainMs, confirmedGainScanInstructions=gainInstructions,
                tooltipMs=tooltipMs, tooltipInstructions=tooltipInstructions,
            }
        end
        return cases
    ''', addon, bool(args.baseline))
    report = {
        "source": args.baseline or "working tree",
        "environment": f"{platform.system()} {platform.machine()}, Python {platform.python_version()}, Lua 5.1 via Lupa",
        "scope": "Host synthetic fixtures; serialization and parsing are surrogates, not native SavedVariables timings",
        "cases": [dict(case.items()) for _, case in sorted(cases.items())],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
