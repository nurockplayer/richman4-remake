#!/usr/bin/env python3
"""Validate and optionally copy only manifest-referenced private scene PNGs."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct


def validate(path: Path) -> tuple[dict, list[Path]]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or manifest.get("schema") != "richman4.scene-images/v1":
        raise ValueError("unsupported scene manifest")
    if not isinstance(manifest.get("maps"), list) or not manifest["maps"]:
        raise ValueError("scene manifest has no maps")
    if not isinstance(manifest.get("characters"), dict):
        raise ValueError("invalid scene characters")
    base = path.resolve().parent
    paths = set()

    def visit(value):
        if isinstance(value, dict):
            if "path" in value:
                relative = value["path"]
                if (not isinstance(relative, str) or not relative.startswith("images/")
                        or ".." in relative or "\\" in relative):
                    raise ValueError("unsafe scene image path")
                source = (base / relative).resolve()
                if not source.is_relative_to(base):
                    raise ValueError("scene image escapes manifest directory")
                data = source.read_bytes()
                if hashlib.sha256(data).hexdigest() != value.get("sha256"):
                    raise ValueError(f"scene image digest mismatch: {relative}")
                if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
                    raise ValueError(f"invalid scene PNG: {relative}")
                width, height = struct.unpack_from(">II", data, 16)
                if not (0 < width <= 4096 and 0 < height <= 4096):
                    raise ValueError("scene PNG dimensions out of range")
                paths.add(Path(relative))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(manifest)
    for scene in manifest["maps"]:
        if scene.get("width") != 2304 or scene.get("height") != 2304:
            raise ValueError("unsupported scene dimensions")
        if Path(scene["image"]["path"]) not in paths:
            raise ValueError("missing scene background")
    return manifest, sorted(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    _, paths = validate(args.manifest)
    if args.destination:
        args.destination.mkdir(parents=True, exist_ok=False)
        for relative in paths:
            target = args.destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(args.manifest.parent / relative, target)
        shutil.copyfile(args.manifest, args.destination / "manifest.json")
        validate(args.destination / "manifest.json")
    print(f"Validated {len(paths)} private scene images")


if __name__ == "__main__":
    main()
