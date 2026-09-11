#!/usr/bin/env python3
"""Focused checks for the private S20 Panel10 preparation output."""
from __future__ import annotations

import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from prepare_source_shop import (  # noqa: E402
    CHUNK_COUNT,
    EDITIONS,
    OPAQUE_CHUNKS,
    RESOURCE_INDEX,
    SELECTED_CHUNKS,
    TRANSPARENT_CHUNKS,
    _load_identity,
    _rewrite_base_paths,
)


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


class SourceShopAssetTests(unittest.TestCase):
    def test_identity_enumerates_complete_panel10_resources(self):
        identity_value = os.environ.get("SOURCE_SHOP_IDENTITY")
        if not identity_value:
            self.skipTest("SOURCE_SHOP_IDENTITY is not set")
        identity_path = Path(identity_value)
        if not identity_path.is_file():
            self.fail("SOURCE_SHOP_IDENTITY is configured but unavailable")
        selected = _load_identity(identity_path)
        self.assertEqual(set(selected), {(edition, RESOURCE_INDEX) for edition in EDITIONS})
        self.assertTrue(all(len(value["chunks"]) == CHUNK_COUNT for value in selected.values()))

    def test_generated_output_preserves_callback_alpha_roles(self):
        root_value = os.environ.get("SOURCE_SHOP_ASSET_ROOT")
        if not root_value:
            self.skipTest("SOURCE_SHOP_ASSET_ROOT is not set")
        root = Path(root_value)
        if not root.is_dir():
            self.fail("SOURCE_SHOP_ASSET_ROOT is configured but unavailable")
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema"], "richman4.source-shop-assets/v1")
        self.assertEqual(manifest["selected_chunks"], list(SELECTED_CHUNKS))
        for edition in EDITIONS:
            chunks = manifest["resources"][edition]["chunks"]
            self.assertEqual(set(chunks), {str(index) for index in SELECTED_CHUNKS})
            for index in SELECTED_CHUNKS:
                frame = chunks[str(index)]
                width, height, rgba = _png_rgba(root / frame["path"])
                self.assertEqual((width, height), (frame["width"], frame["height"]))
                alpha = rgba[3::4]
                if index in OPAQUE_CHUNKS:
                    self.assertTrue(all(value == 255 for value in alpha))
                    self.assertFalse(frame["transparent_word_zero"])
                else:
                    self.assertTrue(frame["transparent_word_zero"])
                    if frame["source_zero_word_count"]:
                        self.assertTrue(any(value == 0 for value in alpha))
                    else:
                        # A transparent callback does not imply that this
                        # particular source chunk contains a zero word.
                        self.assertTrue(all(value == 255 for value in alpha))
        self.assertEqual(OPAQUE_CHUNKS | TRANSPARENT_CHUNKS, frozenset(SELECTED_CHUNKS))

    def test_unconfigured_private_inputs_skip_without_reading_working_directory(self):
        for value in (None, ""):
            for method, variable in (
                ("test_generated_output_preserves_callback_alpha_roles", "SOURCE_SHOP_ASSET_ROOT"),
                ("test_identity_enumerates_complete_panel10_resources", "SOURCE_SHOP_IDENTITY"),
            ):
                with self.subTest(value=value, method=method), tempfile.TemporaryDirectory() as temporary:
                    # A cwd that looks like asset output must still never be read.
                    Path(temporary, "manifest.json").write_text("invalid sentinel")
                    environment = os.environ.copy()
                    environment.pop(variable, None)
                    if value is not None:
                        environment[variable] = value
                    result = subprocess.run(
                        [sys.executable, str(Path(__file__).resolve()), "SourceShopAssetTests." + method, "-v"],
                        cwd=temporary, env=environment, capture_output=True, text=True, check=False,
                    )
                    output = result.stdout + result.stderr
                    self.assertEqual(result.returncode, 0, output)
                    self.assertIn("Ran 1 test", output)
                    self.assertIn("OK (skipped=1)", output)
                    self.assertIn(variable + " is not set", output)

    def test_rewrite_keeps_resolved_base_paths_idempotent(self):
        tiny = {
            "maps": [{"path": "images/base/Game/map/1.png"}],
            "ui": {"Game": {"Panel": {"resources": {"11": {"chunks": {"0": {"path": "images/Game/ui/Panel/11/0.png"}}}}}}},
        }
        rewritten = _rewrite_base_paths(tiny)
        self.assertEqual(rewritten["maps"][0]["path"], "images/base/Game/map/1.png")
        self.assertEqual(rewritten["ui"]["Game"]["Panel"]["resources"]["11"]["chunks"]["0"]["path"], "images/base/Game/ui/Panel/11/0.png")
        self.assertEqual(_rewrite_base_paths(rewritten), rewritten)


if __name__ == "__main__":
    unittest.main()
