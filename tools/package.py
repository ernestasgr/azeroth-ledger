"""Validate TOC load order and build the addon-only release archive."""

from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "AzerothLedger"
TESTS = ROOT / "AzerothLedger_Tests"
SOURCE_ORDER = ("Item.lua", "Work.lua", "Trace.lua", "SchemaValidate.lua", "StoreKernel.lua", "StorePreferences.lua", "StoreJournal.lua", "StoreEvidence.lua", "StoreRecords.lua", "StoreLoot.lua", "StoreExchange.lua", "StoreVendor.lua", "StoreReward.lua", "StoreScan.lua", "Schema.lua", "Client.lua", "Scan.lua", "Inventory.lua", "Loot.lua", "Reward.lua", "Vendor.lua", "Exchange.lua", "LastSeen.lua", "Collection.lua", "Presentation.lua", "Journal.lua", "BookWidgets.lua", "BookQuery.lua", "Book.lua", "Settings.lua", "Events.lua", "Runtime.lua", "MerchantSession.lua", "MailSession.lua", "TradeSession.lua", "LootSession.lua", "QuestSession.lua", "CraftSession.lua", "Diagnostics.lua", "Commands.lua", "MinimapButton.lua", "Main.lua")

AUTO_LOADED_FILES = ("Bindings.xml",)

def manifest_files(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("##")
    ]


def check() -> list[Path]:
    toc = ADDON / "AzerothLedger.toc"
    assert manifest_files(toc) == list(SOURCE_ORDER), "main TOC load order changed"
    assert manifest_files(TESTS / "AzerothLedger_Tests.toc") == ["Smoke.lua", "Vendor.lua", "Exchange.lua", "Evidence.lua", "Collection.lua", "Journal.lua", "Presentation.lua", "PerformanceFixture.lua", "Performance.lua"]

    main = toc.read_text(encoding="utf-8")
    companion = (TESTS / "AzerothLedger_Tests.toc").read_text(encoding="utf-8")
    assert "## SavedVariables: AzerothLedgerDB, AzerothLedgerMinimapButtonDB, AzerothLedgerTraceDB" in main
    assert "## Dependencies: AzerothLedger, WoWUnit" in companion

    files = [toc, *(ADDON / name for name in (*SOURCE_ORDER, *AUTO_LOADED_FILES))]
    assert sorted(ADDON.iterdir()) == sorted(files), "unexpected file in release addon"
    assert all(path.is_file() for path in files)
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
