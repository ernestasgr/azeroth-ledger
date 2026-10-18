"""Check the addon matches its TOC and build the addon-only release archive."""

from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "AzerothLedger"
TESTS = ROOT / "AzerothLedger_Tests"
AUTO_LOADED_FILES = ("Bindings.xml",)


def manifest_files(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        # Like the client: a line starting with # is metadata (##) or a comment, not a file.
        if line.strip() and not line.lstrip().startswith("#")
    ]


def listed_files(folder: Path, extra: tuple[str, ...] = ()) -> list[Path]:
    """The folder's TOC and what it lists, refusing missing files and files it does not list."""
    toc = folder / f"{folder.name}.toc"
    files = [toc, *(folder / name for name in (*manifest_files(toc), *extra))]
    missing = [path.name for path in files if not path.is_file()]
    assert not missing, f"{toc.name} lists missing files: {', '.join(missing)}"
    unlisted = sorted(path.name for path in set(folder.iterdir()) - set(files))
    assert not unlisted, f"unexpected files not listed in {toc.name}: {', '.join(unlisted)}"
    return files


def check(addon: Path = ADDON, tests: Path = TESTS) -> list[Path]:
    files = listed_files(addon, AUTO_LOADED_FILES)
    main = files[0].read_text(encoding="utf-8")
    companion = listed_files(tests)[0].read_text(encoding="utf-8")
    assert "## SavedVariables: AzerothLedgerDB, AzerothLedgerMinimapButtonDB, AzerothLedgerTraceDB" in main
    assert "## Dependencies: AzerothLedger, WoWUnit" in companion
    return files


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    files = check()
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with ZipFile(args.output, "w", compression=ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, f"AzerothLedger/{path.name}")
        with ZipFile(args.output) as archive:
            assert sorted(archive.namelist()) == sorted(f"AzerothLedger/{path.name}" for path in files)
    print("package and load order: passed")


if __name__ == "__main__":
    main()
