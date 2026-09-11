#!/usr/bin/env python3
"""Prepare the bounded private FLIC slice used by the lottery presenter.

The owner ZIP is read in place and only Panel entries 12, 13, 14, 15, 16 and
17 are inspected.  The resulting PNGs and manifests are private preparation
output; existing scene PNGs are referenced by symlink; bounded SMP overlays are
re-emitted from source words to preserve the caller transparency policy.
"""
from __future__ import annotations

import argparse
import binascii
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from decode_original_images import decode_entry, parse_mkf, parse_visual_resource, write_png as write_smp_png

MAX_OUTPUT_FRAMES = 64
RESOURCES = {
    14: {"x": 8, "y": 8, "delay_ms": 100, "loop": True, "transparent_index_zero": True},
    16: {"x": 183, "y": 75, "delay_ms": 50, "loop": False, "transparent_index_zero": False},
    17: {"x": 205, "y": 0, "delay_ms": 50, "loop": False, "transparent_index_zero": True},
}
EDITIONS = ("Game", "MultiverseJourney")
REUSED_RESOURCES = (12, 13, 15)


class AssetError(ValueError):
    pass


def _u8(data: bytes, offset: int) -> int:
    if offset >= len(data):
        raise AssetError("FLIC chunk is truncated")
    return data[offset]


def _u16(data: bytes, offset: int) -> int:
    if offset + 2 > len(data):
        raise AssetError("FLIC chunk is truncated")
    return struct.unpack_from("<H", data, offset)[0]


def _i8(data: bytes, offset: int) -> int:
    return struct.unpack_from("<b", data, offset)[0] if offset < len(data) else (_ for _ in ()).throw(AssetError("FLIC chunk is truncated"))


def _i16(data: bytes, offset: int) -> int:
    if offset + 2 > len(data):
        raise AssetError("FLIC chunk is truncated")
    return struct.unpack_from("<h", data, offset)[0]


def _decode_brun(payload: bytes, width: int, height: int) -> bytearray:
    pixels = bytearray(width * height)
    offset = 0
    for row in range(height):
        packets = _u8(payload, offset); offset += 1
        cursor = row * width
        for _ in range(packets):
            count = _i8(payload, offset); offset += 1
            if count >= 0:
                value = _u8(payload, offset); offset += 1
                if count > width - (cursor - row * width): raise AssetError("BRUN row overflow")
                pixels[cursor:cursor + count] = bytes([value]) * count; cursor += count
            else:
                count = -count
                if count > width - (cursor - row * width) or offset + count > len(payload): raise AssetError("BRUN literal overflow")
                pixels[cursor:cursor + count] = payload[offset:offset + count]; offset += count; cursor += count
        if cursor != (row + 1) * width: raise AssetError("BRUN row does not fill frame")
    return pixels


def _decode_ss2(payload: bytes, pixels: bytearray, width: int, height: int) -> None:
    compressed_lines = _u16(payload, 0); offset = 2; row = 0; controls = 0
    if compressed_lines > height: raise AssetError("SS2 line count exceeds frame")
    while compressed_lines > 0:
        controls += 1
        if controls > height * 2 + 1:
            raise AssetError("SS2 control count exceeds frame")
        raw_line_packets = _u16(payload, offset); offset += 2
        if raw_line_packets & 0xC000 == 0xC000:
            row += -_i16(struct.pack("<H", raw_line_packets), 0)
            if row > height: raise AssetError("SS2 skipped past frame")
            continue
        if row >= height: raise AssetError("SS2 row overflow")
        compressed_lines -= 1
        packets = raw_line_packets; cursor = 0
        if packets & 0x8000:
            pixels[row * width + width - 1] = packets & 0xFF
            packets = _u16(payload, offset); offset += 2
            if packets == 0:
                row += 1
                continue
        for _ in range(packets):
            skip = _u8(payload, offset); count = _i8(payload, offset + 1); offset += 2; cursor += skip
            if cursor > width: raise AssetError("SS2 x overflow")
            if count >= 0:
                size = count * 2
                if cursor + size > width or offset + size > len(payload): raise AssetError("SS2 literal overflow")
                pixels[row * width + cursor:row * width + cursor + size] = payload[offset:offset + size]
                offset += size; cursor += size
            else:
                count = -count
                size = count * 2
                if cursor + size > width or offset + 2 > len(payload): raise AssetError("SS2 repeat overflow")
                value = payload[offset:offset + 2]; offset += 2
                pixels[row * width + cursor:row * width + cursor + size] = value * count; cursor += size
        row += 1


