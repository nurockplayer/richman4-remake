#!/usr/bin/env python3
"""Focused checks for the bounded private S21 source SALE preparation.

The live identity/contract tests are driven by SALE_PANEL7374_IDENTITY.  The
selection, alpha, anchor, overlay and error-handling checks use synthetic
inputs so they run without touching private source material.
"""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from decode_original_images import VisualChunk, VisualResource  # noqa: E402
from prepare_source_sale import (  # noqa: E402
    CATEGORY_DETAIL_MAP,
    CHUNK_COUNTS,
    CHUNK_ROLES,
    EDITIONS,
    EXPECTED_BASE_SHA256,
    EXPECTED_IDENTITY_SHA256,
    MAX_NEW_OUTPUT_BYTES,
    OPAQUE_CHUNKS,
    RESOURCE_INDEXES,
    SELECTED_CHUNKS,
    SOURCE_ASM_SHA256,
    TRANSPARENT_CHUNKS,
    AssetError,
    _enforce_limits,
    _estimate_output_bytes,
    _load_identity,
    _overlay_scene,
    _preflight_targets,
    _sha256,
    _write_selected_chunk,
    prepare,
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


def _identity_path() -> Path | None:
    value = os.environ.get("SALE_PANEL7374_IDENTITY")
    if not value:
        return None
    path = Path(value)
    return path if path.is_file() else None


class SourceSaleSelectionTests(unittest.TestCase):
    def test_selection_is_bounded_to_panel73_and_panel74(self):
        self.assertEqual(RESOURCE_INDEXES, (73, 74))
        self.assertEqual(SELECTED_CHUNKS[73], tuple(range(0, 20)))
        self.assertEqual(SELECTED_CHUNKS[74], tuple(range(0, 13)))
        self.assertEqual(CHUNK_COUNTS, {73: 20, 74: 13})
        self.assertEqual(sum(len(value) for value in SELECTED_CHUNKS.values()) * len(EDITIONS), 66)
        self.assertEqual(EXPECTED_BASE_SHA256, "6f3acbbc87aada42688e396afcbefc2b418958d30f576fac2eeeeef75fc96c30")
        self.assertEqual(EXPECTED_IDENTITY_SHA256, "ab4e69bf4066f9b456341d07acc82055bbf4687db4baa7c7cbc944ecf5db5800")
        self.assertEqual(SOURCE_ASM_SHA256, "750b782654839143d9b9a0ae53fa1a3a037e51982ea03ae28a1b35a6603dfbde")

    def test_alpha_classification_matches_frozen_source_callbacks(self):
        self.assertEqual(TRANSPARENT_CHUNKS[73], frozenset({3, 4}))
        self.assertEqual(OPAQUE_CHUNKS[73], frozenset(set(range(0, 20)) - {3, 4}))
        self.assertIn(18, OPAQUE_CHUNKS[73])
        self.assertIn(19, OPAQUE_CHUNKS[73])
        self.assertEqual(TRANSPARENT_CHUNKS[74], frozenset(range(0, 13)))
        self.assertEqual(OPAQUE_CHUNKS[74], frozenset())

    def test_per_chunk_roles_cover_every_selected_chunk(self):
        for index in RESOURCE_INDEXES:
            self.assertEqual(set(CHUNK_ROLES[index]), set(SELECTED_CHUNKS[index]))
            self.assertTrue(all(CHUNK_ROLES[index][chunk] for chunk in SELECTED_CHUNKS[index]))
        self.assertEqual(CHUNK_ROLES[73][0], ("bulletin_board",))
        self.assertEqual(CHUNK_ROLES[73][18], ("stock_checkmark",))
        self.assertEqual(CHUNK_ROLES[73][19], ("property_page_tab",))
        self.assertEqual(CATEGORY_DETAIL_MAP, (7, 8, 6, 6))

    def test_identity_contract_matches_frozen_input(self):
        path = _identity_path()
        if path is None:
            self.skipTest("SALE_PANEL7374_IDENTITY is not set")
        self.assertEqual(_sha256(path), EXPECTED_IDENTITY_SHA256)
        selected = _load_identity(path)
        self.assertEqual(
            set(selected),
            {(edition, index) for edition in EDITIONS for index in RESOURCE_INDEXES},
        )
        for (edition, index), record in selected.items():
            self.assertEqual(record["chunk_count"], CHUNK_COUNTS[index], (edition, index))
            self.assertEqual([chunk["index"] for chunk in record["chunks"]], list(range(CHUNK_COUNTS[index])))
            for chunk in record["chunks"]:
                for field in ("width", "height", "x", "y", "pixel_data_sha256"):
                    self.assertIn(field, chunk)

    def test_identity_mismatch_is_rejected(self):
        path = _identity_path()
        if path is None:
            self.skipTest("SALE_PANEL7374_IDENTITY is not set")
        original = json.loads(path.read_text(encoding="utf-8"))
        mutations = {}

        wrong_schema = copy.deepcopy(original)
        wrong_schema["schema"] = "richman4.source-shop-panel10-identity/v1"
        mutations["schema"] = wrong_schema

        missing_record = copy.deepcopy(original)
        missing_record["records"] = missing_record["records"][:-1]
        mutations["record count"] = missing_record

        wrong_index = copy.deepcopy(original)
        wrong_index["records"][0]["physical_index"] = 10
        mutations["physical index"] = wrong_index

        malformed_hash = copy.deepcopy(original)
        malformed_hash["records"][0]["chunks"][0]["pixel_data_sha256"] = "not-a-hash"
        mutations["malformed pixel hash"] = malformed_hash

        missing_field = copy.deepcopy(original)
        missing_field["records"][0]["chunks"][0].pop("pixel_data_sha256")
        mutations["missing pixel hash"] = missing_field

        with tempfile.TemporaryDirectory() as temporary:
            for label, value in mutations.items():
                with self.subTest(label):
                    target = Path(temporary) / f"{label}.json"
                    target.write_text(json.dumps(value), encoding="utf-8")
                    with self.assertRaises(AssetError):
                        _load_identity(target)

    def test_identity_value_mismatch_is_rejected_at_decode(self):
        identity = _identity_path()
        zip_value = os.environ.get("SALE_SOURCE_ZIP")
        if identity is None or not zip_value or not Path(zip_value).is_file():
            self.skipTest("SALE_PANEL7374_IDENTITY or SALE_SOURCE_ZIP is not set")
        original = json.loads(identity.read_text(encoding="utf-8"))
        tampered = copy.deepcopy(original)
        tampered["records"][0]["chunks"][0]["pixel_data_sha256"] = "0" * 64
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tampered_path = root / "tampered-identity.json"
            tampered_path.write_text(json.dumps(tampered), encoding="utf-8")
            base = root / "scene-manifest.json"
            base.write_text(
                json.dumps({"schema": "richman4.scene-images/v1", "maps": [], "characters": {}}),
                encoding="utf-8",
            )
            with self.assertRaises(AssetError):
                prepare(Path(zip_value), root / "out", tampered_path, base)

    def test_anchors_are_preserved_from_identity(self):
        path = _identity_path()
        if path is None:
            self.skipTest("SALE_PANEL7374_IDENTITY is not set")
        selected = _load_identity(path)
        for edition in EDITIONS:
            record = selected[(edition, 74)]
            self.assertTrue(any(chunk["x"] or chunk["y"] for chunk in record["chunks"]))
            for chunk in record["chunks"]:
                self.assertNotEqual((chunk["x"], chunk["y"]), (0, 0))
            panel73 = selected[(edition, 73)]
            self.assertTrue(all((chunk["x"], chunk["y"]) == (0, 0) for chunk in panel73["chunks"]))

    def test_pinned_base_rejects_non_latest_manifest(self):
        path = _identity_path()
        if path is None:
            self.skipTest("SALE_PANEL7374_IDENTITY is not set")
        zip_value = os.environ.get("SALE_SOURCE_ZIP")
        if not zip_value or not Path(zip_value).is_file():
            self.skipTest("SALE_SOURCE_ZIP is not set")
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary) / "scene-manifest.json"
            base.write_text(json.dumps({"schema": "richman4.scene-images/v1", "maps": [], "characters": {}}), encoding="utf-8")
            with self.assertRaises(AssetError):
                prepare(
                    Path(zip_value),
                    Path(temporary) / "out",
                    path,
                    base,
                    expected_base_sha256=EXPECTED_BASE_SHA256,
                    expected_identity_sha256=EXPECTED_IDENTITY_SHA256,
                )


