"""Install the checked-out addon and its WoWUnit companion into a local Forever client."""

from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path

from package import ADDON, ROOT, TESTS, check, manifest_files


DEFAULT_WOW_ROOT = Path("C:/Program Files (x86)/World of Warcraft/_classic_beta_")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def install(wow_root: Path, verify_only: bool) -> None:
    check()
    client = wow_root.resolve(strict=True)
    flavor = (client / ".flavor.info").read_text(encoding="utf-8")
    if "wow_classic_beta" not in flavor:
        raise ValueError(f"Expected the Forever beta at {client}")

    addons = (client / "Interface" / "AddOns").resolve(strict=True)
    if not (addons / "WoWUnit" / "WoWUnit.toc").is_file():
        raise FileNotFoundError("WoWUnit must be installed before the test companion")

    for source in (ADDON, TESTS):
        target = addons / source.name
        if target.exists() and not target.is_dir():
            raise ValueError(f"Addon target is not a directory: {target}")
        if target.exists() and not target.resolve().is_relative_to(addons):
            raise ValueError(f"Addon target leaves AddOns: {target}")
        if not verify_only:
            target.mkdir(exist_ok=True)

        names = [f"{source.name}.toc", *manifest_files(source / f"{source.name}.toc")]
        for name in names:
            origin = source / name
            destination = target / name
            if destination.exists() and not destination.resolve().is_relative_to(addons):
                raise ValueError(f"Addon file leaves AddOns: {destination}")
            if not verify_only:
                shutil.copy2(origin, destination)
            if digest(origin) != digest(destination):
                raise ValueError(f"Installed file differs from source: {destination}")
            print(f"verified {destination.relative_to(addons)}")

    print(f"Installed files match {ROOT} in {addons}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wow-root", type=Path, default=DEFAULT_WOW_ROOT)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    install(args.wow_root, args.verify_only)


if __name__ == "__main__":
    main()