def _apply_palette(
    payload: bytes, palette: list[tuple[int, int, int]], *, six_bit: bool = False
) -> None:
    count = _u16(payload, 0); offset = 2; index = 0
    for _ in range(count):
        index += _u8(payload, offset); count_value = _u8(payload, offset + 1); offset += 2
        count_value = count_value or 256
        if index + count_value > 256 or offset + count_value * 3 > len(payload): raise AssetError("palette chunk overflow")
        for item in range(count_value):
            red, green, blue = payload[offset + item * 3:offset + item * 3 + 3]
            if six_bit:
                red, green, blue = ((value << 2) | (value >> 4) for value in (red, green, blue))
            palette[index + item] = (red, green, blue)
        offset += count_value * 3; index += count_value


def decode_flic(data: bytes, *, max_frames: int = MAX_OUTPUT_FRAMES) -> tuple[int, int, list[tuple[bytearray, list[tuple[int, int, int]]]]]:
    if len(data) < 128: raise AssetError("FLIC header is truncated")
    size, magic, declared, width, height, depth = struct.unpack_from("<IHHHHH", data, 0)
    if magic not in (0xAF11, 0xAF12) or width <= 0 or height <= 0 or depth != 8: raise AssetError("unsupported FLIC header")
    if size != len(data): raise AssetError("FLIC size field does not match payload")
    if declared <= 0 or declared > max_frames: raise AssetError("FLIC frame count exceeds bound")
    palette = [(0, 0, 0)] * 256; pixels = bytearray(width * height); frames = []
    offset = 128; seen = 0
    while offset + 16 <= len(data) and seen < declared:
        frame_size, frame_magic, sub_count = struct.unpack_from("<IHH", data, offset)
        if frame_size < 16 or offset + frame_size > len(data): raise AssetError("FLIC frame is truncated")
        if frame_magic == 0xF100: offset += frame_size; continue
        if frame_magic != 0xF1FA: raise AssetError("unsupported FLIC frame marker")
        cursor = offset + 16
        for _ in range(sub_count):
            if cursor + 6 > offset + frame_size: raise AssetError("FLIC subchunk header is truncated")
            chunk_size, chunk_type = struct.unpack_from("<IH", data, cursor)
            if chunk_size < 6 or cursor + chunk_size > offset + frame_size: raise AssetError("FLIC subchunk is truncated")
            payload = data[cursor + 6:cursor + chunk_size]
            if chunk_type == 4: _apply_palette(payload, palette)
            elif chunk_type == 11: _apply_palette(payload, palette, six_bit=True)
            elif chunk_type == 15: pixels = _decode_brun(payload, width, height)
            elif chunk_type == 7: _decode_ss2(payload, pixels, width, height)
            elif chunk_type not in (18,): raise AssetError(f"unsupported FLIC subchunk {chunk_type}")
            cursor += chunk_size
        frames.append((bytearray(pixels), list(palette))); seen += 1; offset += frame_size
    if len(frames) != declared: raise AssetError(f"FLIC has {len(frames)} frames; expected {declared}")
    return width, height, frames


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)


