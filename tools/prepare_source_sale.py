#!/usr/bin/env python3
"""Prepare the bounded private S21 source SALE artwork slice.

Only Panel resources 73 (20 chunks) and 74 (13 chunks) are decoded from each
edition's owner ZIP member; every other inherited scene image keeps its
existing private path through the shared S20 symlink helpers.  The output
never materializes the complete original asset corpus and does not change
product code or layout.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
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
from prepare_inventory_assets import _ensure_base_link  # noqa: E402
from prepare_source_shop import (  # noqa: E402
    _ensure_resolved_overlay_links,
    _verify_scene_paths,
)


EDITIONS = ("Game", "MultiverseJourney")
RESOURCE_INDEXES = (73, 74)
SELECTED_CHUNKS = {
    73: tuple(range(0, 20)),
    74: tuple(range(0, 13)),
}
CHUNK_COUNTS = {73: 20, 74: 13}
ARCHIVE_NAME = "Panel.mkf"
ARCHIVE_KEY = "Panel"
ARCHIVE_MEMBER = "dfw4cskzl_136622/{edition}/Panel.mkf"
EXPECTED_SIGNATURE = "SMP"
PIXEL_FORMAT = "rgb555"
IDENTITY_SCHEMA = "richman4.source-sale-panel7374-identity/v1"
SCENE_SCHEMA = "richman4.scene-images/v1"
EXPECTED_BASE_SHA256 = "6f3acbbc87aada42688e396afcbefc2b418958d30f576fac2eeeeef75fc96c30"
EXPECTED_IDENTITY_SHA256 = "ab4e69bf4066f9b456341d07acc82055bbf4687db4baa7c7cbc944ecf5db5800"
SOURCE_ASM_PATH = (
    "/Users/tachikoma/.codex/worktrees/1e3e/richman4-remake/.local/research-rich4/"
    "asm/rich4_ui_sale.asm"
)
SOURCE_ASM_SHA256 = "750b782654839143d9b9a0ae53fa1a3a037e51982ea03ae28a1b35a6603dfbde"
# fcn_004754ac stores the proven category-detail chunk map as little-endian
# bytes 07 08 06 06 (female 1..4 then male 1..4).
CATEGORY_DETAIL_MAP = (7, 8, 6, 6)

# Panel73 chunks 3/4 (tool/card pickers) are drawn with fcn_00456418
# (non-zero source words are the sprites); every other selected Panel73 chunk
# is drawn opaquely with fcn_004563f5, including chunk 18 (stock checkmark) and
# chunk 19 (property page tab).  Panel74 tool miniatures all use the
# non-zero source draw and keep their recorded anchors.
TRANSPARENT_CHUNKS = {
    73: frozenset({3, 4}),
    74: frozenset(SELECTED_CHUNKS[74]),
}
OPAQUE_CHUNKS = {
    index: frozenset(set(SELECTED_CHUNKS[index]) - set(TRANSPARENT_CHUNKS[index]))
    for index in RESOURCE_INDEXES
}
CHUNK_ROLES = {
    73: {
        0: ("bulletin_board",),
        1: ("stock_picker",),
        2: ("property_picker",),
        3: ("tool_picker",),
        4: ("card_picker",),
        5: ("reference_value_notice",),
        6: ("tool_card_detail",),
        7: ("stock_detail",),
        8: ("property_detail",),
        9: ("female_category_1",),
        10: ("female_category_2",),
        11: ("female_category_3",),
        12: ("female_category_4",),
        13: ("male_category_1",),
        14: ("male_category_2",),
        15: ("male_category_3",),
        16: ("male_category_4",),
        17: ("category_menu",),
        18: ("stock_checkmark",),
        19: ("property_page_tab",),
    },
    74: {index: ("tool_miniature_icon",) for index in SELECTED_CHUNKS[74]},
}
MAX_NEW_OUTPUT_BYTES = 20 * 1024 * 1024
MIN_INHERITED_IMAGE_REFERENCES = 4959


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
    """Load and validate the complete pinned Panel73/74 source identity."""

    identity = _load_json(path)
    if identity.get("schema") != IDENTITY_SCHEMA:
        raise AssetError("Panel73/74 identity has an unsupported schema")
    records = identity.get("records")
    expected_keys = {(edition, index) for edition in EDITIONS for index in RESOURCE_INDEXES}
    if not isinstance(records, list) or len(records) != len(expected_keys):
        raise AssetError("Panel73/74 identity must contain one record per edition and index")
    selected: dict[tuple[str, int], dict] = {}
    for record in records:
        if not isinstance(record, dict):
            raise AssetError("Panel73/74 identity contains a non-object record")
        edition = record.get("edition")
        index = int(record.get("physical_index", -1))
        if edition not in EDITIONS or index not in RESOURCE_INDEXES:
            raise AssetError("Panel73/74 identity has an unexpected edition or index")
        chunks = record.get("chunks")
        if not isinstance(chunks, list) or len(chunks) != CHUNK_COUNTS[index]:
            raise AssetError(f"Panel73/74 identity must enumerate {CHUNK_COUNTS[index]} chunks for {index}")
        for position, chunk in enumerate(chunks):
            if not isinstance(chunk, dict) or int(chunk.get("index", -1)) != position:
                raise AssetError("Panel73/74 identity chunk indexes are not contiguous")
            for field in ("width", "height", "x", "y", "pixel_data_sha256"):
                if field not in chunk:
                    raise AssetError(f"Panel73/74 identity chunk {position} is missing {field}")
            digest = chunk["pixel_data_sha256"]
            if not isinstance(digest, str) or len(digest) != 64 or any(
                character not in "0123456789abcdef" for character in digest
            ):
                raise AssetError("Panel73/74 identity has a malformed source pixel hash")
        selected[(edition, index)] = record
    if set(selected) != expected_keys:
        raise AssetError("Panel73/74 identity is incomplete")
    return selected


def _collect_image_paths(value, paths: list[str]) -> None:
    if isinstance(value, dict):
        for item in value.values():
            _collect_image_paths(item, paths)
    elif isinstance(value, list):
        for item in value:
            _collect_image_paths(item, paths)
    elif isinstance(value, str) and value.startswith("images/"):
        paths.append(value)


def _image_reference_count(scene: dict) -> int:
    paths: list[str] = []
    _collect_image_paths(scene, paths)
    return len(paths)


def _estimate_output_bytes(identity: dict[tuple[str, int], dict]) -> int:
    """Bound the new selected PNG payload before any byte is written."""

    total = 0
    for record in identity.values():
        index = int(record["physical_index"])
        for chunk in record["chunks"]:
            if int(chunk["index"]) not in SELECTED_CHUNKS[index]:
                continue
            # RGBA8 scanlines plus zlib/IDAT overhead; deliberately generous.
            total += int(chunk["width"]) * int(chunk["height"]) * 4 + 4096
    return total


def _enforce_limits(estimate: int, output: Path) -> None:
    if estimate > MAX_NEW_OUTPUT_BYTES:
        raise AssetError(
            f"bounded selected output estimate {estimate} exceeds {MAX_NEW_OUTPUT_BYTES} bytes"
        )
    anchor = output
    while not anchor.exists() and anchor != anchor.parent:
        anchor = anchor.parent
    free = shutil.disk_usage(anchor).free
    if free < estimate * 2:
        raise AssetError(
            f"insufficient free space at {anchor}: {free} bytes free, {estimate} bytes required"
        )


def _preflight_targets(output: Path) -> None:
    for edition in EDITIONS:
        for index in RESOURCE_INDEXES:
            for chunk in SELECTED_CHUNKS[index]:
                target = output / "images" / edition / "ui" / ARCHIVE_KEY / str(index) / f"{chunk}.png"
                if target.exists() or target.is_symlink():
                    raise AssetError(f"output collision: {target}")


def _write_selected_chunk(target: Path, chunk, visual, transparent: bool) -> None:
    if target.exists() or target.is_symlink():
        raise AssetError(f"output collision: {target}")
    write_png(target, chunk, visual, pixel_format=PIXEL_FORMAT, transparent_word_zero=transparent)


def _resource_record(
    edition: str,
    resource_index: int,
    archive_hash: str,
    payload_hash: str,
    member: str,
    chunks: dict[str, dict],
) -> dict:
    return {
        "resource_index": resource_index,
        "payload_sha256": payload_hash,
        "signature": EXPECTED_SIGNATURE,
        "format": EXPECTED_SIGNATURE,
        "pixel_format": PIXEL_FORMAT,
        "transparent_word_zero": "per-chunk",
        "source": {
            "edition": edition,
            "archive": ARCHIVE_NAME,
            "resource_index": resource_index,
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


def _overlay_scene(base_scene: dict, resources: dict[str, dict]) -> dict:
    """Return a copy of the resolved base scene with only 73/74 added."""

    scene = copy.deepcopy(base_scene)
    scene.setdefault("ui", {})
    if not isinstance(scene["ui"], dict):
        raise AssetError("resolved scene manifest UI section is invalid")
    for edition in EDITIONS:
        group = scene["ui"].setdefault(edition, {}).setdefault(ARCHIVE_KEY, {})
        if not isinstance(group, dict):
            raise AssetError(f"scene UI Panel group is invalid for {edition}")
        resources_map = group.setdefault("resources", {})
        if not isinstance(resources_map, dict):
            raise AssetError(f"scene UI Panel resources are invalid for {edition}")
        for index in RESOURCE_INDEXES:
            key = str(index)
            if key in resources_map:
                raise AssetError(f"scene Panel resource {key} already exists for {edition}")
            resources_map[key] = resources[edition][key]
    return scene


def prepare(
    zip_path: Path,
    output: Path,
    identity_path: Path,
    base_manifest: Path,
    expected_base_sha256: str | None = None,
    expected_identity_sha256: str | None = None,
) -> dict:
    zip_path = zip_path.expanduser().resolve()
    output = output.expanduser().resolve()
    identity_path = identity_path.expanduser().resolve()
    base_manifest = base_manifest.expanduser().resolve()
    if not zip_path.is_file():
        raise InputError(f"owner ZIP is unavailable: {zip_path}")
    if not identity_path.is_file():
        raise InputError(f"Panel73/74 identity is unavailable: {identity_path}")
    if not base_manifest.is_file():
        raise InputError(f"resolved scene manifest is unavailable: {base_manifest}")
    if expected_base_sha256 is not None and _sha256(base_manifest) != expected_base_sha256:
        raise AssetError("resolved scene manifest is not the pinned latest base")
    if expected_identity_sha256 is not None and _sha256(identity_path) != expected_identity_sha256:
        raise AssetError("Panel73/74 identity does not match the frozen input")

    identity = _load_identity(identity_path)
    base_scene = _load_json(base_manifest)
    if (
        base_scene.get("schema") != SCENE_SCHEMA
        or not isinstance(base_scene.get("maps"), list)
        or not isinstance(base_scene.get("characters"), dict)
    ):
        raise AssetError("resolved scene manifest has an unsupported schema")
    if len([record for record in identity.values()]) != len(EDITIONS) * len(RESOURCE_INDEXES):
        raise AssetError("Panel73/74 identity is incomplete")

    estimate = _estimate_output_bytes(identity)
    _enforce_limits(estimate, output)
    output.mkdir(parents=True, exist_ok=True)
    _preflight_targets(output)

    resources: dict[str, dict] = {edition: {} for edition in EDITIONS}
    provenance: dict[str, dict] = {edition: {} for edition in EDITIONS}
    with zipfile.ZipFile(zip_path) as archive:
        for edition in EDITIONS:
            member = ARCHIVE_MEMBER.format(edition=edition)
            try:
                panel_data = archive.read(member)
            except KeyError as error:
                raise AssetError(f"owner ZIP is missing {member}") from error
            archive_hash = hashlib.sha256(panel_data).hexdigest()
            mkf = parse_mkf(Path(member), panel_data)
            for index in RESOURCE_INDEXES:
                if len(mkf.entries) <= index:
                    raise AssetError(f"{member} has no Panel resource {index}")
                expected = identity[(edition, index)]
                if archive_hash != expected.get("archive_sha256"):
                    raise AssetError(f"{member} archive hash differs from pinned identity")
                payload = decode_entry(mkf, mkf.entries[index])
                payload_hash = hashlib.sha256(payload).hexdigest()
                if payload_hash != expected.get("payload_sha256"):
                    raise AssetError(f"{member} Panel{index} payload hash differs from pinned identity")
                visual = parse_visual_resource(payload, mkf.entries[index])
                if visual is None or visual.signature != EXPECTED_SIGNATURE:
                    raise FormatError(f"{member}: Panel{index} is not an SMP resource")
                if visual.chunk_count != CHUNK_COUNTS[index]:
                    raise AssetError(
                        f"{member}: Panel{index} has {visual.chunk_count} chunks; expected {CHUNK_COUNTS[index]}"
                    )
                identity_chunks = {int(chunk["index"]): chunk for chunk in expected["chunks"]}
                output_chunks: dict[str, dict] = {}
                for chunk in visual.chunks:
                    if chunk.index not in SELECTED_CHUNKS[index]:
                        continue
                    pinned = identity_chunks[chunk.index]
                    if (chunk.width, chunk.height, chunk.x, chunk.y) != tuple(
                        int(pinned[key]) for key in ("width", "height", "x", "y")
                    ):
                        raise AssetError(
                            f"{member}: Panel{index} chunk {chunk.index} geometry differs from pinned identity"
                        )
                    if hashlib.sha256(chunk.pixels).hexdigest() != pinned["pixel_data_sha256"]:
                        raise AssetError(
                            f"{member}: Panel{index} chunk {chunk.index} pixels differ from pinned identity"
                        )
                    relative = (
                        Path("images") / edition / "ui" / ARCHIVE_KEY / str(index) / f"{chunk.index}.png"
                    )
                    target = output / relative
                    transparent = chunk.index in TRANSPARENT_CHUNKS[index]
                    _write_selected_chunk(target, chunk, visual, transparent)
                    output_chunks[str(chunk.index)] = {
                        "path": relative.as_posix(),
                        "sha256": _sha256(target),
                        "width": chunk.width,
                        "height": chunk.height,
                        "transparent_word_zero": transparent,
                        "source_zero_word_count": sum(
                            1
                            for offset in range(0, len(chunk.pixels), 2)
                            if chunk.pixels[offset : offset + 2] == b"\x00\x00"
                        ),
                        "logical": {
                            "width": chunk.width,
                            "height": chunk.height,
                            "anchor_x": chunk.x,
                            "anchor_y": chunk.y,
                        },
                        "roles": list(CHUNK_ROLES[index].get(chunk.index, ())),
                    }
                if set(output_chunks) != {str(value) for value in SELECTED_CHUNKS[index]}:
                    raise AssetError(f"{member}: selected Panel{index} output is incomplete")
                resources[edition][str(index)] = _resource_record(
                    edition, index, archive_hash, payload_hash, member, output_chunks
                )
                provenance[edition][str(index)] = {
                    "member": member,
                    "archive_sha256": archive_hash,
                    "payload_sha256": payload_hash,
                    "resource_index": index,
                    "signature": EXPECTED_SIGNATURE,
                    "chunk_count": visual.chunk_count,
                    "selected_chunks": list(SELECTED_CHUNKS[index]),
                    "transparent_word_zero_chunks": sorted(TRANSPARENT_CHUNKS[index]),
                    "opaque_chunks": sorted(OPAQUE_CHUNKS[index]),
                    "alpha_policy": {
                        "transparent_word_zero": "non-zero source words are sprites (fcn_00456418)",
                        "opaque": "source words always drawn (fcn_004563f5)",
                    },
                    "roles": {str(key): list(value) for key, value in sorted(CHUNK_ROLES[index].items())},
                }

    base_refs = _image_reference_count(base_scene)
    if base_refs < MIN_INHERITED_IMAGE_REFERENCES:
        raise AssetError(
            f"resolved base scene has only {base_refs} image references; expected at least {MIN_INHERITED_IMAGE_REFERENCES}"
        )
    scene = _overlay_scene(base_scene, resources)
    new_refs = _image_reference_count(scene)
    if new_refs != base_refs + len(EDITIONS) * sum(len(SELECTED_CHUNKS[index]) for index in RESOURCE_INDEXES):
        raise AssetError("overlay scene does not add exactly the selected 66 image references")

    _ensure_base_link(output, base_manifest)
    _ensure_resolved_overlay_links(output, base_manifest)
    _verify_scene_paths(scene, output)

    base_paths: list[str] = []
    _collect_image_paths(base_scene, base_paths)
    new_paths: list[str] = []
    _collect_image_paths(scene, new_paths)
    if not set(base_paths).issubset(set(new_paths)):
        raise AssetError("overlay scene dropped inherited image references")

    source_asm_sha = ""
    asm_path = Path(SOURCE_ASM_PATH)
    if asm_path.is_file():
        source_asm_sha = _sha256(asm_path)

    manifest = {
        "schema": "richman4.source-sale-assets/v1",
        "version": 1,
        "resource_indexes": list(RESOURCE_INDEXES),
        "selected_chunks": {str(index): list(SELECTED_CHUNKS[index]) for index in RESOURCE_INDEXES},
        "chunk_roles": {
            edition: {
                str(index): {
                    str(key): list(value) for key, value in sorted(CHUNK_ROLES[index].items())
                }
                for index in RESOURCE_INDEXES
            }
            for edition in EDITIONS
        },
        "alpha_policy": {
            str(index): {
                "transparent_word_zero_chunks": sorted(TRANSPARENT_CHUNKS[index]),
                "opaque_chunks": sorted(OPAQUE_CHUNKS[index]),
            }
            for index in RESOURCE_INDEXES
        },
        "category_detail_map": list(CATEGORY_DETAIL_MAP),
        "base_manifest": {
            "path": str(base_manifest),
            "sha256": _sha256(base_manifest),
            "schema": base_scene["schema"],
        },
        "resources": resources,
        "output": {
            "format": "png",
            "pixel_format": PIXEL_FORMAT,
            "transparent_word_zero": "per-chunk",
            "png_count": len(EDITIONS) * sum(len(SELECTED_CHUNKS[index]) for index in RESOURCE_INDEXES),
            "estimated_bytes": estimate,
        },
        "provenance": {
            "zip_path": str(zip_path),
            "zip_sha256": _sha256(zip_path),
            "identity_path": str(identity_path),
            "identity_sha256": _sha256(identity_path),
            "source_asm_path": str(asm_path),
            "source_asm_sha256": source_asm_sha,
        },
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output / "scene-manifest.json").write_text(
        json.dumps(scene, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    provenance_payload = {
        "schema": "richman4.source-sale-assets-provenance/v1",
        "manifest_sha256": _sha256(output / "manifest.json"),
        "scene_manifest_sha256": _sha256(output / "scene-manifest.json"),
        "base_manifest": manifest["base_manifest"],
        "resources": provenance,
        "identity_sha256": manifest["provenance"]["identity_sha256"],
        "source_asm_sha256": source_asm_sha,
        "category_detail_map": list(CATEGORY_DETAIL_MAP),
        "inherited_image_references": base_refs,
        "limits": (
            "Only selected Panel73/74 source SALE chunks decoded; every inherited map/character/UI/"
            "S19/S20 image path is preserved through private links. No product visual or functional PASS claimed."
        ),
    }
    (output / "provenance.json").write_text(
        json.dumps(provenance_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", dest="zip_path", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--identity", type=Path, required=True)
    parser.add_argument("--base-manifest", type=Path, required=True)
    parser.add_argument("--expected-base-sha256", default=None)
    parser.add_argument("--expected-identity-sha256", default=None)
    args = parser.parse_args()
    try:
        result = prepare(
            args.zip_path,
            args.output,
            args.identity,
            args.base_manifest,
            args.expected_base_sha256,
            args.expected_identity_sha256,
        )
    except (AssetError, InputError, FormatError, OSError, KeyError, IndexError, zipfile.BadZipFile) as error:
        parser.exit(1, f"source SALE asset preparation failed: {error}\n")
    print(f"Prepared bounded source SALE assets: {result['output']['png_count']} PNG chunks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
