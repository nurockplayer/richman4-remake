#!/usr/bin/env python3
"""Decode local backgrounds and verified static sprites; never upload assets."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import tempfile

from decode_original_images import (
    FormatError,
    InputError,
    VisualChunk,
    VisualResource,
    _find_casefolded,
    _publish_staged_images,
    assert_disjoint_paths,
    assert_private_output,
    decode_entry,
    discover_editions,
    parse_mkf,
    parse_visual_resource,
    write_png,
)
from import_original import ImportErrorBase, parse_map_payload

SCHEMA = "richman4.scene-images/v1"
SIDE = 72
TILE_SIZE = 32
TILE_COUNT = SIDE * SIDE
PLACEMENT_OFFSET = 0x210
PIXEL_OFFSET = 0x2A90
PAYLOAD_SIZE = 0x512A90
ROAD_RESOURCE_INDEX = {"Game": 12, "MultiverseJourney": 24}
ROAD_CHUNK_COUNT = {"Game": 17, "MultiverseJourney": 58}


def decode_ground(payload: bytes) -> VisualResource:
    """Decode the verified 72x72 format, rejecting unsupported variants."""
    if len(payload) != PAYLOAD_SIZE or payload[:4] != b"GND\0":
        raise FormatError("unsupported GND signature or payload size")
    width, height, count, reserved = struct.unpack_from("<HHII", payload, 4)
    if (width, height, count, reserved) != (SIDE, SIDE, TILE_COUNT, 0):
        raise FormatError("unsupported GND dimensions or tile count")
    placements = struct.unpack_from(f"<{TILE_COUNT}H", payload, PLACEMENT_OFFSET)
    if any(tile >= TILE_COUNT for tile in placements):
        raise FormatError("GND placement points outside tile bank")
    # GND contains opaque palette indices; index zero is a real ground color.
    image_side = SIDE * TILE_SIZE
    pixels = bytearray(image_side * image_side)
    for position, tile in enumerate(placements):
        tile_x, tile_y = position % SIDE, position // SIDE
        source = PIXEL_OFFSET + tile * TILE_SIZE * TILE_SIZE
        for row in range(TILE_SIZE):
            target = (tile_y * TILE_SIZE + row) * image_side + tile_x * TILE_SIZE
            pixels[target : target + TILE_SIZE] = payload[
                source + row * TILE_SIZE : source + (row + 1) * TILE_SIZE
            ]
    chunk = VisualChunk(0, image_side, image_side, 0, 0, bytes(pixels))
    return VisualResource("SPR", 1, PIXEL_OFFSET, payload[0x10:0x210], (chunk,))


def export_sprite(archive, index: int, stage: Path, relative: Path) -> dict | None:
    if index >= len(archive.entries):
        return None
    entry = archive.entries[index]
    payload = decode_entry(archive, entry)
    visual = parse_visual_resource(payload, entry)
    if visual is None or visual.signature != "SPR" or visual.chunk_count != 8:
        raise FormatError(f"expected eight-direction SPR at {archive.path}:{index}")
    frames = []
    for chunk in visual.chunks:
        image_path = relative / f"direction-{chunk.index}.png"
        path = stage / image_path
        write_png(path, chunk, visual, pixel_format="rgb555")
        frames.append({"path": image_path.as_posix(),
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                       "width": chunk.width, "height": chunk.height,
                       "logical": {"width": chunk.width, "height": chunk.height,
                                   "anchor_x": chunk.x, "anchor_y": chunk.y}})
    return {"resource_index": index, "payload_sha256": hashlib.sha256(payload).hexdigest(),
            "frames": frames}


def export_road_sprites(archive, edition: str, stage: Path, relative: Path) -> dict | None:
    """Export the edition's verified node-icon SMP, preserving 1-based IDs."""
    index = ROAD_RESOURCE_INDEX[edition]
    if index >= len(archive.entries):
        return None
    entry = archive.entries[index]
    payload = decode_entry(archive, entry)
    visual = parse_visual_resource(payload, entry)
    expected_chunks = ROAD_CHUNK_COUNT[edition]
    if visual is None or visual.signature != "SMP" or visual.chunk_count != expected_chunks:
        raise FormatError(
            f"expected {expected_chunks}-chunk SMP road icon resource at {archive.path}:{index}"
        )
    sprites = []
    for chunk in visual.chunks:
        image_path = relative / f"chunk-{chunk.index:04d}.png"
        path = stage / image_path
        write_png(path, chunk, visual, pixel_format="rgb555", transparent_word_zero=True)
        frame = {
            "path": image_path.as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "width": chunk.width,
            "height": chunk.height,
            "logical": {
                "width": chunk.width,
                "height": chunk.height,
                "anchor_x": chunk.x,
                "anchor_y": chunk.y,
            },
        }
        # Map graph field_0x22 is a 1-based resource chunk number.  Keep the
        # explicit value beside a one-frame direction list so the scene
        # manifest uses the same logical/anchor contract as SPR sprites.
        sprites.append({"visual_index": chunk.index + 1, "frames": [frame]})
    return {
        "resource_index": index,
        "payload_sha256": hashlib.sha256(payload).hexdigest(),
        "signature": visual.signature,
        "chunk_count": visual.chunk_count,
        "transparent_word_zero": True,
        "sprites": sprites,
    }


