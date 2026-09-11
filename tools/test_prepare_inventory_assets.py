#!/usr/bin/env python3
"""Focused checks for the private Panel11 preparation output."""
from __future__ import annotations

import json
import os
from pathlib import Path
import struct
import sys
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_inventory_assets import CHUNK_COUNT, EDITIONS, RESOURCE_INDEX, TRANSPARENT_CHUNKS, _load_identity, _rewrite_base_paths


def _png_rgba(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"not a PNG: {path}")
    width, height, depth, color_type = struct.unpack(">IIBB", data[16:26])
    if depth != 8 or color_type != 6:
        raise AssertionError(f"PNG is not RGBA8: {path}")
    cursor = 8
    compressed = bytearray()
    while cursor < len(data):
        size = struct.unpack_from(">I", data, cursor)[0]
        kind = data[cursor + 4 : cursor + 8]
        payload = data[cursor + 8 : cursor + 8 + size]
        if kind == b"IDAT":
            compressed.extend(payload)
        cursor += size + 12
    raw = zlib.decompress(compressed)
    stride = width * 4
    rows = bytearray()
    for row in range(height):
        if raw[row * (stride + 1)] != 0:
            raise AssertionError(f"PNG uses a filtered row: {path}")
        rows.extend(raw[row * (stride + 1) + 1 : row * (stride + 1) + 1 + stride])
    return width, height, bytes(rows)


class InventoryAssetTests(unittest.TestCase):
    def test_identity_enumerates_both_panel11_resources(self):
        identity_path = Path(os.environ.get("PANEL11_IDENTITY", ""))
        if not identity_path.is_file():
            self.skipTest("PANEL11_IDENTITY is not set")
        selected = _load_identity(identity_path)
        self.assertEqual(set(selected), {(edition, RESOURCE_INDEX) for edition in EDITIONS})
        self.assertTrue(all(len(value["chunks"]) == CHUNK_COUNT for value in selected.values()))

    def test_generated_output_keeps_background_and_icon_alpha_roles(self):
        root = Path(os.environ.get("INVENTORY_ASSET_ROOT", ""))
        if not root.is_dir():
            self.skipTest("INVENTORY_ASSET_ROOT is not set")
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema"], "richman4.inventory-assets/v1")
        for edition in EDITIONS:
            chunks = manifest["resources"][edition]["chunks"]
            self.assertEqual(len(chunks), CHUNK_COUNT)
            for index in range(CHUNK_COUNT):
                frame = chunks[str(index)]
                width, height, rgba = _png_rgba(root / frame["path"])
                self.assertEqual((width, height), (frame["width"], frame["height"]))
                alpha = rgba[3::4]
                if index in TRANSPARENT_CHUNKS:
                    self.assertTrue(any(value == 0 for value in alpha))
                else:
                    self.assertTrue(all(value == 255 for value in alpha))

    def test_base_manifest_paths_resolve_through_private_parent_link(self):
        with self.subTest("nested map character and UI records"):
            tiny = {
                "maps": [{"path": "images/Game/map/1.png"}],
                "characters": {"Game": {"path": "images/Game/character/1.png"}},
                "ui": {"Game": {"Panel": {"resources": {"3": {"chunks": {"0": {"path": "images/Game/ui/Panel/3/0.png"}}}}}}},
            }
            rewritten = _rewrite_base_paths(tiny)
            self.assertEqual(rewritten["maps"][0]["path"], "images/base/Game/map/1.png")
            self.assertEqual(rewritten["characters"]["Game"]["path"], "images/base/Game/character/1.png")
            self.assertEqual(rewritten["ui"]["Game"]["Panel"]["resources"]["3"]["chunks"]["0"]["path"], "images/base/Game/ui/Panel/3/0.png")
            self.assertEqual(_rewrite_base_paths(rewritten), rewritten)

    def test_base_manifest_parent_resolution_and_panel11_overlay_boundary(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_images = root / "source" / "images" / "Game" / "map"
            source_images.mkdir(parents=True)
            (source_images / "1.png").write_bytes(b"map")
            output = root / "inventory"
            (output / "images").mkdir(parents=True)
            (output / "images" / "Game" / "ui" / "Panel" / "11").mkdir(parents=True)
            (output / "images" / "Game" / "ui" / "Panel" / "11" / "15.png").write_bytes(b"overlay")
            (output / "images" / "base").symlink_to(root / "source" / "images", target_is_directory=True)
            scene = _rewrite_base_paths({"maps": [{"path": "images/Game/map/1.png"}], "ui": {"Game": {"Panel": {"resources": {}}}}})
            scene["ui"]["Game"]["Panel"]["resources"]["11"] = {"chunks": {"15": {"path": "images/Game/ui/Panel/11/15.png"}}}
            scene_path = output / "scene-manifest.json"
            scene_path.write_text(json.dumps(scene), encoding="utf-8")
            base_path = scene["maps"][0]["path"]
            overlay_path = scene["ui"]["Game"]["Panel"]["resources"]["11"]["chunks"]["15"]["path"]
            self.assertTrue((scene_path.parent / base_path).exists())
            self.assertTrue((scene_path.parent / overlay_path).exists())
            self.assertFalse(overlay_path.startswith("images/base/"))


if __name__ == "__main__":
    unittest.main()
