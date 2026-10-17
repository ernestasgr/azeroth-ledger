"""Tests for clearing Azeroth Ledger Collection data from SavedVariables."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import reset_collection  # noqa: E402
from reset_collection import _Parser, cleared, reset  # noqa: E402

COMPACT = (
    'AzerothLedgerDB = {["areas"]={["Ada-Realm-bags"]={["seenAt"]=5}},["book"]={["scale"]=1.25,'
    '["filter"]={["search"]="say \\"hi\\""}},["display"]={["canvas"]={[1]=0.02,[2]=-1e-05}},'
    '["journal"]={["gains"]={{["id"]="1:2672:0"}},["nextSequence"]=2},["marker"]="m",'
    '["records"]={["2672:0"]={["itemID"]=2672}},["retention"]={["gains"]=1000},["schema"]=2}\n'
    'AzerothLedgerMinimapButtonDB = {["minimapPos"]=315}\n'
)

INDENTED = """
AzerothLedgerDB = {
\t["records"] = {
\t\t["2672:0"] = {
\t\t\t["links"] = {
\t\t\t\t"|cffffffff|Hitem:2672::::::::|h[Stringy Wolf Meat]|h|r", -- [1]
\t\t\t},
\t\t},
\t},
\t["schema"] = 2,
\t["display"] = {
\t\t["toasts"] = true,
\t},
\t["loot"] = {
\t},
}
AzerothLedgerMinimapButtonDB = {
\t["minimapPos"] = 200,
}
"""


def fields(text: str, name: str = "AzerothLedgerDB") -> dict:
    for statement, start, end in _Parser(text).statements():
        if statement == name:
            return {key: value for key, value in _Parser(text[start:end]).value()}
    raise AssertionError(name)


class ResetCollectionTests(unittest.TestCase):
    def test_keeps_settings_and_drops_collection(self) -> None:
        for source in (COMPACT, INDENTED):
            result = fields(cleared(source))
            self.assertEqual([], result["records"])
            self.assertEqual([], result["areas"])
            self.assertEqual(2, result["schema"])
            for dropped in ("journal", "loot", "marker", "environment", "evidence"):
                self.assertNotIn(dropped, result)
            self.assertIn("display", result)
        compact = fields(cleared(COMPACT))
        self.assertEqual(dict(compact["book"])["scale"], 1.25)
        self.assertEqual(dict(dict(compact["book"])["filter"])["search"], 'say "hi"')
        self.assertEqual(dict(dict(compact["display"])["canvas"])[2], -1e-05)
        self.assertEqual(fields(cleared(COMPACT), "AzerothLedgerMinimapButtonDB"), {"minimapPos": 315})
        self.assertEqual(fields(cleared(INDENTED), "AzerothLedgerMinimapButtonDB"), {"minimapPos": 200})

    def test_is_idempotent(self) -> None:
        once = cleared(COMPACT)
        self.assertEqual(once, cleared(once))

    def test_rejects_other_schemas(self) -> None:
        with self.assertRaisesRegex(ValueError, "schema"):
            cleared('AzerothLedgerDB = {["schema"]=1,["records"]={}}\n')

    def test_backs_up_and_clears_each_account(self) -> None:
        original_check = reset_collection.wow_running
        reset_collection.wow_running = lambda: False
        try:
            with tempfile.TemporaryDirectory() as temporary:
                client = Path(temporary)
                (client / ".flavor.info").write_text("wow_classic_beta", encoding="utf-8")
                saved = client / "WTF" / "Account" / "1#1" / "SavedVariables"
                saved.mkdir(parents=True)
                target = saved / "AzerothLedger.lua"
                target.write_text(COMPACT, encoding="utf-8")

                reset(client, dry_run=True)
                self.assertEqual(COMPACT, target.read_text(encoding="utf-8"))

                reset(client)
                backups = list(saved.glob("AzerothLedger.lua.pre-collection-reset-*.bak"))
                self.assertEqual(1, len(backups))
                self.assertEqual(COMPACT, backups[0].read_text(encoding="utf-8"))
                self.assertEqual([], fields(target.read_text(encoding="utf-8"))["records"])

                reset(client)
                self.assertEqual(1, len(list(saved.glob("*.bak"))), "an unchanged save needs no new backup")
        finally:
            reset_collection.wow_running = original_check

    def test_refuses_while_wow_runs(self) -> None:
        original_check = reset_collection.wow_running
        reset_collection.wow_running = lambda: True
        try:
            with tempfile.TemporaryDirectory() as temporary:
                client = Path(temporary)
                (client / ".flavor.info").write_text("wow_classic_beta", encoding="utf-8")
                with self.assertRaisesRegex(RuntimeError, "Close WoW"):
                    reset(client)
        finally:
            reset_collection.wow_running = original_check


if __name__ == "__main__":
    unittest.main()
