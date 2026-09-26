#!/usr/bin/env python3
"""Prepare the bounded private Panel11 inventory artwork slice.

Only Panel resource 11, chunks 0..16, is decoded from each owner's ZIP
member.  The scene overlay reuses the existing private scene manifest and
image paths; it does not copy the map, character, font, or other UI assets.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
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


EDITIONS = ("Game", "MultiverseJourney")
RESOURCE_INDEX = 11
CHUNK_COUNT = 17
TRANSPARENT_CHUNKS = frozenset(range(2, 15))
ARCHIVE_NAME = "Panel.mkf"
ARCHIVE_KEY = "Panel"
ARCHIVE_MEMBER = "dfw4cskzl_136622/{edition}/Panel.mkf"
EXPECTED_SIGNATURE = "SMP"
PIXEL_FORMAT = "rgb555"


class AssetError(ValueError):
    """A private source or output does not satisfy the bounded contract."""


def _preflight_destination(output: Path, relative: str | Path, *, allow_leaf_symlink: bool = False) -> Path:
    """Validate an owned destination without following a redirected parent."""
    relative = Path(relative)
    if relative.is_absolute() or not relative.parts or any(part in ("", ".", "..") for part in relative.parts):
        raise AssetError(f"unsafe publication destination: {relative}")
    root = output.resolve()
    target = root / relative
    current = root
    for part in relative.parts[:-1]:
        current = current / part
        if current.is_symlink():
            raise AssetError(f"publication parent is a symlink: {current}")
        if current.exists() and not current.is_dir():
            raise AssetError(f"publication parent is not a directory: {current}")
    resolved_parent = target.parent.resolve()
    if resolved_parent != root and root not in resolved_parent.parents:
        raise AssetError(f"publication destination escapes output root: {relative}")
    if target.is_symlink() and not allow_leaf_symlink:
        raise AssetError(f"publication destination is a symlink: {relative}")
    return target


def _preflight_write_set(output: Path, destinations: list[tuple[str | Path, bool]]) -> list[Path]:
    """Check all owned writes and reject aliases before the first live change."""
    targets = [_preflight_destination(output, relative, allow_leaf_symlink=allow_link) for relative, allow_link in destinations]
    resolved = [target.resolve(strict=False) for target in targets]
    if len(set(resolved)) != len(resolved):
        raise AssetError("publication write set contains aliased destinations")
    return targets


def _scene_image_inputs(scene: dict, manifest_path: Path) -> list[Path]:
    """Return canonical backing paths for every image referenced by a scene."""
    paths: list[Path] = []

    def collect(value):
        if isinstance(value, dict):
            for item in value.values():
                collect(item)
        elif isinstance(value, list):
            for item in value:
                collect(item)
        elif isinstance(value, str) and value.startswith("images/"):
            paths.append(manifest_path.parent / value)
    collect(scene)
    return paths


def _preflight_replacement_inputs(inputs: list[Path], targets: list[Path]) -> None:
    """Reject inputs whose canonical backing paths are removed by replacement."""
    canonical_inputs = {path.expanduser().resolve(strict=False) for path in inputs}
    for target in targets:
        # Replacing a symlink only removes the link entry; its referent is safe.
        if target.is_symlink():
            continue
        canonical_target = target.expanduser().resolve(strict=False)
        if canonical_target in canonical_inputs:
            raise AssetError(f"publication destination is also an input: {target}")
        if target.is_dir() and any(canonical_target in path.parents for path in canonical_inputs):
            raise AssetError(f"publication would remove an input-containing directory: {target}")


def _rewrite_base_paths(value):
    """Repoint existing scene image records through the private base link."""

    if isinstance(value, dict):
        return {key: _rewrite_base_paths(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_rewrite_base_paths(item) for item in value]
    if isinstance(value, str) and value.startswith("images/") and not value.startswith("images/base/"):
        return "images/base/" + value[len("images/"):]
    return value


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
    identity = _load_json(path)
    records = identity.get("records")
    if not isinstance(records, list) or len(records) != len(EDITIONS):
        raise AssetError("Panel11 identity must contain one record per edition")
    selected: dict[tuple[str, int], dict] = {}
    for record in records:
        if not isinstance(record, dict):
            raise AssetError("Panel11 identity contains a non-object record")
        edition = record.get("edition")
        if edition not in EDITIONS or int(record.get("physical_index", -1)) != RESOURCE_INDEX:
            raise AssetError("Panel11 identity has an unexpected edition or index")
        chunks = record.get("chunks")
        if not isinstance(chunks, list) or len(chunks) != CHUNK_COUNT:
            raise AssetError("Panel11 identity must enumerate chunks 0..16")
        for index, chunk in enumerate(chunks):
            if not isinstance(chunk, dict) or int(chunk.get("index", -1)) != index:
                raise AssetError("Panel11 identity chunk indexes are not contiguous")
            if not isinstance(chunk.get("pixel_data_sha256"), str):
                raise AssetError("Panel11 identity is missing source pixel hashes")
        selected[(edition, RESOURCE_INDEX)] = record
    if set(selected) != {(edition, RESOURCE_INDEX) for edition in EDITIONS}:
        raise AssetError("Panel11 identity is incomplete")
    return selected


def _scene_overlay_resource(
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


def _prepare_into(
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
        raise InputError(f"Panel11 identity is unavailable: {identity_path}")
    if not base_manifest.is_file():
        raise InputError(f"existing scene manifest is unavailable: {base_manifest}")
    identity_document = _load_json(identity_path)
    identity = _load_identity(identity_path)
    scene = _load_json(base_manifest)
    if scene.get("schema") != "richman4.scene-images/v1" or not isinstance(scene.get("maps"), list) or not isinstance(scene.get("characters"), dict):
        raise AssetError("existing scene manifest has an unsupported schema")
    scene = _rewrite_base_paths(scene)
    scene.setdefault("ui", {})
    if not isinstance(scene["ui"], dict):
        raise AssetError("existing scene manifest UI section is invalid")
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
                raise AssetError(f"{member} has no Panel resource 11")
            payload = decode_entry(mkf, mkf.entries[RESOURCE_INDEX])
            payload_hash = hashlib.sha256(payload).hexdigest()
            expected = identity[(edition, RESOURCE_INDEX)]
            if archive_hash != expected.get("archive_sha256"):
                raise AssetError(f"{member} archive hash differs from pinned identity")
            if payload_hash != expected.get("payload_sha256"):
                raise AssetError(f"{member} Panel11 payload hash differs from pinned identity")
            visual = parse_visual_resource(payload, mkf.entries[RESOURCE_INDEX])
            if visual is None or visual.signature != EXPECTED_SIGNATURE:
                raise FormatError(f"{member}: Panel11 is not an SMP resource")
            if visual.chunk_count != CHUNK_COUNT:
                raise AssetError(f"{member}: Panel11 has {visual.chunk_count} chunks; expected {CHUNK_COUNT}")
            output_chunks: dict[str, dict] = {}
            identity_chunks = {int(chunk["index"]): chunk for chunk in expected["chunks"]}
            for chunk in visual.chunks:
                pinned = identity_chunks[chunk.index]
                if (chunk.width, chunk.height, chunk.x, chunk.y) != tuple(int(pinned[key]) for key in ("width", "height", "x", "y")):
                    raise AssetError(f"{member}: Panel11 chunk {chunk.index} geometry differs from pinned identity")
                if hashlib.sha256(chunk.pixels).hexdigest() != pinned["pixel_data_sha256"]:
                    raise AssetError(f"{member}: Panel11 chunk {chunk.index} pixels differ from pinned identity")
                relative = Path("images") / edition / "ui" / ARCHIVE_KEY / str(RESOURCE_INDEX) / f"{chunk.index}.png"
                target = output / relative
                if target.exists() or target.is_symlink():
                    raise AssetError(f"output collision: {relative.as_posix()}")
                # The source caller uses the non-zero draw path only for
                # chunks 2..14. Background chunks 0/1 and vehicle chunks
                # 15/16 use the opaque draw path.
                transparent = chunk.index in TRANSPARENT_CHUNKS
                write_png(target, chunk, visual, pixel_format=PIXEL_FORMAT, transparent_word_zero=transparent)
                output_chunks[str(chunk.index)] = {
                    "path": relative.as_posix(),
                    "sha256": _sha256(target),
                    "width": chunk.width,
                    "height": chunk.height,
                    "transparent_word_zero": transparent,
                    "logical": {"width": chunk.width, "height": chunk.height, "anchor_x": chunk.x, "anchor_y": chunk.y},
                }
            resources[edition] = _scene_overlay_resource(edition, archive_hash, payload_hash, member, output_chunks)
            provenance[edition] = {
                "member": member,
                "archive_sha256": archive_hash,
                "payload_sha256": payload_hash,
                "resource_index": RESOURCE_INDEX,
                "signature": EXPECTED_SIGNATURE,
                "chunk_count": visual.chunk_count,
                "source_identity": str(identity_path),
                "alpha_policy": {"chunks_0_1_15_16": "opaque source/caller draw", "chunks_2_14": "WORD 0 transparent per source icon caller"},
            }
    for edition in EDITIONS:
        group = scene["ui"].setdefault(edition, {}).setdefault(ARCHIVE_KEY, {})
        group["archive_sha256"] = resources[edition]["source"]["archive_sha256"]
        group.setdefault("resources", {})[str(RESOURCE_INDEX)] = resources[edition]
    _ensure_base_link(output, base_manifest)
    manifest = {
        "schema": "richman4.inventory-assets/v1",
        "version": 1,
        "resource_index": RESOURCE_INDEX,
        "base_manifest": {"path": str(base_manifest), "sha256": _sha256(base_manifest), "schema": scene["schema"]},
        "resources": resources,
        "output": {"format": "png", "pixel_format": PIXEL_FORMAT, "transparent_word_zero": "per-chunk"},
        "provenance": {"zip_path": str(zip_path), "zip_sha256": _sha256(zip_path), "identity_path": str(identity_path), "identity_sha256": _sha256(identity_path), "decoder_sha256": identity_document.get("decoder_sha256", "")},
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "scene-manifest.json").write_text(json.dumps(scene, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    provenance_payload = {"schema": "richman4.inventory-assets-provenance/v1", "manifest_sha256": _sha256(output / "manifest.json"), "scene_manifest_sha256": _sha256(output / "scene-manifest.json"), "base_manifest": manifest["base_manifest"], "resources": provenance, "decoder_sha256": identity_document.get("decoder_sha256", ""), "limits": "Only Panel11 chunks 0..16 decoded; existing scene/map/character/font assets referenced by symlink and manifest paths. No caller equivalence or product visual PASS claimed."}
    (output / "provenance.json").write_text(json.dumps(provenance_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def prepare(zip_path: Path, output: Path, identity_path: Path, base_manifest: Path) -> dict:
    """Generate in a private staging directory, then publish the bounded slice."""
    zip_path = zip_path.expanduser().resolve()
    output = output.expanduser().resolve()
    identity_path = identity_path.expanduser().resolve()
    base_manifest = base_manifest.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    staged = Path(tempfile.mkdtemp(prefix=".inventory-prepare-", dir=output.parent))
    try:
        manifest = _prepare_into(zip_path, staged, identity_path, base_manifest)
        scene = _load_json(staged / "scene-manifest.json")
        paths: list[str] = []
        def collect(value):
            if isinstance(value, dict):
                for item in value.values(): collect(item)
            elif isinstance(value, list):
                for item in value: collect(item)
            elif isinstance(value, str) and value.startswith("images/"):
                paths.append(value)
        collect(scene)
        missing = [item for item in paths if not (staged / item).is_file()]
        if missing:
            raise AssetError(f"scene manifest has unresolved image paths: {missing[0]}")
        # Validate the complete owned write set before moving any live entry.
        staged_pngs = [staged / record["path"] for value in manifest["resources"].values() for record in value["chunks"].values()]
        destinations = [source.relative_to(staged) for source in staged_pngs]
        destinations.extend(Path(name) for name in ("images/base", "manifest.json", "scene-manifest.json", "provenance.json"))
        allow_leaf_links = {"images/base", "manifest.json", "scene-manifest.json", "provenance.json"}
        owned_targets = _preflight_write_set(output, [(path, path.as_posix() in allow_leaf_links) for path in destinations])
        _preflight_replacement_inputs(
            [zip_path, identity_path, base_manifest, *_scene_image_inputs(_load_json(base_manifest), base_manifest)],
            [owned_targets[len(staged_pngs)], *owned_targets[len(staged_pngs) + 1:]],
        )
        for target in owned_targets[len(staged_pngs) + 1:]:
            if target.exists() and not target.is_symlink() and not target.is_file():
                raise AssetError(f"metadata publication destination is not a regular file or symlink: {target.name}")
        targets = list(zip(staged_pngs, owned_targets[:len(staged_pngs)]))
        collisions = [target for _, target in targets if target.exists() or target.is_symlink()]
        if collisions:
            raise AssetError(f"output collision: {collisions[0].relative_to(output).as_posix()}")
        output.mkdir(parents=True, exist_ok=True)
        staged_base = staged / "images" / "base"
        base_target = owned_targets[len(staged_pngs)]
        metadata = [staged / name for name in ("manifest.json", "scene-manifest.json", "provenance.json")]
        metadata_targets = owned_targets[len(staged_pngs) + 1:]
        # Move old producer-owned entries aside on the same filesystem. This
        # preserves regular files, directories, and symlinks without copying.
        backups: list[tuple[Path, Path]] = []
        published: list[Path] = []
        preserve_recovery = False
        try:
            for index, target in enumerate([base_target, *metadata_targets]):
                if target.exists() or target.is_symlink():
                    backup = staged / f"publication-backup-{index}"
                    os.replace(target, backup)
                    backups.append((backup, target))
            for source, target in targets:
                target.parent.mkdir(parents=True, exist_ok=True)
                os.replace(source, target)
                published.append(target)
            base_target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staged_base, base_target)
            published.append(base_target)
            for source, target in zip(metadata, metadata_targets):
                os.replace(source, target)
                published.append(target)
            missing = [item for item in paths if not (output / item).is_file()]
            if missing:
                raise AssetError(f"published scene manifest has unresolved image paths: {missing[0]}")
        except BaseException as original_error:
            recovery_errors: list[str] = []
            for path in reversed(published):
                try:
                    if path.is_symlink() or path.is_file():
                        path.unlink(missing_ok=True)
                    elif path.is_dir():
                        shutil.rmtree(path)
                except OSError as recovery_error:
                    recovery_errors.append(f"remove {path}: {recovery_error}")
            for backup, target in reversed(backups):
                try:
                    if target.exists() or target.is_symlink():
                        if target.is_dir() and not target.is_symlink():
                            shutil.rmtree(target)
                        else:
                            target.unlink()
                    os.replace(backup, target)
                except OSError as recovery_error:
                    recovery_errors.append(f"restore {target} from {backup}: {recovery_error}")
            if recovery_errors:
                original_error.add_note(
                    "rollback incomplete; recovery material retained at "
                    f"{staged}; " + "; ".join(recovery_errors)
                )
                preserve_recovery = True
            raise
        return manifest
    finally:
        if not locals().get("preserve_recovery", False):
            shutil.rmtree(staged, ignore_errors=True)


def _write_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _merge_image_links(source: Path, target: Path, skip: frozenset[str] = frozenset()) -> None:
    """Compose two private image roots with symlinks, without copying data."""

    target.mkdir(parents=True, exist_ok=True)
    for child in source.iterdir():
        if child.name in skip:
            continue
        destination = target / child.name
        if destination.is_symlink():
            if child.is_dir() and destination.resolve() != child.resolve():
                old_source = destination.resolve()
                destination.unlink()
                destination.mkdir()
                _merge_image_links(old_source, destination)
                _merge_image_links(child, destination)
            elif destination.resolve() != child.resolve():
                raise AssetError(f"base image link collision: {destination}")
            continue
        if destination.exists():
            if not child.is_dir() or not destination.is_dir():
                raise AssetError(f"base image path collision: {destination}")
            _merge_image_links(child, destination)
            continue
        destination.symlink_to(child, target_is_directory=child.is_dir())


def _ensure_base_link(output: Path, base_manifest: Path) -> None:
    """Expose base-manifest images below output/images/base using links."""

    source_images = base_manifest.parent / "images"
    if not source_images.is_dir():
        raise AssetError(f"existing scene image directory is unavailable: {source_images}")
    base_link = output / "images" / "base"
    nested_base = source_images / "base"
    roots = [nested_base, source_images] if nested_base.is_dir() else [source_images]
    if base_link.is_symlink():
        base_link.unlink()
    elif base_link.exists():
        if not base_link.is_dir():
            raise AssetError(f"existing base image link collision: {base_link}")
    else:
        base_link.mkdir(parents=True, exist_ok=True)
    for root in roots:
        _merge_image_links(root, base_link, frozenset({"base"}) if root == source_images else frozenset())


def patch_existing(
    zip_path: Path,
    output: Path,
    identity_path: Path,
    base_manifest: Path,
) -> dict:
    """Patch only the four vehicle PNGs and repoint existing base paths."""

    zip_path = zip_path.expanduser().resolve()
    output = output.expanduser().resolve()
    identity_path = identity_path.expanduser().resolve()
    base_manifest = base_manifest.expanduser().resolve()
    if not zip_path.is_file() or not identity_path.is_file() or not base_manifest.is_file():
        raise InputError("patch inputs are unavailable")
    manifest_path = output / "manifest.json"
    scene_path = output / "scene-manifest.json"
    provenance_path = output / "provenance.json"
    manifest = _load_json(manifest_path)
    scene_before = _load_json(scene_path)
    provenance = _load_json(provenance_path)
    if manifest.get("schema") != "richman4.inventory-assets/v1":
        raise AssetError("existing inventory manifest has an unsupported schema")
    base_data = _load_json(base_manifest)
    if base_data.get("schema") != "richman4.scene-images/v1":
        raise AssetError("base manifest has an unsupported schema")
    manifest["base_manifest"] = {"path": str(base_manifest), "sha256": _sha256(base_manifest), "schema": base_data["schema"]}
    identity = _load_identity(identity_path)
    previous_rewrite = provenance.get("metadata_rewrite", {})
    old_manifest_sha = previous_rewrite.get("manifest_sha256_before", _sha256(manifest_path))
    old_scene_sha = previous_rewrite.get("scene_manifest_sha256_before", _sha256(scene_path))
    panel_resources = {}
    for edition in EDITIONS:
        try:
            resource = manifest["resources"][edition]
            chunks = resource["chunks"]
            panel_resources[edition] = copy.deepcopy(scene_before["ui"][edition][ARCHIVE_KEY]["resources"][str(RESOURCE_INDEX)])
        except (KeyError, TypeError) as error:
            raise AssetError(f"existing manifest is missing Panel11 {edition}") from error
        if set(chunks) != {str(index) for index in range(CHUNK_COUNT)}:
            raise AssetError(f"existing manifest has an unexpected Panel11 {edition} chunk set")

    destinations: list[tuple[str | Path, bool]] = []
    for edition in EDITIONS:
        for index in (15, 16):
            canonical = f"images/{edition}/ui/{ARCHIVE_KEY}/{RESOURCE_INDEX}/{index}.png"
            inventory_path = manifest["resources"][edition]["chunks"][str(index)].get("path")
            scene_record_path = panel_resources[edition]["chunks"][str(index)].get("path")
            if inventory_path != canonical or scene_record_path != canonical:
                raise AssetError(f"Panel11 {edition} chunk {index} destination is not canonical")
            destinations.append((canonical, False))
    destinations.extend((("images/base", True), ("manifest.json", True), ("scene-manifest.json", True), ("provenance.json", True)))
    replacement_targets = _preflight_write_set(output, destinations)
    _preflight_replacement_inputs(
        [zip_path, identity_path, base_manifest, *_scene_image_inputs(base_data, base_manifest)],
        replacement_targets,
    )

    # Build all candidates and metadata before touching published files. The
    # only staged image data is the four small vehicle PNGs.
    staged_root = Path(tempfile.mkdtemp(prefix=".inventory-patch-", dir=output))
    staged_pngs: list[tuple[Path, Path]] = []
    try:
      with zipfile.ZipFile(zip_path) as archive:
        for edition in EDITIONS:
            member = ARCHIVE_MEMBER.format(edition=edition)
            panel_data = archive.read(member)
            expected = identity[(edition, RESOURCE_INDEX)]
            if hashlib.sha256(panel_data).hexdigest() != expected.get("archive_sha256"):
                raise AssetError(f"{member} archive hash differs from pinned identity")
            mkf = parse_mkf(Path(member), panel_data)
            payload = decode_entry(mkf, mkf.entries[RESOURCE_INDEX])
            if hashlib.sha256(payload).hexdigest() != expected.get("payload_sha256"):
                raise AssetError(f"{member} Panel11 payload hash differs from pinned identity")
            visual = parse_visual_resource(payload, mkf.entries[RESOURCE_INDEX])
            if visual is None or visual.signature != EXPECTED_SIGNATURE or visual.chunk_count != CHUNK_COUNT:
                raise AssetError(f"{member}: Panel11 visual resource is incompatible")
            pinned = {int(chunk["index"]): chunk for chunk in expected["chunks"]}
            for index in (15, 16):
                chunk = visual.chunks[index]
                expected_chunk = pinned[index]
                if (chunk.width, chunk.height, chunk.x, chunk.y) != tuple(int(expected_chunk[key]) for key in ("width", "height", "x", "y")):
                    raise AssetError(f"{member}: Panel11 chunk {index} geometry differs from pinned identity")
                if hashlib.sha256(chunk.pixels).hexdigest() != expected_chunk["pixel_data_sha256"]:
                    raise AssetError(f"{member}: Panel11 chunk {index} pixels differ from pinned identity")
                record = manifest["resources"][edition]["chunks"][str(index)]
                target = _preflight_destination(output, record["path"])
                if not target.is_file() or target.is_symlink():
                    raise AssetError(f"existing Panel11 output is unavailable: {record['path']}")
                staged = staged_root / f"{edition}-{index}.png"
                write_png(staged, chunk, visual, pixel_format=PIXEL_FORMAT, transparent_word_zero=False)
                record["sha256"] = _sha256(staged)
                record["transparent_word_zero"] = False
                panel_resources[edition]["chunks"][str(index)]["sha256"] = record["sha256"]
                panel_resources[edition]["chunks"][str(index)]["transparent_word_zero"] = False
                staged_pngs.append((staged, target))

      scene = _rewrite_base_paths(scene_before)
      for edition in EDITIONS:
          scene["ui"][edition][ARCHIVE_KEY]["resources"][str(RESOURCE_INDEX)] = panel_resources[edition]
      provenance["base_manifest"] = manifest["base_manifest"]
      for edition in EDITIONS:
          provenance.setdefault("resources", {}).setdefault(edition, {})["alpha_policy"] = {
              "chunks_0_1_15_16": "opaque source/caller draw",
              "chunks_2_14": "WORD 0 transparent per source icon caller",
          }
      image_paths: list[str] = []
      def collect_paths(value):
          if isinstance(value, dict):
              for item in value.values(): collect_paths(item)
          elif isinstance(value, list):
              for item in value: collect_paths(item)
          elif isinstance(value, str) and value.startswith("images/"):
              image_paths.append(value)
      collect_paths(scene)

      manifest_payload = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
      scene_payload = json.dumps(scene, ensure_ascii=False, indent=2) + "\n"
      manifest_sha = hashlib.sha256(manifest_payload.encode()).hexdigest()
      scene_sha = hashlib.sha256(scene_payload.encode()).hexdigest()
      provenance["manifest_sha256"] = manifest_sha
      provenance["scene_manifest_sha256"] = scene_sha
      provenance["metadata_rewrite"] = {
          "manifest_sha256_before": old_manifest_sha,
          "manifest_sha256_after": manifest_sha,
          "scene_manifest_sha256_before": old_scene_sha,
          "scene_manifest_sha256_after": scene_sha,
          "rewritten_base_paths": True,
          "rewritten_chunks": [f"{edition}:{index}" for edition in EDITIONS for index in (15, 16)],
      }
      metadata = [(manifest_path, manifest_payload), (scene_path, scene_payload),
                  (provenance_path, json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")]
      staged_metadata: list[tuple[Path, Path]] = []
      for index, (target, payload) in enumerate(metadata):
          staged = staged_root / f"metadata-{index}.json"
          staged.write_text(payload, encoding="utf-8")
          staged_metadata.append((staged, target))
      base_link = output / "images" / "base"
      backup_link = staged_root / "base-link-backup"
      had_base_link = base_link.exists() or base_link.is_symlink()
      backups: list[tuple[Path, Path]] = []
      published: list[Path] = []
      try:
          if had_base_link:
              os.replace(base_link, backup_link)
              backups.append((backup_link, base_link))
          published.append(base_link)  # _ensure_base_link may fail partway through.
          _ensure_base_link(output, base_manifest)
          # Validate against the final composed links. A stale prior link (or
          # a dangling symlink) must not make a missing authoritative path
          # appear publishable.
          missing = [item for item in image_paths if not (output / item).is_file()]
          if missing:
              raise AssetError(f"scene manifest has unresolved image paths: {missing[0]}")
          for index, (staged, target) in enumerate([*staged_pngs, *staged_metadata]):
              if target.exists() or target.is_symlink():
                  backup = staged_root / f"entry-backup-{index}"
                  os.replace(target, backup)
                  backups.append((backup, target))
              os.replace(staged, target)
              published.append(target)
      except BaseException as original_error:
          recovery_errors: list[str] = []

          def remove_entry(path: Path) -> None:
              if path.is_symlink() or path.is_file():
                  path.unlink(missing_ok=True)
              elif path.is_dir():
                  shutil.rmtree(path)

          for path in reversed(published):
              try:
                  remove_entry(path)
              except OSError as recovery_error:
                  recovery_errors.append(f"remove {path}: {recovery_error}")
          for backup, target in reversed(backups):
              try:
                  if target.exists() or target.is_symlink():
                      remove_entry(target)
                  os.replace(backup, target)
              except OSError as recovery_error:
                  recovery_errors.append(f"restore {target} from {backup}: {recovery_error}")
          if recovery_errors:
              original_error.add_note(
                  "rollback incomplete; recovery material retained at "
                  f"{staged_root}; " + "; ".join(recovery_errors)
              )
              preserve_recovery = True
          raise
      return manifest
    finally:
      if not locals().get("preserve_recovery", False):
          shutil.rmtree(staged_root, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", dest="zip_path", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--identity", type=Path, required=True)
    parser.add_argument("--base-manifest", type=Path, required=True)
    parser.add_argument("--patch-existing", action="store_true", help="rewrite only corrected opaque chunks 15/16")
    args = parser.parse_args()
    try:
        action = patch_existing if args.patch_existing else prepare
        result = action(args.zip_path, args.output, args.identity, args.base_manifest)
    except (AssetError, InputError, FormatError, OSError, KeyError, IndexError, zipfile.BadZipFile) as error:
        notes = getattr(error, "__notes__", ())
        details = "".join(f"\n{note}" for note in notes)
        parser.exit(1, f"inventory asset preparation failed: {error}{details}\n")
    print(f"Prepared bounded Panel11 inventory assets: {sum(len(value['chunks']) for value in result['resources'].values())} chunks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
