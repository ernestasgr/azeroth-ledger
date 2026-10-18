"""Profile anonymous ledger fixtures with Lua 5.1; these are host measurements."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import sys


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-path", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.lua_path:
        sys.path.insert(0, str(args.lua_path.resolve()))
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    measurements = lua.execute(r'''
        local addon = assert(loadfile("tests/support/addon.lua"))().addon("Book")
        date = os.date
        local fixture = assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))()
        local raw = fixture(10000)
        local started = os.clock()
        local store = addon.Schema.open(raw, function(value) raw = value end)
        local load = (os.clock() - started) * 1000
        assert(store:diagnostic().kind == "healthy")
        local native = assert(loadfile("tests/support/native_ui.lua"))().create()
        native.api.debugprofilestop = function() return os.clock() * 1000 end
        native.api.C_Item = { GetItemInfo = function(link)
            return "Fixture", link, 1, nil, nil, nil, nil, nil, nil, 1, nil, 7
        end }
        local frame = addon.Book.open(native.api, store, "Fixture", "Test")
        local frames = 0
        repeat
            frames = frames + 1
            frame.scripts.OnUpdate(frame)
        until addon.Work.timings["Collection query"]
            and addon.Work.timings["Collection query"].frames > 0
            and (function()
                for _, control in ipairs(native.controls) do
                    if control.text == "10000 items" and control:IsVisible() then return true end
                end
            end)()
        local open = addon.Work.timings["Collection open"].maximum
        local query = addon.Work.timings["Collection query"]
        local render = addon.Work.timings["Book frame"].maximum
        started = os.clock()
        frame.scripts.OnKeyDown(frame, "PAGEDOWN")
        local paging = (os.clock() - started) * 1000
        local update = 0
        for index = 1, 100 do
            started = os.clock()
            assert(store:scan({ character = "Fixture", realm = "Test", area = "bags", seenAt = 1001 + index,
                complete = true, items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 1 } } }))
            update = math.max(update, (os.clock() - started) * 1000)
        end
        local links, gained, sourcePairs = 0, 0, 0
        for record in store:cursor() do
            links, gained = links + #record.links, gained + record.totalGained
            for _, quantity in pairs(store:breakdown(record.key).sources) do
                if quantity > 0 then sourcePairs = sourcePairs + 1 end
            end
        end
        -- A compact Lua table surrogate. WoW's own writer must be measured in-client.
        local function serialize(value)
            if type(value) == "string" then return string.format("%q", value) end
            if type(value) ~= "table" then return tostring(value) end
            local parts = {}
            for key, child in pairs(value) do parts[#parts + 1] = "[" .. serialize(key) .. "]=" .. serialize(child) end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        started = os.clock()
        local serialized = "return " .. serialize(raw)
        local save = (os.clock() - started) * 1000
        started = os.clock()
        local restoredRaw = assert(loadstring(serialized))()
        local parse = (os.clock() - started) * 1000
        assert(addon.Schema.open(restoredRaw, function() end):count() == 10000)
        return { entries = 10000, journalRows = 9000, retainedLinks = links, lifetimeGained = gained,
            nonzeroItemSourcePairs = sourcePairs, schemaOpenMs = load, collectionOpenMs = open,
            collectionQueryFrames = query.frames, collectionQueryWorkMs = query.total,
            maximumQueryFrameMs = query.maximum, maximumBookFrameMs = render, keyboardPagingMs = paging,
            maximumStorageUpdateMs = update,
            serializedBytes = #serialized, surrogateSerializeMs = save, surrogateParseMs = parse }
    ''')
    report = dict(measurements.items())
    report["environment"] = f"{platform.system()} {platform.machine()}, Lua 5.1 via Lupa"
    report["scope"] = "Host replay, native frame port, synthetic metadata; not a WoW client measurement"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
