#!/usr/bin/env python3
"""Copy a validated private help bundle into a newly created package directory."""
import argparse
from pathlib import Path
import shutil

from export_original_help import validate


def package_help(manifest_path: Path, destination: Path) -> None:
    _, relative_paths = validate(manifest_path)
    # Validate before creating output, and never replace an existing package.
    destination.mkdir(parents=True, exist_ok=False)
    try:
        for relative in relative_paths:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(manifest_path.parent / relative, target)
        shutil.copyfile(manifest_path, destination / "manifest.json")
        validate(destination / "manifest.json")
    except Exception:
        shutil.rmtree(destination)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    if args.destination:
        package_help(args.manifest, args.destination)
    else:
        validate(args.manifest)
    print("Validated private source help for Game and MultiverseJourney")


if __name__ == "__main__":
    main()
