#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_lottery_assets import _decode_ss2, _load_existing_art, _rewrite_base_paths, decode_flic, write_png, AssetError, _existing_scene_resource, _static_transparent
from decode_original_images import VisualChunk, VisualResource


def _flic(frame_payloads: list[bytes], width: int = 2, height: int = 1) -> bytes:
    frames = []
    for index, pixels in enumerate(frame_payloads):
        if index == 0:
            palette = struct.pack("<H", 1) + bytes([0, 2, 0, 0, 0, 63, 0, 0])
            brun = bytes([1, 0xFE]) + pixels
            subs = [struct.pack("<IH", len(palette) + 6, 4) + palette, struct.pack("<IH", len(brun) + 6, 15) + brun]
        else:
            ss2 = struct.pack("<H", 1) + bytes([1, 0, 0, 1]) + bytes([pixels[0], pixels[1]])
            subs = [struct.pack("<IH", len(ss2) + 6, 7) + ss2]
        body = b"".join(subs)
        frames.append(struct.pack("<IHHHH", 16 + len(body), 0xF1FA, len(subs), 0, 0) + b"\0\0\0\0" + body)
    header = bytearray(128); struct.pack_into("<IHHHHH", header, 0, 128 + sum(map(len, frames)), 0xAF12, len(frames), width, height, 8)
    return bytes(header) + b"".join(frames)


class LotteryAssetTests(unittest.TestCase):
    def test_flic_frames_and_delta(self):
        width, height, frames = decode_flic(_flic([bytes([1, 2]), bytes([2, 1])]))
        self.assertEqual((width, height), (2, 1)); self.assertEqual(list(frames[0][0]), [1, 2]); self.assertEqual(list(frames[1][0]), [2, 1])

    def test_png_zero_index_policy(self):
        # Two equally black palette entries: only index zero is transparent.
        with tempfile.TemporaryDirectory() as folder:
            for transparent in (True, False):
                path = Path(folder) / "a.png"
                write_png(path, bytearray([0, 1]), [(0, 0, 0)] * 256, 2, 1, transparent)
                data = path.read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                cursor = 8
                compressed = bytearray()
                while cursor < len(data):
                    size = struct.unpack_from(">I", data, cursor)[0]
                    if data[cursor + 4:cursor + 8] == b"IDAT":
                        compressed.extend(data[cursor + 8:cursor + 8 + size])
                    cursor += size + 12
                self.assertEqual(zlib.decompress(compressed), bytes([0, 0, 0, 0, 0 if transparent else 255, 0, 0, 0, 255]))

    def test_static_source_word_zero_and_opaque_background(self):
        # 0x0000 and 0x8000 both decode to RGB black; only the first is skipped.
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "source.png"
            source.write_bytes(b"opaque-cache-is-preserved")
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            item = {"chunk_index": 0, "width": 2, "height": 1, "x": 0, "y": 0, "path": str(source), "sha256": source_hash}
            visual = VisualResource("SMP", 1, 0, None, (VisualChunk(0, 2, 1, 0, 0, struct.pack("<HH", 0, 0x8000)),))
            result = _existing_scene_resource("Game", 13, [item], root / "output", "archive", "payload", "member", visual)
            target = root / "output" / result["chunks"]["0"]["path"]
            data = target.read_bytes()
            offset = data.index(b"IDAT")
            length = struct.unpack_from(">I", data, offset - 4)[0]
            self.assertEqual(zlib.decompress(data[offset + 4:offset + 4 + length]), bytes([0, 0, 0, 0, 0, 0, 0, 0, 255]))
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), source_hash)
            background = _existing_scene_resource("Game", 12, [item], root / "output", "archive", "payload", "member", visual)
            self.assertFalse(background["chunks"]["0"]["transparent_word_zero"])
            self.assertTrue((root / "output" / background["chunks"]["0"]["path"]).is_symlink())
            self.assertFalse(_static_transparent(12, 9))
            self.assertFalse(_static_transparent(15, 21))
            self.assertTrue(_static_transparent(15, 22))

    def test_ss2_signed_line_skip(self):
        pixels = bytearray([1] * 6)
        payload = struct.pack("<HhHbbBB", 1, -1, 1, 0, 1, 2, 3)
        _decode_ss2(payload, pixels, 2, 3)
        self.assertEqual(list(pixels), [1, 1, 2, 3, 1, 1])

    def test_bad_flic_fails_closed(self):
        with self.assertRaises(AssetError): decode_flic(b"bad")

    def test_scene_base_paths_are_rewritten_only_for_images(self):
        value = {"path": "images/Game/ui.png", "name": "images are source-backed", "nested": ["other/images/x.png"]}
        self.assertEqual(_rewrite_base_paths(value), {"path": "images/base/Game/ui.png", "name": "images are source-backed", "nested": ["other/images/x.png"]})

    def test_standard_original_images_manifest_is_supported(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); resources = []
            for edition in ("Game", "MultiverseJourney"):
                for resource in (12, 13, 15):
                    relative = Path("images") / edition / "Panel" / f"resource-{resource:04d}" / "chunk-0000.png"
                    target = root / relative; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(b"png")
                    resources.append({"edition": edition, "archive": f"{edition}/Panel.mkf", "resource_index": resource, "images": [{"chunk_index": 0, "width": 1, "height": 1, "x": 0, "y": 0, "path": relative.as_posix(), "sha256": hashlib.sha256(b"png").hexdigest()}]})
            manifest = root / "manifest.json"; manifest.write_text(json.dumps({"schema": "richman4.original-images/v1", "visual_resources": resources}))
            selected = _load_existing_art(manifest)
            self.assertEqual(sorted((key, len(value)) for key, value in selected.items()), sorted(((edition, resource), 1) for edition in ("Game", "MultiverseJourney") for resource in (12, 13, 15)))


if __name__ == "__main__": unittest.main()
