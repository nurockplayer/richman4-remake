#!/usr/bin/env python3
"""Focused checks for the private Panel11 preparation output."""
from __future__ import annotations

import json
import os
from pathlib import Path
from types import SimpleNamespace
import struct
import subprocess
import sys
from unittest import mock
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_inventory_assets as inventory
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
    def _patch_fixture(self, root: Path):
        """Create only the tiny files that patch_existing owns or references."""
        output = root / "inventory"
        source = root / "source"
        output.mkdir()
        source_images = source / "images" / "Game" / "map"
        source_images.mkdir(parents=True)
        (source_images / "1.png").write_bytes(b"base-map")
        zip_path = root / "owner.zip"
        zip_path.write_bytes(b"unused mock archive")
        identity_path = root / "identity.json"
        identity_path.write_text("{}", encoding="utf-8")
        base_manifest = source / "scene.json"
        base_manifest.write_text(json.dumps({"schema": "richman4.scene-images/v1"}), encoding="utf-8")
        image_root = output / "images"
        image_root.mkdir()
        for edition in EDITIONS:
            for index in range(CHUNK_COUNT):
                path = image_root / edition / "ui" / "Panel" / "11" / f"{index}.png"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(f"original:{edition}:{index}".encode())
        old_base = root / "old-base"
        (old_base / "kept").mkdir(parents=True)
        (old_base / "kept" / "link-target").write_bytes(b"old")
        (image_root / "base").symlink_to(old_base, target_is_directory=True)

        chunks = {}
        scene_resources = {}
        expected_chunks = []
        for index in range(CHUNK_COUNT):
            relative = f"images/Game/ui/Panel/11/{index}.png"
            chunks[str(index)] = {"path": relative, "sha256": "old", "transparent_word_zero": index in TRANSPARENT_CHUNKS}
            scene_resources[str(index)] = {"path": relative, "sha256": "old", "transparent_word_zero": index in TRANSPARENT_CHUNKS}
            expected_chunks.append({"index": index, "width": 1, "height": 1, "x": index, "y": 0, "pixel_data_sha256": inventory.hashlib.sha256(f"pixels:{index}".encode()).hexdigest()})
        resources = {edition: {"source": {"edition": edition}, "chunks": json.loads(json.dumps(chunks))} for edition in EDITIONS}
        scene_ui = {edition: {"Panel": {"resources": {"11": {"chunks": json.loads(json.dumps(scene_resources))}}}} for edition in EDITIONS}
        scene = {"schema": "richman4.scene-images/v1", "maps": [{"path": "images/Game/map/1.png"}], "characters": {}, "ui": scene_ui}
        (output / "manifest.json").write_text(json.dumps({"schema": "richman4.inventory-assets/v1", "resources": resources}), encoding="utf-8")
        (output / "scene-manifest.json").write_text(json.dumps(scene), encoding="utf-8")
        (output / "provenance.json").write_text(json.dumps({"resources": {}}), encoding="utf-8")
        identity = {(edition, RESOURCE_INDEX): {"archive_sha256": inventory.hashlib.sha256(f"archive:{edition}".encode()).hexdigest(), "payload_sha256": inventory.hashlib.sha256(f"payload:{edition}".encode()).hexdigest(), "chunks": expected_chunks} for edition in EDITIONS}
        fake_chunks = [SimpleNamespace(index=index, width=1, height=1, x=index, y=0, pixels=f"pixels:{index}".encode()) for index in range(CHUNK_COUNT)]
        visual = SimpleNamespace(signature="SMP", chunk_count=CHUNK_COUNT, chunks=fake_chunks)

        class FakeArchive:
            def __init__(self, _path): pass
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, member): return f"archive:{member.split('/')[1]}".replace("Game", "Game").encode()

        # Keep the archive payload identical to the edition-specific pinned bytes.
        FakeArchive.read = lambda self, member: f"archive:{member.split('/')[1]}".encode()
        return output, zip_path, identity_path, base_manifest, identity, visual, FakeArchive, None

    def _run_mock_patch(self, fixture, *, bad_second=False, ensure=None, write_json=None):
        output, zip_path, identity_path, base_manifest, identity, visual, FakeArchive, _ = fixture
        identity = {key: value.copy() for key, value in identity.items()}
        if bad_second:
            key = (EDITIONS[1], RESOURCE_INDEX)
            identity[key] = {**identity[key], "archive_sha256": "wrong"}
        archive_hash = {edition: f"archive:{edition}".encode() for edition in EDITIONS}
        payload_hash = {edition: f"payload:{edition}".encode() for edition in EDITIONS}
        with mock.patch.object(inventory.zipfile, "ZipFile", FakeArchive), \
             mock.patch.object(inventory, "_load_identity", return_value=identity), \
             mock.patch.object(inventory, "_load_json", side_effect=lambda path: json.loads(Path(path).read_text(encoding="utf-8"))), \
             mock.patch.object(inventory, "parse_mkf", side_effect=lambda path, data: SimpleNamespace(entries=[object()] * CHUNK_COUNT, edition=Path(path).parts[-2])), \
             mock.patch.object(inventory, "decode_entry", side_effect=lambda mkf, entry: f"payload:{mkf.edition}".encode()), \
             mock.patch.object(inventory, "parse_visual_resource", return_value=visual), \
             mock.patch.object(inventory, "write_png", side_effect=lambda path, chunk, *_args, **_kwargs: Path(path).write_bytes(b"new-png:" + chunk.pixels)), \
             mock.patch.object(inventory, "_ensure_base_link", side_effect=ensure) if ensure else mock.patch.object(inventory, "_ensure_base_link", wraps=inventory._ensure_base_link), \
             mock.patch.object(inventory, "_write_json", side_effect=write_json) if write_json else mock.patch.object(inventory, "_write_json", wraps=inventory._write_json):
            return inventory.patch_existing(zip_path, output, identity_path, base_manifest)

    @staticmethod
    def _snapshot(output: Path):
        values = {path.relative_to(output).as_posix(): path.read_bytes() for path in output.rglob("*") if path.is_file() and not path.is_symlink()}
        link = output / "images" / "base"
        return values, link.is_symlink(), os.readlink(link) if link.is_symlink() else None

    def test_patch_existing_late_second_edition_failure_keeps_all_published_bytes(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-", dir="/private/tmp") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            before = self._snapshot(fixture[0])
            with self.assertRaises(inventory.AssetError):
                self._run_mock_patch(fixture, bad_second=True)
            self.assertEqual(self._snapshot(fixture[0]), before)

    def test_patch_existing_base_link_failure_restores_original_link_and_bytes(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-", dir="/private/tmp") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output = fixture[0]
            before = self._snapshot(output)
            def fail_after_partial_link(output_path, _base):
                (output_path / "images" / "base").mkdir()
                (output_path / "images" / "base" / "partial").symlink_to("missing")
                raise OSError("injected base-link failure")
            with self.assertRaisesRegex(OSError, "injected base-link failure"):
                self._run_mock_patch(fixture, ensure=fail_after_partial_link)
            self.assertEqual(self._snapshot(output), before)

    def test_patch_existing_metadata_failure_restores_pngs_json_and_links(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-", dir="/private/tmp") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output = fixture[0]
            before = self._snapshot(output)
            real_write = inventory._write_json
            calls = 0
            def fail_on_scene(path, value):
                nonlocal calls
                calls += 1
                if calls == 2:
                    real_write(path, value)
                    raise OSError("injected metadata publication failure")
                real_write(path, value)
            with self.assertRaisesRegex(OSError, "injected metadata publication failure"):
                self._run_mock_patch(fixture, write_json=fail_on_scene)
            self.assertEqual(self._snapshot(output), before)

    def test_patch_existing_success_and_repeat_are_stable(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-", dir="/private/tmp") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            manifest = self._run_mock_patch(fixture)
            output = fixture[0]
            self.assertEqual(manifest["schema"], "richman4.inventory-assets/v1")
            for edition in EDITIONS:
                for index in (15, 16):
                    path = output / manifest["resources"][edition]["chunks"][str(index)]["path"]
                    self.assertEqual(path.read_bytes(), f"new-png:pixels:{index}".encode())
                    self.assertFalse(manifest["resources"][edition]["chunks"][str(index)]["transparent_word_zero"])
            first = self._snapshot(output)
            self._run_mock_patch(fixture)
            self.assertEqual(self._snapshot(output), first)

    def test_identity_enumerates_both_panel11_resources(self):
        identity_value = os.environ.get("PANEL11_IDENTITY")
        if not identity_value:
            self.skipTest("PANEL11_IDENTITY is not set")
        identity_path = Path(identity_value)
        if not identity_path.is_file():
            self.skipTest("PANEL11_IDENTITY is not set")
        selected = _load_identity(identity_path)
        self.assertEqual(set(selected), {(edition, RESOURCE_INDEX) for edition in EDITIONS})
        self.assertTrue(all(len(value["chunks"]) == CHUNK_COUNT for value in selected.values()))

    def test_generated_output_keeps_background_and_icon_alpha_roles(self):
        root_value = os.environ.get("INVENTORY_ASSET_ROOT")
        if not root_value:
            self.skipTest("INVENTORY_ASSET_ROOT is not set")
        root = Path(root_value)
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

    def test_generated_output_skips_without_asset_root_configuration(self):
        test_file = str(Path(__file__).resolve())
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            (temporary_path / "manifest.json").write_text("not JSON", encoding="utf-8")
            for configured_value in (None, ""):
                environment = os.environ.copy()
                if configured_value is None:
                    environment.pop("INVENTORY_ASSET_ROOT", None)
                else:
                    environment["INVENTORY_ASSET_ROOT"] = configured_value
                result = subprocess.run(
                    [
                        sys.executable,
                        test_file,
                        "InventoryAssetTests.test_generated_output_keeps_background_and_icon_alpha_roles",
                        "-v",
                    ],
                    cwd=temporary,
                    env=environment,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn("Ran 1 test", output)
                self.assertIn("OK (skipped=1)", output)
                self.assertIn("INVENTORY_ASSET_ROOT is not set", output)

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