def write_png(path: Path, pixels: bytearray, palette: list[tuple[int, int, int]], width: int, height: int, transparent: bool) -> None:
    rows = bytearray()
    for row in range(height):
        rows.append(0)
        for index in pixels[row * width:(row + 1) * width]:
            red, green, blue = palette[index]; rows.extend((red, green, blue, 0 if transparent and index == 0 else 255))
    payload = bytearray(b"\x89PNG\r\n\x1a\n")
    payload.extend(_png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
    payload.extend(_png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))); payload.extend(_png_chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(payload)


def _frame_record(relative: Path, path: Path, width: int, height: int, index: int, settings: dict) -> dict:
    return {"path": relative.as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "width": width, "height": height, "logical": {"width": width, "height": height, "anchor_x": 0, "anchor_y": 0}, "frame_index": index, "caller": dict(settings)}


def _rewrite_base_paths(value):
    """Repoint every base-manifest image record through the owned symlink."""

    if isinstance(value, dict):
        return {key: _rewrite_base_paths(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_rewrite_base_paths(item) for item in value]
    if isinstance(value, str) and value.startswith("images/"):
        return "images/base/" + value[len("images/"):]
    return value


def _load_existing_art(path: Path) -> dict[tuple[str, int], list[dict]]:
    try:
        parsed = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AssetError(f"existing-art metadata is unreadable: {path}: {error}") from error
    schema = parsed.get("schema")
    if schema not in ("richman4.source-lottery-existing-art/v1", "richman4.original-images/v1"):
        raise AssetError("existing-art metadata has an unsupported schema")
    if schema == "richman4.original-images/v1":
        source_root = path.parent
        verified = []
        for resource in parsed.get("visual_resources", []):
            archive = resource.get("archive", "") if isinstance(resource, dict) else ""
            edition = resource.get("edition") if isinstance(resource, dict) else None
            index = resource.get("resource_index") if isinstance(resource, dict) else None
            if edition not in EDITIONS or index not in REUSED_RESOURCES or archive != f"{edition}/Panel.mkf":
                continue
            for image in resource.get("images", []):
                if isinstance(image, dict):
                    verified.append({**image, "edition": edition, "resource_index": index, "path": str(source_root / image.get("path", ""))})
        parsed = {"verified_images": verified}
    selected: dict[tuple[str, int], list[dict]] = {}
    for item in parsed.get("verified_images", []):
        if not isinstance(item, dict):
            raise AssetError("existing-art metadata contains a non-object image")
        edition = item.get("edition")
        resource = item.get("resource_index")
        if edition not in EDITIONS or resource not in REUSED_RESOURCES:
            continue
        source = Path(str(item.get("path", ""))).expanduser()
        if not source.is_file():
            raise AssetError(f"verified existing image is unavailable: {source}")
        if hashlib.sha256(source.read_bytes()).hexdigest() != item.get("sha256"):
            raise AssetError(f"verified existing image hash mismatch: {source}")
        for key in ("chunk_index", "width", "height", "x", "y"):
            if not isinstance(item.get(key), int):
                raise AssetError(f"existing-art metadata has invalid {key}: {item}")
        selected.setdefault((edition, resource), []).append(item)
    for edition in EDITIONS:
        for resource in REUSED_RESOURCES:
            if not selected.get((edition, resource)):
                raise AssetError(f"existing-art metadata lacks {edition} Panel/{resource}")
    for items in selected.values():
        items.sort(key=lambda item: item["chunk_index"])
    return selected


def _static_transparent(resource: int, chunk: int) -> bool:
    # fcn456418 skips word zero; fcn4563f5 copies the opaque background/patch.
    return resource == 13 or (resource == 12 and chunk in (1, 2, 7, 8)) or (resource == 15 and (1 <= chunk <= 6 or chunk >= 22))


def _existing_scene_resource(edition: str, resource: int, items: list[dict], output: Path, archive_sha256: str, payload_sha256: str, zip_member: str, visual) -> dict:
    chunks = {}
    for item in items:
        relative = Path("images") / edition / "ui" / "Panel" / str(resource) / f"{item['chunk_index']}.png"
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        source = Path(item["path"]).expanduser().resolve()
        transparent = _static_transparent(resource, item["chunk_index"])
        chunk = visual.chunks[item["chunk_index"]]
        if (chunk.index, chunk.width, chunk.height, chunk.x, chunk.y) != tuple(item[key] for key in ("chunk_index", "width", "height", "x", "y")):
            raise AssetError("existing-art dimensions differ from source SMP")
        if transparent:
            # Source non-zero blit skips WORD 0, not every RGB-black pixel.
            # Never follow an earlier output symlink and modify the shared cache.
            if target.is_symlink(): target.unlink()
            write_smp_png(target, chunk, visual, pixel_format="rgb555", transparent_word_zero=True)
        elif target.exists() or target.is_symlink():
            if not target.is_symlink() or target.resolve() != source:
                raise AssetError(f"existing-art output collision: {relative.as_posix()}")
        else:
            target.symlink_to(source)
        chunks[str(item["chunk_index"])] = {
            "path": relative.as_posix(), "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "source_cache_sha256": item["sha256"], "transparent_word_zero": transparent, "width": item["width"], "height": item["height"],
            "logical": {"width": item["width"], "height": item["height"], "anchor_x": item["x"], "anchor_y": item["y"]},
        }
    return {
        "resource_index": resource, "payload_sha256": payload_sha256, "signature": "SMP", "format": "SMP", "pixel_format": "rgb555", "transparent_word_zero": "per-chunk",
        "source": {"edition": edition, "archive": "Panel.mkf", "zip_member": zip_member, "resource_index": resource, "payload_sha256": payload_sha256, "archive_sha256": archive_sha256},
        "output": {"format": "png", "pixel_format": "rgb555", "transparent_word_zero": "per-chunk"}, "chunks": chunks,
    }


def _generated_scene_resource(edition: str, resource: int, group: dict) -> dict:
    settings = group["caller"]
    chunks = {}
    for index, frame in group["frames"].items():
        frame = dict(frame); frame.pop("frame_index", None); frame.pop("caller", None)
        frame["logical"] = {"width": frame["width"], "height": frame["height"], "anchor_x": settings["x"], "anchor_y": settings["y"]}
        chunks[index] = frame
    return {
        "resource_index": resource, "payload_sha256": group["payload_sha256"], "signature": "FLIC", "format": "FLIC", "pixel_format": "rgba8888", "transparent_index_zero": settings["transparent_index_zero"],
        "source": {"edition": edition, "archive": "Panel.mkf", "zip_member": group["zip_member"], "resource_index": resource, "payload_sha256": group["payload_sha256"], "archive_sha256": group["archive_sha256"]},
        "output": {"format": "png", "pixel_format": "rgba8888", "transparent_index_zero": settings["transparent_index_zero"]}, "chunks": chunks,
    }


def prepare(zip_path: Path, output: Path, base_manifest: Path | None = None, existing_art: Path | None = None) -> dict:
    output = output.expanduser().resolve(); zip_path = zip_path.expanduser().resolve()
    if not zip_path.is_file(): raise AssetError(f"owner ZIP is unavailable: {zip_path}")
    output.mkdir(parents=True, exist_ok=True)
    base = None
    base_scene = None
    if base_manifest is not None:
        base_manifest = base_manifest.expanduser().resolve()
        if not base_manifest.is_file(): raise AssetError(f"base manifest is unavailable: {base_manifest}")
        base_data = json.loads(base_manifest.read_text(encoding="utf-8"))
        base = {"path": str(base_manifest), "sha256": hashlib.sha256(base_manifest.read_bytes()).hexdigest(), "schema": base_data.get("schema")}
        if base.get("schema") != "richman4.scene-images/v1":
            raise AssetError("base manifest has an unsupported schema")
        base_scene = _rewrite_base_paths(base_data)
    existing = _load_existing_art(existing_art.expanduser().resolve()) if existing_art is not None else None
    resources = {}
    panel_identity = {}
    static_visuals = {}
    with zipfile.ZipFile(zip_path) as archive:
        for edition in EDITIONS:
            name = f"dfw4cskzl_136622/{edition}/Panel.mkf"
            with archive.open(name) as source: panel_data = source.read()
            mkf = parse_mkf(Path(name), panel_data)
            panel_hash = hashlib.sha256(panel_data).hexdigest()
            panel_identity[edition] = {"archive_sha256": panel_hash, "zip_member": name, "payloads": {}}
            groups = {}
            for resource, settings in RESOURCES.items():
                entry = mkf.entries[resource]; decoded = decode_entry(mkf, entry)
                width, height, frames = decode_flic(decoded)
                payload_hash = hashlib.sha256(decoded).hexdigest()
                group = {"resource_index": resource, "archive": "Panel.mkf", "zip_member": name, "archive_sha256": panel_hash, "payload_sha256": payload_hash, "signature": "FLIC", "frame_count": len(frames), "caller": dict(settings), "frames": {}}
                for index, (pixels, palette) in enumerate(frames):
                    relative = Path("images") / edition / "ui" / "Panel" / str(resource) / f"{index}.png"; target = output / relative
                    write_png(target, pixels, palette, width, height, settings["transparent_index_zero"])
                    group["frames"][str(index)] = _frame_record(relative, target, width, height, index, settings)
                groups[str(resource)] = group
            if existing is not None:
                for resource in REUSED_RESOURCES:
                    payload = decode_entry(mkf, mkf.entries[resource])
                    panel_identity[edition]["payloads"][str(resource)] = hashlib.sha256(payload).hexdigest()
                    visual = parse_visual_resource(payload, mkf.entries[resource])
                    if visual is None or visual.signature != "SMP": raise AssetError("lottery static resource must be SMP")
                    static_visuals[(edition, resource)] = visual
            resources[edition] = groups
    manifest = {"schema": "richman4.lottery-assets/v1", "version": 1, "base_manifest": base, "resources": resources, "static_assets": {"resources": [12, 13, 15], "background_12_15_chunk0": "existing opaque PNG symlink", "overlays": "source SMP word-zero transparent PNG"}}
    manifest_path = output / "manifest.json"; temporary = manifest_path.with_suffix(".json.tmp"); temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"); temporary.replace(manifest_path)
    if base_scene is not None and existing is not None:
        base_link = output / "images" / "base"
        if base_link.exists() or base_link.is_symlink():
            if not base_link.is_symlink() or base_link.resolve() != base_manifest.parent / "images":
                raise AssetError(f"base image link collision: {base_link}")
        else:
            base_link.parent.mkdir(parents=True, exist_ok=True)
            base_link.symlink_to(base_manifest.parent / "images", target_is_directory=True)
        for edition in EDITIONS:
            panel = base_scene["ui"][edition]["Panel"]
            for resource in REUSED_RESOURCES:
                panel["resources"][str(resource)] = _existing_scene_resource(edition, resource, existing[(edition, resource)], output, panel_identity[edition]["archive_sha256"], panel_identity[edition]["payloads"][str(resource)], panel_identity[edition]["zip_member"], static_visuals[(edition, resource)])
            for resource in RESOURCES:
                panel["resources"][str(resource)] = _generated_scene_resource(edition, resource, resources[edition][str(resource)])
        scene_path = output / "scene-manifest.json"
        temporary_scene = scene_path.with_suffix(".json.tmp")
        temporary_scene.write_text(json.dumps(base_scene, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary_scene.replace(scene_path)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--zip", dest="zip_path", type=Path, required=True); parser.add_argument("--output", type=Path, required=True); parser.add_argument("--base-manifest", type=Path); parser.add_argument("--existing-art", type=Path)
    args = parser.parse_args()
    try: result = prepare(args.zip_path, args.output, args.base_manifest, args.existing_art)
    except (AssetError, OSError, KeyError, IndexError, zipfile.BadZipFile) as error: parser.exit(1, f"lottery asset preparation failed: {error}\n")
    print(f"Prepared lottery FLIC assets: {sum(len(v) for v in result['resources'].values())} resources")
    return 0


if __name__ == "__main__": raise SystemExit(main())