def scene_objects(graph: bytes, parsed: dict) -> list[dict]:
    objects = []
    for category, sprite_offset, direction_offset in [
        ("landscapes", 26, 24), ("companies", 32, 27)
    ]:
        section = parsed["sections"][category]
        for record in parsed[category]:
            start = section["offset"] + record["id"] * section["record_size"]
            sprite_id = struct.unpack_from("<H", graph, start + sprite_offset)[0]
            if sprite_id:
                objects.append({"category": category, "id": record["id"],
                                "x": record["x"], "y": record["y"],
                                "sprite_id": sprite_id,
                                "direction": (8 - graph[start + direction_offset]) & 7})
    return objects


def decode_source(source: Path, output: Path) -> dict:
    source, output = source.resolve(), output.resolve()
    assert_disjoint_paths(source, output)
    assert_private_output(output)
    editions = []
    names = {"game": "Game", "multiversejourney": "MultiverseJourney"}
    for edition, directory in discover_editions(source):
        if edition.casefold() not in names:
            raise InputError(f"unknown ground edition: {edition}")
        canonical = names[edition.casefold()]
        if any(name == canonical for name, _ in editions):
            raise InputError(f"duplicate ground edition: {canonical}")
        editions.append((canonical, directory))
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": SCHEMA, "version": 1, "pixel_format": "rgb555", "maps": [], "characters": {}}
    with tempfile.TemporaryDirectory(prefix=".ground-stage-", dir=output) as temporary:
        stage = Path(temporary)
        (stage / "images").mkdir()
        for edition, directory in editions:
            data_path = _find_casefolded(directory, "Data.mkf")
            if data_path is not None:
                data_archive = parse_mkf(data_path)
                characters = []
                for character_id in range(12):
                    # Verified in both owner executables: ((id*4+id)*4+id)+base.
                    index = (87 if edition == "Game" else 128) + character_id * 21
                    sprite = export_sprite(data_archive, index, stage,
                                           Path("images") / edition / "characters" / str(character_id))
                    if sprite is not None:
                        sprite["character_id"] = character_id
                        characters.append(sprite)
                manifest["characters"][edition] = {
                    "archive_sha256": hashlib.sha256(data_archive.data).hexdigest(),
                    "sprites": characters,
                }
            archive_path = _find_casefolded(directory, "map.mkf")
            if archive_path is None:
                continue
            archive = parse_mkf(archive_path)
            archive_hash = hashlib.sha256(archive.data).hexdigest()
            road_sprites = export_road_sprites(
                archive,
                edition,
                stage,
                Path("images") / edition / "road-icons",
            )
            for entry in archive.entries:
                # Known map resources alternate GND and graph, before sprites.
                if entry.index % 2 or archive.payload(entry)[:4] != b"GND\0":
                    continue
                payload = decode_entry(archive, entry)
                ground = decode_ground(payload)
                if entry.index + 1 >= len(archive.entries):
                    raise FormatError("GND is missing its following map graph")
                graph = decode_entry(archive, archive.entries[entry.index + 1])
                graph_data = parse_map_payload(graph)
                map_number = entry.index // 2 + 1
                relative = Path("images") / edition / f"map-{map_number:02d}.png"
                path = stage / relative
                write_png(path, ground.chunks[0], ground, pixel_format="rgb555",
                          transparent_index_zero=False)
                house_sprites = []
                for level in range(1, 6):
                    index = (27 if edition == "Game" else 39) + (map_number - 1) * 5 + level - 1
                    sprite = export_sprite(archive, index, stage,
                                           Path("images") / edition / "houses" / f"{map_number}-{level}")
                    if sprite is not None:
                        sprite["level"] = level
                        house_sprites.append(sprite)
                objects = scene_objects(graph, graph_data)
                scenery_sprites = []
                for sprite_id in sorted({item["sprite_id"] for item in objects}):
                    index = sprite_id + (26 if edition == "Game" else 38)
                    sprite = export_sprite(archive, index, stage,
                                           Path("images") / edition / "scenery" / str(index))
                    if sprite is not None:
                        sprite["sprite_id"] = sprite_id
                        scenery_sprites.append(sprite)
                road_source = {}
                road_frames = []
                if road_sprites is not None:
                    road_source = {
                        "archive_sha256": archive_hash,
                        "resource_index": road_sprites["resource_index"],
                        "payload_sha256": road_sprites["payload_sha256"],
                        "signature": road_sprites["signature"],
                        "chunk_count": road_sprites["chunk_count"],
                        "transparent_word_zero": road_sprites["transparent_word_zero"],
                    }
                    road_frames = road_sprites["sprites"]
                manifest["maps"].append({
                    "id": f"{edition}:{map_number}",
                    "archive": f"{edition}/map.mkf",
                    "source_file_sha256": archive_hash,
                    "graph_payload_sha256": hashlib.sha256(graph).hexdigest(),
                    "ground_payload_sha256": hashlib.sha256(payload).hexdigest(),
                    "entry_index": entry.index,
                    "world_rect": {"x": 0, "y": 0, "width": SIDE * TILE_SIZE,
                                   "height": SIDE * TILE_SIZE},
                    "lands": [{"id": land["id"], "x": land["x"], "y": land["y"],
                               "direction": (8 - land["field_0x1b"]) & 7}
                              for land in graph_data["lands"]],
                    "house_sprites": house_sprites,
                    "scenery": objects, "scenery_sprites": scenery_sprites,
                    "road_source": road_source, "road_sprites": road_frames,
                    "image": {"path": relative.as_posix(),
                              "width": SIDE * TILE_SIZE, "height": SIDE * TILE_SIZE,
                              "sha256": hashlib.sha256(path.read_bytes()).hexdigest()},
                })
        if not manifest["maps"]:
            raise InputError("no supported GND backgrounds found")
        staged_manifest = stage / "manifest.json"
        staged_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        _publish_staged_images(stage / "images", staged_manifest, output)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(".local/original-scenes"))
    args = parser.parse_args()
    try:
        manifest = decode_source(args.source, args.output)
    except (InputError, FormatError, ImportErrorBase, OSError) as error:
        parser.exit(1, f"Ground import failed: {error}\n")
    print(f"Decoded {len(manifest['maps'])} original backgrounds into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