class SourceSaleAlphaOutputTests(unittest.TestCase):
    def _resource(self) -> tuple[VisualResource, VisualChunk]:
        chunk = VisualChunk(0, 2, 1, 5, 6, struct.pack("<HH", 0x0000, 0x7FFF))
        visual = VisualResource("SMP", 1, 0, None, (chunk,))
        return visual, chunk

    def test_rgb555_alpha_follows_policy_not_source_colour(self):
        visual, chunk = self._resource()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            transparent = root / "transparent.png"
            opaque = root / "opaque.png"
            _write_selected_chunk(transparent, chunk, visual, True)
            _write_selected_chunk(opaque, chunk, visual, False)
            width, height, rgba = _png_rgba(transparent)
            self.assertEqual((width, height), (2, 1))
            self.assertEqual(rgba[:3], b"\x00\x00\x00")
            self.assertEqual(rgba[3], 0)
            self.assertEqual(rgba[7], 255)
            width, height, rgba = _png_rgba(opaque)
            self.assertEqual((width, height), (2, 1))
            self.assertEqual(rgba[:3], b"\x00\x00\x00")
            self.assertEqual(rgba[3], 255)
            self.assertEqual(rgba[7], 255)

    def test_output_collision_is_rejected(self):
        visual, chunk = self._resource()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            existing = root / "0.png"
            existing.write_bytes(b"occupied")
            with self.assertRaises(AssetError):
                _write_selected_chunk(existing, chunk, visual, True)

    def test_preflight_rejects_an_existing_selected_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "images" / "Game" / "ui" / "Panel" / "73" / "0.png"
            target.parent.mkdir(parents=True)
            target.write_bytes(b"occupied")
            with self.assertRaises(AssetError):
                _preflight_targets(root)

    def test_bounded_output_estimate_guard(self):
        tiny = {("Game", 74): {"physical_index": 74, "chunks": [{"index": 0, "width": 4, "height": 4}]}}
        self.assertGreater(_estimate_output_bytes(tiny), 0)
        with tempfile.TemporaryDirectory() as temporary:
            huge = {
                ("Game", 73): {
                    "physical_index": 73,
                    "chunks": [
                        {"index": index, "width": 4096, "height": 4096}
                        for index in SELECTED_CHUNKS[73]
                    ],
                }
            }
            estimate = _estimate_output_bytes(huge)
            self.assertGreater(estimate, MAX_NEW_OUTPUT_BYTES)
            with self.assertRaises(AssetError):
                _enforce_limits(estimate, Path(temporary) / "out")


