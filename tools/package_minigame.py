#!/usr/bin/env python3
"""Copy the validated private minigame input plane into a package directory.

Only the manifest and the input files it references (penguin click mask and
source coordinate grid) are copied; minigame artwork comes from the scene
bundle.  The packaged manifest lets the game resolve the same input data from
``Contents/Resources/Original/minigame`` instead of a development fallback.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil

SCHEMA = "richman4.minigame-assets/v1"
MASK_WIDTH = 640
MASK_HEIGHT = 480
MASK_BYTES = MASK_WIDTH * MASK_HEIGHT
GRID_RECORDS = 81
_HEX = set("0123456789abcdef")


def _safe_relative(value) -> Path:
    if not isinstance(value, str) or not value:
        raise ValueError("minigame input path must be a non-empty string")
    if "\x00" in value or "\\" in value:
        raise ValueError(f"minigame input path has an unsupported character: {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or any(part in ("", "..") for part in pure.parts):
        raise ValueError(f"minigame input path escapes the manifest: {value!r}")
    return Path(*pure.parts)


def _entry(inputs, name: str) -> tuple[Path, dict]:
    entry = inputs.get(name) if isinstance(inputs, dict) else None
    if not isinstance(entry, dict):
        raise ValueError(f"minigame input {name} is missing")
    relative = _safe_relative(entry.get("path"))
    digest = entry.get("sha256")
    if (
        not isinstance(digest, str)
        or len(digest) != 64
        or any(character not in _HEX for character in digest)
    ):
        raise ValueError(f"minigame input {name} has no valid sha256")
    return relative, entry


def _checked(base: Path, relative: Path, entry: dict, *, context: str) -> bytes:
    source = base / relative
    if source.is_symlink() or not source.is_file():
        raise ValueError(f"{context} is not a regular file: {relative.as_posix()}")
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != entry["sha256"]:
        raise ValueError(f"{context} digest mismatch: {relative.as_posix()}")
    return data


def validate(manifest_path: Path) -> tuple[dict, list[Path]]:
    manifest_path = manifest_path.expanduser().resolve()
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError(f"minigame manifest is not a regular file: {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"minigame manifest {manifest_path}: invalid JSON ({error})") from error
    if not isinstance(manifest, dict) or manifest.get("schema") != SCHEMA:
        raise ValueError("unsupported minigame manifest schema")
    if manifest.get("version") != 1:
        raise ValueError("unsupported minigame manifest version")
    inputs = manifest.get("input")
    mask_relative, mask_entry = _entry(inputs, "penguin_mask")
    grid_relative, grid_entry = _entry(inputs, "penguin_grid")
    if mask_relative == grid_relative:
        raise ValueError("minigame input files must be distinct")
    base = manifest_path.parent
    mask = _checked(base, mask_relative, mask_entry, context="penguin mask")
    if len(mask) != MASK_BYTES:
        raise ValueError(f"penguin mask must be {MASK_BYTES} bytes")
    if "width" in mask_entry and mask_entry["width"] != MASK_WIDTH:
        raise ValueError("penguin mask width does not match its bytes")
    if "height" in mask_entry and mask_entry["height"] != MASK_HEIGHT:
        raise ValueError("penguin mask height does not match its bytes")
    grid_data = _checked(base, grid_relative, grid_entry, context="penguin grid")
    try:
        grid = json.loads(grid_data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"penguin grid is not valid JSON ({error})") from error
    records = grid.get("records") if isinstance(grid, dict) else None
    if not isinstance(records, list) or len(records) != GRID_RECORDS:
        raise ValueError(f"penguin grid must have {GRID_RECORDS} records")
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("x"), (int, float)) or not isinstance(record.get("y"), (int, float)):
            raise ValueError("penguin grid record has no numeric x/y")
    return manifest, [mask_relative, grid_relative]


def package_minigame(manifest_path: Path, destination: Path) -> None:
    manifest_path = manifest_path.expanduser().resolve()
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
    except BaseException:
        shutil.rmtree(destination, ignore_errors=True)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    if args.destination:
        package_minigame(args.manifest, args.destination)
    else:
        validate(args.manifest)
    print("Validated private minigame input manifest")


if __name__ == "__main__":
    main()
