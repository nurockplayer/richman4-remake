#!/usr/bin/env python3
"""Prepare the bounded private S20 source Panel10 artwork slice.

The output keeps the resolved S19 scene manifest and its image paths through
private links, then adds only the Panel10 chunks directly used by the source
shop callbacks.  This utility never materializes the complete original asset
corpus and does not change product code.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from decode_original_images import (  # noqa: E402
    FormatError,
    InputError,
    decode_entry,
    parse_mkf,
    parse_visual_resource,
    write_png,
)
from prepare_inventory_assets import (  # noqa: E402
    _ensure_base_link,
    _merge_image_links,
    _rewrite_base_paths,
)


EDITIONS = ("Game", "MultiverseJourney")
RESOURCE_INDEX = 10
CHUNK_COUNT = 38
ARCHIVE_NAME = "Panel.mkf"
ARCHIVE_KEY = "Panel"
ARCHIVE_MEMBER = "dfw4cskzl_136622/{edition}/Panel.mkf"
EXPECTED_SIGNATURE = "SMP"
PIXEL_FORMAT = "rgb555"

# Mode 0 is cards and mode 1 is tools in BOTH editions. The source mode
# variable selects mode * 16 + the local frame; it is not an edition switch.
SELECTED_CHUNKS = (0, 1, 2, 3, 13, 14, 15, 16, 17, 18, 19, 29, 30, 35, 36, 37)

# fcn_004563f5 draws backgrounds/catalog frames opaquely. Closing first
# restores a background rectangle via fcn_0045643d, then draws frame 3/19
# with fcn_00456418. Ready, closing, buttons and points use source-nonzero.
OPAQUE_CHUNKS = frozenset({0, 1, 16, 17})
TRANSPARENT_CHUNKS = frozenset(set(SELECTED_CHUNKS) - OPAQUE_CHUNKS)
CHUNK_ROLES = {
    0: ("background_card",),
    1: ("catalog_card_frame",),
    2: ("merchant_ready_card",),
    3: ("merchant_closing_card",),
    13: ("tab_card_normal",),
    14: ("tab_card_pressed",),
    15: ("feedback_bubble",),
    16: ("background_tool",),
    17: ("catalog_tool_frame",),
    18: ("merchant_ready_tool",),
    19: ("merchant_closing_tool",),
    29: ("tab_tool_normal",),
    30: ("tab_tool_pressed",),
    35: ("exit_button_normal",),
    36: ("exit_button_pressed",),
    37: ("points_background",),
}

class AssetError(ValueError):
    """A private source or output does not satisfy the bounded contract."""


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AssetError(f"metadata is unreadable: {path}: {error}") from error
    if not isinstance(value, dict):
        raise AssetError(f"metadata must be an object: {path}")
    return value


def _load_identity(path: Path) -> dict[tuple[str, int], dict]:
    """Load and validate the complete pinned Panel10 source identity."""

    identity = _load_json(path)
    if identity.get("schema") != "richman4.source-shop-panel10-identity/v1":
        raise AssetError("Panel10 identity has an unsupported schema")
    records = identity.get("records")
    if not isinstance(records, list) or len(records) != len(EDITIONS):
        raise AssetError("Panel10 identity must contain one record per edition")
    selected: dict[tuple[str, int], dict] = {}
    for record in records:
        if not isinstance(record, dict):
            raise AssetError("Panel10 identity contains a non-object record")
        edition = record.get("edition")
        if edition not in EDITIONS or int(record.get("physical_index", -1)) != RESOURCE_INDEX:
            raise AssetError("Panel10 identity has an unexpected edition or index")
        chunks = record.get("chunks")
        if not isinstance(chunks, list) or len(chunks) != CHUNK_COUNT:
            raise AssetError("Panel10 identity must enumerate chunks 0..37")
        for index, chunk in enumerate(chunks):
            if not isinstance(chunk, dict) or int(chunk.get("index", -1)) != index:
                raise AssetError("Panel10 identity chunk indexes are not contiguous")
            for field in ("width", "height", "x", "y", "pixel_data_sha256"):
                if field not in chunk:
                    raise AssetError(f"Panel10 identity chunk {index} is missing {field}")
            if not isinstance(chunk["pixel_data_sha256"], str):
                raise AssetError("Panel10 identity is missing source pixel hashes")
        selected[(edition, RESOURCE_INDEX)] = record
    if set(selected) != {(edition, RESOURCE_INDEX) for edition in EDITIONS}:
        raise AssetError("Panel10 identity is incomplete")
    return selected


def _resource_record(
    edition: str,
    archive_hash: str,
    payload_hash: str,
    member: str,
    chunks: dict[str, dict],
) -> dict:
    return {
        "resource_index": RESOURCE_INDEX,
        "payload_sha256": payload_hash,
        "signature": EXPECTED_SIGNATURE,
        "format": EXPECTED_SIGNATURE,
        "pixel_format": PIXEL_FORMAT,
        "transparent_word_zero": "per-chunk",
        "source": {
            "edition": edition,
            "archive": ARCHIVE_NAME,
            "resource_index": RESOURCE_INDEX,
            "zip_member": member,
            "payload_sha256": payload_hash,
            "archive_sha256": archive_hash,
        },
        "output": {
            "format": "png",
            "pixel_format": PIXEL_FORMAT,
            "transparent_word_zero": "per-chunk",
        },
        "chunks": chunks,
    }


def _verify_scene_paths(scene: dict, output: Path) -> None:
    paths: list[str] = []

    def collect(value) -> None:
        if isinstance(value, dict):
            for item in value.values():
                collect(item)
        elif isinstance(value, list):
            for item in value:
                collect(item)
        elif isinstance(value, str) and value.startswith("images/"):
            paths.append(value)

    collect(scene)
    missing = [path for path in paths if not (output / path).exists()]
    if missing:
        raise AssetError(f"scene manifest has unresolved image paths: {missing[0]}")


def _ensure_resolved_overlay_links(output: Path, base_manifest: Path) -> None:
    """Expose inherited S19 overlay files at their unchanged scene paths."""

    source_images = base_manifest.parent / "images"
    if not source_images.is_dir():
        raise AssetError(f"existing scene image directory is unavailable: {source_images}")
    target_images = output / "images"
    target_images.mkdir(parents=True, exist_ok=True)
    for child in source_images.iterdir():
        if child.name == "base":
            continue
        _merge_image_links(child, target_images / child.name)


def prepare(
    zip_path: Path,
    output: Path,
    identity_path: Path,
    base_manifest: Path,
) -> dict:
    zip_path = zip_path.expanduser().resolve()
    output = output.expanduser().resolve()
    identity_path = identity_path.expanduser().resolve()
    base_manifest = base_manifest.expanduser().resolve()
    if not zip_path.is_file():
        raise InputError(f"owner ZIP is unavailable: {zip_path}")
    if not identity_path.is_file():
        raise InputError(f"Panel10 identity is unavailable: {identity_path}")
    if not base_manifest.is_file():
        raise InputError(f"resolved scene manifest is unavailable: {base_manifest}")

    identity_document = _load_json(identity_path)
    identity = _load_identity(identity_path)
    base_scene = _load_json(base_manifest)
    if (
        base_scene.get("schema") != "richman4.scene-images/v1"
        or not isinstance(base_scene.get("maps"), list)
        or not isinstance(base_scene.get("characters"), dict)
    ):
        raise AssetError("resolved scene manifest has an unsupported schema")
    # The S19 input is already the resolved scene manifest.  Preserve every
    # existing field/path exactly; rewriting it would incorrectly turn the
    # 34 Panel11 overlay paths back into base paths.
    scene = copy.deepcopy(base_scene)
    scene.setdefault("ui", {})
    if not isinstance(scene["ui"], dict):
        raise AssetError("resolved scene manifest UI section is invalid")

    output.mkdir(parents=True, exist_ok=True)
    resources: dict[str, dict] = {}
    provenance: dict[str, dict] = {}
    with zipfile.ZipFile(zip_path) as archive:
        for edition in EDITIONS:
            member = ARCHIVE_MEMBER.format(edition=edition)
            try:
                panel_data = archive.read(member)
            except KeyError as error:
                raise AssetError(f"owner ZIP is missing {member}") from error
            archive_hash = hashlib.sha256(panel_data).hexdigest()
            mkf = parse_mkf(Path(member), panel_data)
            if len(mkf.entries) <= RESOURCE_INDEX:
                raise AssetError(f"{member} has no Panel resource 10")
            payload = decode_entry(mkf, mkf.entries[RESOURCE_INDEX])
            payload_hash = hashlib.sha256(payload).hexdigest()
            expected = identity[(edition, RESOURCE_INDEX)]
            if archive_hash != expected.get("archive_sha256"):
                raise AssetError(f"{member} archive hash differs from pinned identity")
            if payload_hash != expected.get("payload_sha256"):
                raise AssetError(f"{member} Panel10 payload hash differs from pinned identity")
            visual = parse_visual_resource(payload, mkf.entries[RESOURCE_INDEX])
            if visual is None or visual.signature != EXPECTED_SIGNATURE:
                raise FormatError(f"{member}: Panel10 is not an SMP resource")
            if visual.chunk_count != CHUNK_COUNT:
                raise AssetError(f"{member}: Panel10 has {visual.chunk_count} chunks; expected {CHUNK_COUNT}")
            output_chunks: dict[str, dict] = {}
            identity_chunks = {int(chunk["index"]): chunk for chunk in expected["chunks"]}
            for chunk in visual.chunks:
                if chunk.index not in SELECTED_CHUNKS:
                    continue
                pinned = identity_chunks[chunk.index]
                if (chunk.width, chunk.height, chunk.x, chunk.y) != tuple(int(pinned[key]) for key in ("width", "height", "x", "y")):
                    raise AssetError(f"{member}: Panel10 chunk {chunk.index} geometry differs from pinned identity")
                if hashlib.sha256(chunk.pixels).hexdigest() != pinned["pixel_data_sha256"]:
                    raise AssetError(f"{member}: Panel10 chunk {chunk.index} pixels differ from pinned identity")
                relative = Path("images") / edition / "ui" / ARCHIVE_KEY / str(RESOURCE_INDEX) / f"{chunk.index}.png"
                target = output / relative
                if target.exists() or target.is_symlink():
                    raise AssetError(f"output collision: {relative.as_posix()}")
                transparent = chunk.index in TRANSPARENT_CHUNKS
                write_png(target, chunk, visual, pixel_format=PIXEL_FORMAT, transparent_word_zero=transparent)
                output_chunks[str(chunk.index)] = {
                    "path": relative.as_posix(),
                    "sha256": _sha256(target),
                    "width": chunk.width,
                    "height": chunk.height,
                    "transparent_word_zero": transparent,
                    "source_zero_word_count": sum(1 for offset in range(0, len(chunk.pixels), 2) if chunk.pixels[offset : offset + 2] == b"\x00\x00"),
                    "logical": {"width": chunk.width, "height": chunk.height, "anchor_x": chunk.x, "anchor_y": chunk.y},
                    "roles": list(CHUNK_ROLES.get(chunk.index, ())),
                }
            if set(output_chunks) != {str(index) for index in SELECTED_CHUNKS}:
                raise AssetError(f"{member}: selected Panel10 output is incomplete")
            resources[edition] = _resource_record(edition, archive_hash, payload_hash, member, output_chunks)
            provenance[edition] = {
                "member": member,
                "archive_sha256": archive_hash,
                "payload_sha256": payload_hash,
                "resource_index": RESOURCE_INDEX,
                "signature": EXPECTED_SIGNATURE,
                "chunk_count": visual.chunk_count,
                "selected_chunks": list(SELECTED_CHUNKS),
                "source_identity": str(identity_path),
                "alpha_policy": {
                    "opaque_chunks": sorted(OPAQUE_CHUNKS),
                    "transparent_word_zero_chunks": sorted(TRANSPARENT_CHUNKS),
                    "opaque_callback": "fcn_004563f5 for backgrounds/catalog; fcn_0045643d restores a background region before closing",
                    "sprite_callback": "fcn_00456418 draw_non_zero_image_in_rect for ready/closing/feedback/tab/EXIT/points sprites",
                },
            }

    for edition in EDITIONS:
        group = scene["ui"].setdefault(edition, {}).setdefault(ARCHIVE_KEY, {})
        if not isinstance(group, dict):
            raise AssetError(f"scene UI Panel group is invalid for {edition}")
        group.setdefault("resources", {})[str(RESOURCE_INDEX)] = resources[edition]

    _ensure_base_link(output, base_manifest)
    _ensure_resolved_overlay_links(output, base_manifest)
    _verify_scene_paths(scene, output)
    manifest = {
        "schema": "richman4.source-shop-assets/v1",
        "version": 1,
        "resource_index": RESOURCE_INDEX,
        "selected_chunks": list(SELECTED_CHUNKS),
        "base_manifest": {"path": str(base_manifest), "sha256": _sha256(base_manifest), "schema": scene["schema"]},
        "resources": resources,
        "output": {"format": "png", "pixel_format": PIXEL_FORMAT, "transparent_word_zero": "per-chunk"},
        "provenance": {
            "zip_path": str(zip_path),
            "zip_sha256": _sha256(zip_path),
            "identity_path": str(identity_path),
            "identity_sha256": _sha256(identity_path),
            "decoder_sha256": identity_document.get("decoder_sha256", ""),
            "source_asm_path": identity_document.get("source_asm", {}).get("path", ""),
            "source_asm_sha256": identity_document.get("source_asm", {}).get("sha256", ""),
        },
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "scene-manifest.json").write_text(json.dumps(scene, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    provenance_payload = {
        "schema": "richman4.source-shop-assets-provenance/v1",
        "manifest_sha256": _sha256(output / "manifest.json"),
        "scene_manifest_sha256": _sha256(output / "scene-manifest.json"),
        "base_manifest": manifest["base_manifest"],
        "resources": provenance,
        "decoder_sha256": identity_document.get("decoder_sha256", ""),
        "limits": "Only selected Panel10 source shop chunks decoded; all inherited map/character/UI/S19 Panel11 paths are private links. No product visual or functional PASS claimed.",
    }
    (output / "provenance.json").write_text(json.dumps(provenance_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", dest="zip_path", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--identity", type=Path, required=True)
    parser.add_argument("--base-manifest", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = prepare(args.zip_path, args.output, args.identity, args.base_manifest)
    except (AssetError, InputError, FormatError, OSError, KeyError, IndexError, zipfile.BadZipFile) as error:
        parser.exit(1, f"source shop asset preparation failed: {error}\n")
    print(f"Prepared bounded Panel10 source shop assets: {sum(len(value['chunks']) for value in result['resources'].values())} chunks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