class SourceSaleOverlayTests(unittest.TestCase):
    def _base_scene(self) -> dict:
        return {
            "schema": "richman4.scene-images/v1",
            "version": 3,
            "pixel_format": "rgb555",
            "maps": [{"path": "images/base/Game/map-01.png", "role": "board"}],
            "characters": {"Game": {"path": "images/base/Game/characters/1.png"}},
            "ui": {
                "Game": {
                    "Panel": {
                        "archive": "Panel.mkf",
                        "archive_sha256": "abc",
                        "resources": {
                            "10": {"resource_index": 10, "chunks": {"0": {"path": "images/Game/ui/Panel/10/0.png"}}},
                            "11": {"resource_index": 11, "chunks": {"0": {"path": "images/Game/ui/Panel/11/0.png"}}},
                        },
                    },
                    "help": {"path": "images/base/Game/ui/help/1.png"},
                },
                "MultiverseJourney": {"Panel": {"resources": {}}},
            },
        }

    def _resources(self) -> dict:
        return {
            edition: {
                str(index): {"resource_index": index, "chunks": {"0": {"path": f"images/{edition}/ui/Panel/{index}/0.png"}}}
                for index in RESOURCE_INDEXES
            }
            for edition in EDITIONS
        }

    def test_overlay_preserves_every_prior_field_and_adds_only_7374(self):
        base = self._base_scene()
        before = copy.deepcopy(base)
        scene = _overlay_scene(base, self._resources())
        self.assertEqual(base, before)
        self.assertEqual(scene["maps"], before["maps"])
        self.assertEqual(scene["characters"], before["characters"])
        self.assertEqual(scene["ui"]["Game"]["help"], before["ui"]["Game"]["help"])
        for edition in EDITIONS:
            resources = scene["ui"][edition]["Panel"]["resources"]
            for index in RESOURCE_INDEXES:
                self.assertIn(str(index), resources)
        game_resources = scene["ui"]["Game"]["Panel"]["resources"]
        self.assertEqual(set(game_resources), {"10", "11", "73", "74"})
        self.assertEqual(game_resources["10"], before["ui"]["Game"]["Panel"]["resources"]["10"])
        self.assertEqual(game_resources["11"], before["ui"]["Game"]["Panel"]["resources"]["11"])
        self.assertEqual(scene["ui"]["Game"]["Panel"]["archive_sha256"], "abc")

    def test_overlay_rejects_a_duplicate_resource(self):
        base = self._base_scene()
        base["ui"]["Game"]["Panel"]["resources"]["73"] = {"resource_index": 73}
        with self.assertRaises(AssetError):
            _overlay_scene(base, self._resources())

    def test_overlay_keeps_inherited_image_references_resolvable(self):
        base = self._base_scene()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in (
                "images/base/Game/map-01.png",
                "images/base/Game/characters/1.png",
                "images/base/Game/ui/help/1.png",
                "images/Game/ui/Panel/10/0.png",
                "images/Game/ui/Panel/11/0.png",
            ):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"x")
            scene = _overlay_scene(base, self._resources())
            scene_path = root / "scene-manifest.json"
            scene_path.write_text(json.dumps(scene), encoding="utf-8")
            for path in (
                scene["maps"][0]["path"],
                scene["characters"]["Game"]["path"],
                scene["ui"]["Game"]["help"]["path"],
                scene["ui"]["Game"]["Panel"]["resources"]["10"]["chunks"]["0"]["path"],
            ):
                self.assertTrue((root / path).exists(), path)


class SourceSaleSkipTests(unittest.TestCase):
    def test_identity_tests_skip_without_configuration(self):
        test_file = str(Path(__file__).resolve())
        environment = os.environ.copy()
        environment.pop("SALE_PANEL7374_IDENTITY", None)
        environment.pop("SALE_SOURCE_ZIP", None)
        result = subprocess.run(
            [
                sys.executable,
                test_file,
                "SourceSaleSelectionTests.test_identity_contract_matches_frozen_input",
                "-v",
            ],
            cwd=tempfile.gettempdir(),
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Ran 1 test", output)
        self.assertIn("OK (skipped=1)", output)
        self.assertIn("SALE_PANEL7374_IDENTITY is not set", output)


if __name__ == "__main__":
    unittest.main()
