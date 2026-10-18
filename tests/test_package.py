"""Tests for the release package's load-order check."""

from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import package  # noqa: E402


class PackageCheckTests(unittest.TestCase):
    def copy(self, temporary: str) -> tuple[Path, Path]:
        root = Path(temporary)
        addon, tests = root / "AzerothLedger", root / "AzerothLedger_Tests"
        shutil.copytree(package.ADDON, addon)
        shutil.copytree(package.TESTS, tests)
        return addon, tests

    def test_release_follows_the_toc(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            addon, tests = self.copy(temporary)
            files = package.check(addon, tests)
            self.assertEqual(addon / "AzerothLedger.toc", files[0])
            self.assertEqual(addon / "Item.lua", files[1])

    def test_rejects_a_file_the_toc_does_not_list(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            addon, tests = self.copy(temporary)
            (addon / "Stray.lua").write_text("local _, addon = ...\n", encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "Stray.lua"):
                package.check(addon, tests)

    def test_rejects_a_listed_file_that_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            addon, tests = self.copy(temporary)
            (addon / "Journal.lua").unlink()
            with self.assertRaisesRegex(AssertionError, "Journal.lua"):
                package.check(addon, tests)

    def test_rejects_a_companion_file_the_toc_does_not_list(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            addon, tests = self.copy(temporary)
            (tests / "Stray.lua").write_text("", encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "Stray.lua"):
                package.check(addon, tests)


if __name__ == "__main__":
    unittest.main()
