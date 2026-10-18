"""Tests for the pre-commit token limit on staged files."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import check_file_size  # noqa: E402

BYTES_PER_TOKEN = check_file_size.BYTES_PER_TOKEN
LIMIT_BYTES = check_file_size.MAX_TOKENS * BYTES_PER_TOKEN


class CheckFileSizeTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        patcher = mock.patch.object(check_file_size, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def stage(self, path: str, size: int) -> None:
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(b"x" * size)
        subprocess.run(["git", "add", path], cwd=self.root, check=True)

    def refused(self) -> list[str]:
        return [path for path, _ in check_file_size.oversized(check_file_size.staged_paths())]

    def test_refuses_a_staged_file_over_the_limit(self) -> None:
        self.stage("AzerothLedger/Big.lua", LIMIT_BYTES + BYTES_PER_TOKEN)
        self.assertEqual(["AzerothLedger/Big.lua"], self.refused())

    def test_accepts_a_file_at_the_limit(self) -> None:
        self.stage("AzerothLedger/Edge.lua", LIMIT_BYTES + BYTES_PER_TOKEN - 1)
        self.assertEqual([], self.refused())

    def test_measures_the_staged_content_not_the_working_tree(self) -> None:
        self.stage("tools/script.py", 10)
        (self.root / "tools/script.py").write_bytes(b"x" * (LIMIT_BYTES * 2))
        self.assertEqual([], self.refused())

    def test_ignores_unstaged_files(self) -> None:
        (self.root / "Untracked.lua").write_bytes(b"x" * (LIMIT_BYTES * 2))
        self.assertEqual([], self.refused())

    def test_skips_lockfiles_and_build_output(self) -> None:
        for path in ("package-lock.json", "web/yarn.lock", "poetry.lock", "dist/AzerothLedger.lua"):
            self.stage(path, LIMIT_BYTES * 2)
        self.assertEqual([], self.refused())

    def test_skips_files_marked_generated_or_binary(self) -> None:
        (self.root / ".gitattributes").write_text("gen/** linguist-generated\n*.png binary\n", encoding="utf-8")
        subprocess.run(["git", "add", ".gitattributes"], cwd=self.root, check=True)
        self.stage("gen/Api.lua", LIMIT_BYTES * 2)
        self.stage("art/icon.png", LIMIT_BYTES * 2)
        self.assertEqual([], self.refused())

    def stage_text(self, path: str, text: str) -> None:
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text, encoding="utf-8", newline="\n")
        subprocess.run(["git", "add", path], cwd=self.root, check=True)

    def test_lua_comments_and_type_annotations_do_not_count(self) -> None:
        line = "x" * 76 + "\n"
        comments = ("-- " + line) * 400 + ("---@field name string " + line) * 400
        block = "--[[\n" + line * 400 + "]]\n" + "--[==[\n" + line * 400 + "]==]\n"
        self.stage_text("AzerothLedger/Typed.lua", comments + block + "local value = 1\n")
        self.assertEqual([], self.refused())

    def test_lua_code_still_counts(self) -> None:
        code = ("local value = '" + "x" * 60 + "' -- trailing note\n") * 300
        self.stage_text("AzerothLedger/Code.lua", code)
        self.assertEqual(["AzerothLedger/Code.lua"], self.refused())

    def test_python_comments_do_not_count(self) -> None:
        line = "x" * 76 + "\n"
        self.stage_text("tools/noted.py", ("    # " + line) * 400 + "VALUE = 1\n")
        self.assertEqual([], self.refused())

    def test_comment_markers_inside_strings_are_code(self) -> None:
        code = ('text = "-- ' + "x" * 70 + '"\n') * 300
        self.stage_text("AzerothLedger/Strings.lua", code)
        self.assertEqual(["AzerothLedger/Strings.lua"], self.refused())

    def test_refusal_explains_how_to_split(self) -> None:
        self.stage("AzerothLedger/Big.lua", LIMIT_BYTES * 2)
        with mock.patch("sys.argv", ["check_file_size.py"]), mock.patch("builtins.print") as printed:
            with self.assertRaises(SystemExit):
                check_file_size.main()
        message = "\n".join(str(arg) for call in printed.call_args_list for arg in call.args)
        self.assertIn("AzerothLedger/Big.lua", message)
        self.assertIn("How to split", message)
        self.assertIn(".toc", message)


if __name__ == "__main__":
    unittest.main()
