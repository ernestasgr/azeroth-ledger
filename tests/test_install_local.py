"""Tests for the local Forever addon installer."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from install_local import install  # noqa: E402


class InstallLocalTests(unittest.TestCase):
    def test_installs_manifest_files_and_detects_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            client = Path(temporary)
            (client / ".flavor.info").write_text("wow_classic_beta", encoding="utf-8")
            addons = client / "Interface" / "AddOns"
            (addons / "WoWUnit").mkdir(parents=True)
            (addons / "WoWUnit" / "WoWUnit.toc").write_text("", encoding="utf-8")
            (addons / "AzerothLedger").mkdir()
            other_file = addons / "AzerothLedger" / "local-note.txt"
            other_file.write_text("keep", encoding="utf-8")

            install(client, verify_only=False)
            install(client, verify_only=True)
            self.assertEqual("keep", other_file.read_text(encoding="utf-8"))

            (addons / "AzerothLedger" / "Main.lua").write_text("stale", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "differs from source"):
                install(client, verify_only=True)
            install(client, verify_only=False)

    def test_rejects_the_wrong_client(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            client = Path(temporary)
            (client / ".flavor.info").write_text("wow_retail", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Forever beta"):
                install(client, verify_only=False)

    def test_rejects_incompatible_saved_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            client = Path(temporary)
            (client / ".flavor.info").write_text("wow_classic_beta", encoding="utf-8")
            addons = client / "Interface" / "AddOns"
            (addons / "WoWUnit").mkdir(parents=True)
            (addons / "WoWUnit" / "WoWUnit.toc").write_text("", encoding="utf-8")
            saved = client / "WTF" / "Account" / "SavedVariables" / "AzerothLedger.lua"
            saved.parent.mkdir(parents=True)
            saved.write_text('AzerothLedgerDB = { ["schema"] = 1 }', encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "schema 2"):
                install(client, verify_only=False)
            self.assertFalse((addons / "AzerothLedger").exists())


if __name__ == "__main__":
    unittest.main()
