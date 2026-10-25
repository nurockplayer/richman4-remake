"""Export bounded, source-mapped UI resources into a private scene bundle.

The normal ground decoder calls :func:`export_ui_resources` while producing a
full scene manifest.  The ``--manifest`` entry point below is intentionally
separate: it stages only these UI resources and merges them into an existing
scene manifest, so a UI asset refresh does not decode the map or character
corpus again.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from decode_original_images import (
    FormatError,
    InputError,
    VisualChunk,
    VisualResource,
    _find_casefolded,
    assert_disjoint_paths,
    assert_private_output,
    decode_entry,
    discover_editions,
    parse_mkf,
    parse_visual_resource,
    write_png,
)

# Source identity is kept separate from presentation coordinates.  These are
# archive indices, not screen positions; see docs/original-ui-assets.md.
UI_RESOURCES = {"Data": (1, 2, 3), "Panel": (0, 1, 2, 75)}

# The two editions do not use the same jump resource numbers.  The first four
# Game jump resources (and first eight MJ resources) are 640x480 map images;
# the setup atlas follows them, then 36 SPR resources form twelve groups of
# walking/motorcycle/car previews.  Keep these ranges explicit because the
# source setup code indexes the edition's jump archive directly.  ``None``
# means all chunks in the one explicitly selected resource, including the
# save/load map thumbnails and slot background.
JUMP_RESOURCE_RANGES = {
    "Game": {
        "map_backgrounds": tuple(range(0, 4)),
        "setup": (4,),
        "character_previews": tuple(range(5, 41)),
    },
    "MultiverseJourney": {
        "map_backgrounds": tuple(range(0, 8)),
        "setup": (8,),
        "character_previews": tuple(range(9, 45)),
    },
}


def _jump_resource_indices(edition: str) -> tuple[int, ...]:
    ranges = JUMP_RESOURCE_RANGES[edition]
    return (
        *ranges["map_backgrounds"],
        *ranges["setup"],
        *ranges["character_previews"],
    )


EDITION_UI_RESOURCES = {
    "Game": {
        "jump": {index: None for index in _jump_resource_indices("Game")},
        "Data": {479: None, 560: (0,)},
        "help": {0: None},
    },
    "MultiverseJourney": {
        "jump": {
            index: None for index in _jump_resource_indices("MultiverseJourney")
        },
        "Data": {520: None, 601: (0,)},
        "help": {0: None},
    },
}

# These resources are not SPR/SMP records.  The original loading scene reads
# the entire stored entry as a headerless 640x480 RGB555 surface.  Keep the
# binding explicit instead of letting a visually similar resource at another
# edition/index be adopted accidentally.
RAW_RGB555_RESOURCES = {
    (edition, "jump", index)
    for edition, ranges in JUMP_RESOURCE_RANGES.items()
    for index in ranges["map_backgrounds"]
}
RAW_RGB555_RESOURCES.update(
    {
        ("Game", "Data", 560),
        ("MultiverseJourney", "Data", 601),
    }
)
RAW_RGB555_WIDTH = 640
RAW_RGB555_HEIGHT = 480
RAW_RGB555_BYTES = RAW_RGB555_WIDTH * RAW_RGB555_HEIGHT * 2
RAW_RGB555_SIGNATURE = "RAW-RGB555"
REQUIRED_UI_CHUNKS = {
    ("Game", "Data", 479): tuple(range(7)),
    ("MultiverseJourney", "Data", 520): tuple(range(11)),
}


def _canonical_edition(edition: str) -> str:
    """Return the supported edition spelling or fail closed."""

    for supported in EDITION_UI_RESOURCES:
        if str(edition).casefold() == supported.casefold():
            return supported
    raise InputError(f"unsupported UI edition: {edition}")


def _resource_specs(edition: str) -> dict[str, dict[int, tuple[int, ...] | None]]:
    """Combine old common resources with the edition-bound UI slice."""

    canonical = _canonical_edition(edition)
    specs: dict[str, dict[int, tuple[int, ...] | None]] = {
        name: {index: None for index in indices}
        for name, indices in UI_RESOURCES.items()
    }
    for name, resources in EDITION_UI_RESOURCES[canonical].items():
        specs.setdefault(name, {}).update(resources)
    return specs


def _frame_record(relative: Path, target: Path, chunk: VisualChunk) -> dict:
    """Return the stable output record consumed by OriginalVisuals.ui."""

    return {
        "path": relative.as_posix(),
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "width": chunk.width,
        "height": chunk.height,
        "logical": {
            "width": chunk.width,
            "height": chunk.height,
            "anchor_x": chunk.x,
            "anchor_y": chunk.y,
        },
    }


def _source_record(
    edition: str,
    archive_name: str,
    index: int,
    archive,
    entry,
    payload: bytes,
) -> dict:
    """Keep source identity separate from the derived PNG output path."""

    return {
        "edition": edition,
        "archive": f"{archive_name}.mkf",
        "resource_index": index,
        "entry": entry.as_dict(),
        "payload_sha256": hashlib.sha256(payload).hexdigest(),
        "archive_sha256": hashlib.sha256(archive.data).hexdigest(),
    }


def _raw_rgb555_visual(path: Path, index: int, payload: bytes) -> VisualResource:
    """Bind a loading entry to the observed headerless RGB555 dimensions."""

    if len(payload) != RAW_RGB555_BYTES:
        raise FormatError(
            f"raw RGB555 UI resource at {path}:{index} has {len(payload)} bytes; "
            f"expected {RAW_RGB555_BYTES} for {RAW_RGB555_WIDTH}x{RAW_RGB555_HEIGHT}"
        )
    chunk = VisualChunk(
        0,
        RAW_RGB555_WIDTH,
        RAW_RGB555_HEIGHT,
        0,
        0,
        payload,
    )
    return VisualResource(
        RAW_RGB555_SIGNATURE,
        1,
        0,
        None,
        (chunk,),
    )


def _export_resource(
    edition: str,
    archive_name: str,
    index: int,
    chunks: tuple[int, ...] | None,
    archive,
    stage: Path,
) -> dict:
    """Decode only one configured entry and write its selected chunks."""

    entry = archive.entries[index]
    payload = decode_entry(archive, entry)
    binding = (edition, archive_name, index)
    if binding in RAW_RGB555_RESOURCES:
        visual = _raw_rgb555_visual(archive.path, index, payload)
        transparent_word_zero = False
        output_format = "raw-rgb555"
    else:
        visual = parse_visual_resource(payload, entry)
        if visual is None or visual.signature not in ("SMP", "SPR"):
            raise FormatError(f"unsupported UI image at {archive.path}:{index}")
        transparent_word_zero = True
        output_format = visual.signature

    available = {chunk.index: chunk for chunk in visual.chunks}
    selected = tuple(visual.chunks) if chunks is None else tuple(
        available[chunk_index]
        for chunk_index in chunks
        if chunk_index in available
    )
    required = REQUIRED_UI_CHUNKS.get(binding, ()) if chunks is None else chunks
    missing = tuple(
        chunk_index for chunk_index in required if chunk_index not in available
    )
    if missing:
        raise FormatError(
            f"UI resource at {archive.path}:{index} is missing chunk(s): "
            + ", ".join(str(chunk) for chunk in missing)
        )
    if not selected:
        raise FormatError(f"UI resource at {archive.path}:{index} has no selected chunks")

    output_chunks = {}
    for chunk in selected:
        relative = (
            Path("images")
            / edition
            / "ui"
            / archive_name
            / str(index)
            / f"{chunk.index}.png"
        )
        target = stage / relative
        # UI sprites and atlas fragments use a zero background around their
        # irregular edges.  Headerless map/loading pixels are opaque,
        # including their real black background, so the raw binding opts out
        # below.
        write_png(
            target,
            chunk,
            visual,
            pixel_format="rgb555",
            transparent_word_zero=transparent_word_zero,
        )
        output_chunks[str(chunk.index)] = _frame_record(relative, target, chunk)

    payload_sha256 = hashlib.sha256(payload).hexdigest()
    return {
        "resource_index": index,
        "payload_sha256": payload_sha256,
        "signature": visual.signature,
        "format": output_format,
        "pixel_format": "rgb555",
        "transparent_word_zero": transparent_word_zero,
        "source": _source_record(
            edition, archive_name, index, archive, entry, payload
        ),
        "output": {
            "format": "png",
            "pixel_format": "rgb555",
            "transparent_word_zero": transparent_word_zero,
        },
        "chunks": output_chunks,
    }


def export_ui_resources(edition: str, directory: Path, stage: Path) -> dict:
    """Export the bounded UI resource set for one known edition.

    Missing optional archives or entries remain absent.  Once an explicitly
    bound entry exists, malformed data and missing configured chunks are hard
    errors; this keeps a wrong edition/index from silently looking valid.
    """

    canonical = _canonical_edition(edition)
    result = {}
    for name, index_specs in _resource_specs(canonical).items():
        path = _find_casefolded(directory, name + ".mkf")
        if path is None:
            continue
        archive = parse_mkf(path)
        resources = {}
        for index, chunks in index_specs.items():
            if index >= len(archive.entries):
                continue
            resources[str(index)] = _export_resource(
                canonical, name, index, chunks, archive, stage
            )
        result[name] = {
            "archive": f"{name}.mkf",
            "archive_sha256": hashlib.sha256(archive.data).hexdigest(),
            "resources": resources,
        }
    return result


def _canonical_discovered_editions(
    source: Path, editions: set[str] | None
) -> list[tuple[str, Path]]:
    """Discover source folders while preserving the edition binding table."""

    discovered = discover_editions(source)
    wanted: set[str] | None = None
    if editions:
        wanted = {_canonical_edition(value) for value in editions}
    result = []
    seen: set[str] = set()
    for name, directory in discovered:
        canonical = _canonical_edition(name)
        folded = canonical.casefold()
        if folded in seen:
            raise InputError(f"duplicate UI edition: {canonical}")
        seen.add(folded)
        if wanted is None or canonical in wanted:
            result.append((canonical, directory))
    if wanted:
        found = {name for name, _ in result}
        missing = wanted - found
        if missing:
            raise InputError(
                "requested UI editions were not found: "
                + ", ".join(sorted(missing))
            )
    if not result:
        if wanted:
            raise InputError(
                "requested UI editions were not found: "
                + ", ".join(sorted(wanted))
            )
        raise InputError("no supported UI editions found")
    return result


def _validate_existing_scene_manifest(path: Path) -> None:
    """Use the package validator before touching an incremental output."""

    from package_scene_images import validate

    validate(path)


def _merge_ui_archive_group(
    edition: str,
    archive_name: str,
    existing: object,
    incoming: dict,
) -> dict:
    """Merge resource references without mixing archive identities."""

    if not isinstance(existing, dict):
        raise FormatError(f"invalid scene UI archive: {edition}/{archive_name}")
    existing_hash = existing.get("archive_sha256")
    incoming_hash = incoming.get("archive_sha256")
    if existing_hash != incoming_hash:
        raise InputError(
            f"UI archive SHA mismatch for {edition}/{archive_name}: "
            f"existing {existing_hash!r}, source {incoming_hash!r}"
        )

    existing_resources = existing.get("resources", {})
    incoming_resources = incoming.get("resources", {})
    if not isinstance(existing_resources, dict):
        raise FormatError(
            f"invalid scene UI resources: {edition}/{archive_name}"
        )
    if not isinstance(incoming_resources, dict):
        raise FormatError(
            f"invalid staged UI resources: {edition}/{archive_name}"
        )

    # A valid archive group is the primary provenance boundary.  If a
    # preserved resource also carries source metadata, reject a contradictory
    # per-resource identity instead of carrying mixed source hashes forward.
    for resource in existing_resources.values():
        if not isinstance(resource, dict):
            raise FormatError(
                f"invalid scene UI resource: {edition}/{archive_name}"
            )
        source = resource.get("source")
        if isinstance(source, dict) and source.get("archive_sha256") not in (
            None,
            incoming_hash,
        ):
            raise InputError(
                f"UI resource archive SHA mismatch for {edition}/{archive_name}"
            )

    merged = dict(existing)
    merged.update(incoming)
    merged["resources"] = {**existing_resources, **incoming_resources}
    return merged


def update_ui_manifest(
    source: Path,
    manifest_path: Path,
    *,
    editions: set[str] | None = None,
) -> dict:
    """Append bounded UI assets to an existing scene manifest.

    Only the configured archives/entries are decoded.  Existing files are
    preserved byte-for-byte and existing resources in a touched archive are
    retained when its archive SHA matches.  A source/archive identity mismatch
    or a path collision with different bytes is rejected before the manifest
    is replaced.  The manifest replacement is atomic and all newly copied
    files are removed if validation fails.
    """

    source = source.expanduser().resolve()
    manifest_path = manifest_path.expanduser().resolve()
    output = manifest_path.parent
    if not manifest_path.is_file():
        raise InputError(f"scene manifest does not exist: {manifest_path}")
    assert_disjoint_paths(source, output)
    assert_private_output(output)
    _validate_existing_scene_manifest(manifest_path)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise InputError(f"cannot read scene manifest {manifest_path}: {exc}") from exc
    if not isinstance(manifest, dict) or manifest.get("schema") != "richman4.scene-images/v1":
        raise FormatError("unsupported scene manifest")
    if not isinstance(manifest.get("ui", {}), dict):
        raise FormatError("invalid scene UI manifest")

    discovered = _canonical_discovered_editions(source, editions)
    created: list[Path] = []
    temporary_manifest: Path | None = None
    committed = False
    try:
        with tempfile.TemporaryDirectory(prefix=".ui-stage-", dir=output) as temporary:
            stage = Path(temporary)
            staged_ui = {
                edition: export_ui_resources(edition, directory, stage)
                for edition, directory in discovered
            }
            merged = json.loads(json.dumps(manifest))
            merged_ui = merged.setdefault("ui", {})
            for edition, group in staged_ui.items():
                edition_ui = merged_ui.setdefault(edition, {})
                if not isinstance(edition_ui, dict):
                    raise FormatError(f"invalid scene UI edition: {edition}")
                for archive_name, archive_group in group.items():
                    if archive_name not in edition_ui:
                        edition_ui[archive_name] = archive_group
                    else:
                        edition_ui[archive_name] = _merge_ui_archive_group(
                            edition,
                            archive_name,
                            edition_ui[archive_name],
                            archive_group,
                        )

            for staged in sorted((stage / "images").rglob("*.png")):
                relative = staged.relative_to(stage)
                target = output / relative
                if target.is_symlink() or target.resolve() != target:
                    raise InputError(f"unsafe UI output path: {relative.as_posix()}")
                if target.exists():
                    if target.read_bytes() != staged.read_bytes():
                        raise InputError(
                            f"UI output collision has different bytes: {relative.as_posix()}"
                        )
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                created.append(target)
                shutil.copyfile(staged, target)

            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                newline="\n",
                prefix=f".{manifest_path.name}.ui-",
                suffix=".tmp",
                dir=output,
                delete=False,
            ) as temporary:
                temporary_manifest = Path(temporary.name)
                temporary.write(json.dumps(merged, ensure_ascii=False, indent=2))
                temporary.write("\n")
            _validate_existing_scene_manifest(temporary_manifest)
            os.replace(temporary_manifest, manifest_path)
            committed = True
            return merged
    finally:
        if temporary_manifest is not None and temporary_manifest.exists():
            temporary_manifest.unlink()
        if not committed:
            for path in reversed(created):
                try:
                    path.unlink()
                except OSError:
                    pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="existing richman4.scene-images/v1 manifest to update",
    )
    parser.add_argument(
        "--edition",
        dest="editions",
        action="append",
        help="limit the update; repeat for Game and/or MultiverseJourney",
    )
    args = parser.parse_args()
    try:
        manifest = update_ui_manifest(
            args.source,
            args.manifest,
            editions=set(args.editions) if args.editions else None,
        )
    except (FormatError, InputError, OSError, ValueError) as error:
        parser.exit(1, f"UI export failed: {error}\n")
    print(
        "Updated bounded UI assets for "
        + ", ".join(sorted(manifest.get("ui", {})))
        + f" in {args.manifest}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
