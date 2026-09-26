#!/usr/bin/env python3
"""Validate and optionally copy only manifest-referenced private scene PNGs."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct


def _image_records(value):
    if isinstance(value, dict):
        if "path" in value:
            yield value
        for child in value.values():
            yield from _image_records(child)
    elif isinstance(value, list):
        for child in value:
            yield from _image_records(child)


def _safe_relative(relative):
    return (isinstance(relative, str) and relative.startswith("images/")
            and ".." not in relative.split("/") and "\\" not in relative)


def _checked_image(source: Path, record: dict, relative: str) -> tuple[Path, str, int, int]:
    resolved = source.resolve()
    if not resolved.is_file():
        raise ValueError(f"scene image is unavailable: {relative}")
    data = resolved.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != record.get("sha256"):
        raise ValueError(f"scene image digest mismatch: {relative}")
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"invalid scene PNG: {relative}")
    width, height = struct.unpack_from(">II", data, 16)
    if not (0 < width <= 16384 and 0 < height <= 16384):
        raise ValueError("scene PNG dimensions out of range")
    if (width, height) != (record.get("width"), record.get("height")):
        raise ValueError("scene PNG dimensions mismatch")
    return resolved, digest, width, height


def _base_allowlist(path: Path) -> dict[str, tuple[Path, str, int, int]]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or manifest.get("schema") != "richman4.scene-images/v1":
        raise ValueError("unsupported base scene manifest")
    if not isinstance(manifest.get("maps"), list) or not manifest["maps"]:
        raise ValueError("base scene manifest has no maps")
    if not isinstance(manifest.get("characters"), dict):
        raise ValueError("invalid base scene characters")
    allowed = {}
    for record in _image_records(manifest):
        relative = record.get("path")
        if not _safe_relative(relative):
            raise ValueError("unsafe base scene image path")
        source = path.resolve().parent / relative
        identity = _checked_image(source, record, relative)
        transformed = relative if relative.startswith("images/base/") else "images/base/" + relative[len("images/"):]
        if transformed in allowed and allowed[transformed] != identity:
            raise ValueError(f"ambiguous transformed base image path: {transformed}")
        allowed[transformed] = identity
    return allowed


def validate(path: Path, base_manifest: Path | None = None) -> tuple[dict, list[Path]]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or manifest.get("schema") != "richman4.scene-images/v1":
        raise ValueError("unsupported scene manifest")
    if not isinstance(manifest.get("maps"), list) or not manifest["maps"]:
        raise ValueError("scene manifest has no maps")
    if not isinstance(manifest.get("characters"), dict):
        raise ValueError("invalid scene characters")
    base = path.resolve().parent
    allowed_base = _base_allowlist(Path(base_manifest)) if base_manifest is not None else {}
    paths = set()
    identities = {}
    dimensions = {}

    def visit(value):
        if isinstance(value, dict):
            if "frames" in value:
                if not isinstance(value["frames"], list):
                    raise ValueError("invalid sprite frames")
                for frame in value["frames"]:
                    logical = frame.get("logical") if isinstance(frame, dict) else None
                    if not isinstance(logical, dict) or any(
                        type(logical.get(key)) is not int or not (1 if key in ("width", "height") else -65535) <= logical[key] <= 65535
                        for key in ("width", "height", "anchor_x", "anchor_y")
                    ):
                        raise ValueError("invalid sprite logical bounds")
            if "path" in value:
                relative = value["path"]
                if not _safe_relative(relative):
                    raise ValueError("unsafe scene image path")
                source = base / relative
                resolved = source.resolve()
                if not resolved.is_relative_to(base):
                    identity = _checked_image(source, value, relative)
                    if not relative.startswith("images/base/") or allowed_base.get(relative) != identity:
                        raise ValueError(f"scene image escapes manifest directory without exact base record: {relative}")
                else:
                    identity = _checked_image(source, value, relative)
                if relative in allowed_base and allowed_base[relative] != identity:
                    raise ValueError(f"transformed base image path collision: {relative}")
                if relative in identities and identities[relative] != identity:
                    raise ValueError(f"scene image path collision: {relative}")
                identities[relative] = identity
                paths.add(Path(relative))
                dimensions[relative] = identity[2:]
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(manifest)
    for scene in manifest["maps"]:
        rect = scene.get("world_rect")
        if not isinstance(rect, dict) or any(
            type(rect.get(key)) is not int or not (1 if key in ("width", "height") else -65535) <= rect[key] <= 65535
            for key in ("x", "y", "width", "height")
        ):
            raise ValueError("invalid scene world rectangle")
        if Path(scene["image"]["path"]) not in paths:
            raise ValueError("missing scene background")
    return manifest, sorted(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--base-manifest", type=Path)
    args = parser.parse_args()
    _, paths = validate(args.manifest, base_manifest=args.base_manifest)
    if args.destination:
        args.destination.mkdir(parents=True, exist_ok=False)
        for relative in paths:
            target = args.destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile((args.manifest.parent / relative).resolve(), target)
        shutil.copyfile(args.manifest, args.destination / "manifest.json")
        validate(args.destination / "manifest.json")
    print(f"Validated {len(paths)} private scene images")


if __name__ == "__main__":
    main()
