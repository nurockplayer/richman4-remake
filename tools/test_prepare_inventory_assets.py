#!/usr/bin/env python3
"""Focused checks for the private Panel11 preparation output."""
from __future__ import annotations

import json
import os
from pathlib import Path
from types import SimpleNamespace
import struct
import shutil
import subprocess
import sys
from unittest import mock
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr
from io import StringIO

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
    def test_main_reports_recovery_note_on_stderr(self):
        error = inventory.AssetError("injected producer failure")
        error.add_note("rollback incomplete; recovery material retained at /tmp/recovery-path")
        stderr = StringIO()
        arguments = ["prepare_inventory_assets", "--zip", "input.zip", "--output", "output", "--identity", "identity.json", "--base-manifest", "scene.json"]
        with mock.patch.object(sys, "argv", arguments), mock.patch.object(inventory, "prepare", side_effect=error), redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as caught:
                inventory.main()
        self.assertEqual(caught.exception.code, 1)
        self.assertIn("injected producer failure", stderr.getvalue())
        self.assertIn("/tmp/recovery-path", stderr.getvalue())

    def test_prepare_late_second_edition_failure_is_retryable_and_preserves_unrelated_files(self):
        with tempfile.TemporaryDirectory(prefix="fresh-prepare-late-") as temporary:
            fixture = self._prepare_fixture(Path(temporary))
            output = fixture[0].resolve()
            output.mkdir()
            (output / "keep.txt").write_bytes(b"owner data")
            before = self._snapshot(output)
            with self.assertRaises(inventory.AssetError):
                self._run_prepare(fixture, bad_second=True)
            self.assertEqual(self._snapshot(output), before)
            manifest = self._run_prepare(fixture)
            self.assertEqual(len(manifest["resources"]["Game"]["chunks"]), CHUNK_COUNT)
            self.assertEqual((output / "keep.txt").read_bytes(), b"owner data")

    def test_prepare_base_link_and_publication_failures_leave_output_unchanged(self):
        for failure in ("link", "publish"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory(prefix="fresh-prepare-fail-") as temporary:
                fixture = self._prepare_fixture(Path(temporary))
                output = fixture[0]
                output.mkdir()
                (output / "keep.txt").write_bytes(b"kept")
                before = self._snapshot(output)
                with self.assertRaises(OSError):
                    self._run_prepare(fixture, fail_link=failure == "link", fail_png=0 if failure == "publish" else None)
                self.assertEqual(self._snapshot(output), before)

    def test_prepare_refuses_existing_panel_png_without_touching_unrelated_files(self):
        with tempfile.TemporaryDirectory(prefix="fresh-prepare-collision-") as temporary:
            fixture = self._prepare_fixture(Path(temporary))
            output = fixture[0]
            collision = output / "images" / EDITIONS[0] / "ui" / "Panel" / "11" / "0.png"
            collision.parent.mkdir(parents=True)
            collision.write_bytes(b"owner png")
            (output / "other.txt").write_bytes(b"unrelated")
            before = self._snapshot(output)
            with self.assertRaisesRegex(inventory.AssetError, "output collision"):
                self._run_prepare(fixture)
            self.assertEqual(self._snapshot(output), before)

    def test_prepare_repoints_stale_base_and_preserves_unrelated_output(self):
        with tempfile.TemporaryDirectory(prefix="fresh-prepare-stale-base-") as temporary:
            fixture = self._prepare_fixture(Path(temporary))
            output, _, _, base_manifest = fixture[:4]
            output.mkdir()
            (output / "keep.txt").write_bytes(b"unrelated")
            old_base = Path(temporary) / "old-base-entry"
            old_base.mkdir()
            (old_base / "stale").write_bytes(b"stale")
            (output / "images").mkdir()
            (output / "images" / "base").symlink_to(old_base, target_is_directory=True)

            manifest = self._run_prepare(fixture)
            scene = json.loads((output / "scene-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual((output / "keep.txt").read_bytes(), b"unrelated")
            self.assertTrue((output / "images" / "base").is_dir())
            self.assertFalse((output / "images" / "base").resolve() == old_base.resolve())
            self.assertTrue((base_manifest.parent / "images" / "Game" / "map" / "base.png").is_file())
            for record in scene["maps"]:
                self.assertTrue((output / record["path"]).is_file(), record["path"])
            self.assertEqual(len(manifest["resources"]["Game"]["chunks"]), CHUNK_COUNT)

    def test_prepare_late_publication_failure_restores_entries_and_retry_succeeds(self):
        with tempfile.TemporaryDirectory(prefix="fresh-prepare-rollback-") as temporary:
            fixture = self._prepare_fixture(Path(temporary))
            output = fixture[0].resolve()
            output.mkdir()
            (output / "keep.txt").write_bytes(b"untouched")
            old_base = Path(temporary) / "old-base-entry"
            old_base.mkdir()
            (old_base / "marker").write_bytes(b"old base")
            (output / "images").mkdir()
            (output / "images" / "base").symlink_to(old_base, target_is_directory=True)
            metadata_target = Path(temporary) / "original-manifest.json"
            metadata_target.write_bytes(b"original manifest bytes")
            (output / "manifest.json").symlink_to(metadata_target)
            (output / "scene-manifest.json").write_bytes(b"old scene bytes")
            (output / "provenance.json").write_bytes(b"old provenance bytes")
            before = self._snapshot(output)
            real_replace = os.replace
            observed_live_change = False
            injected = False

            def fail_at_scene_publication(source, target):
                nonlocal observed_live_change, injected
                source = Path(source)
                target = Path(target)
                if target.name == "scene-manifest.json" and target.parent.resolve() == output and not injected:
                    injected = True
                    observed_live_change = (
                        (output / "images" / "Game" / "ui" / "Panel" / "11" / "0.png").read_bytes().startswith(b"tiny-png:")
                        and (output / "images" / "base").resolve() != old_base.resolve()
                        and (output / "manifest.json").is_file()
                        and (output / "manifest.json").read_bytes() != b"original manifest bytes"
                    )
                    raise OSError("injected late scene publication failure")
                return real_replace(source, target)

            with mock.patch.object(os, "replace", fail_at_scene_publication):
                with self.assertRaisesRegex(OSError, "late scene publication"):
                    self._run_prepare(fixture)
            self.assertTrue(observed_live_change, "failure seam must occur after live PNG/base/manifest changes")
            self.assertEqual(self._snapshot(output), before)
            self.assertTrue((output / "manifest.json").is_symlink())
            self.assertEqual(os.readlink(output / "manifest.json"), str(metadata_target))
            self.assertEqual(metadata_target.read_bytes(), b"original manifest bytes")
            manifest = self._run_prepare(fixture)
            self.assertEqual(len(manifest["resources"]["Game"]["chunks"]), CHUNK_COUNT)
            self.assertNotEqual((output / "images" / "base").resolve(), old_base.resolve())

    def test_prepare_incomplete_rollback_retains_backup_and_retry_succeeds(self):
        with tempfile.TemporaryDirectory(prefix="fresh-prepare-recovery-") as temporary:
            fixture = self._prepare_fixture(Path(temporary))
            output = fixture[0].resolve()
            output.mkdir()
            (output / "keep.txt").write_bytes(b"untouched")
            old_base = Path(temporary) / "old-base-entry"
            old_base.mkdir()
            (old_base / "marker").write_bytes(b"old base")
            (output / "images").mkdir()
            base = output / "images" / "base"
            base.symlink_to(old_base, target_is_directory=True)
            (output / "manifest.json").write_bytes(b"old manifest")
            (output / "scene-manifest.json").write_bytes(b"old scene")
            (output / "provenance.json").write_bytes(b"old provenance")
            original_manifest = (output / "manifest.json").read_bytes()
            original_scene = (output / "scene-manifest.json").read_bytes()
            real_replace = os.replace
            failed_restore = False

            def inject_failure(source, target):
                nonlocal failed_restore
                source, target = Path(source), Path(target)
                if source.name == "publication-backup-0" and target == base and not failed_restore:
                    failed_restore = True
                    raise OSError("injected base restoration failure")
                if target == output / "scene-manifest.json" and source.name == "scene-manifest.json":
                    raise OSError("injected late scene publication failure")
                return real_replace(source, target)

            with mock.patch.object(os, "replace", side_effect=inject_failure):
                with self.assertRaisesRegex(OSError, "late scene publication") as caught:
                    self._run_prepare(fixture)
            self.assertTrue(failed_restore)
            self.assertFalse(base.exists() or base.is_symlink())
            self.assertEqual((output / "manifest.json").read_bytes(), original_manifest)
            self.assertEqual((output / "scene-manifest.json").read_bytes(), original_scene)
            self.assertEqual((output / "keep.txt").read_bytes(), b"untouched")
            diagnostic = str(caught.exception) + " " + " ".join(getattr(caught.exception, "__notes__", []))
            self.assertIn("recovery material retained at", diagnostic)
            self.assertIn("publication-backup-0", diagnostic)
            recovery_text = next(note for note in getattr(caught.exception, "__notes__", []) if "recovery material retained at" in note)
            recovery = Path(recovery_text.split("recovery material retained at ", 1)[1].split(";", 1)[0])
            self.assertTrue((recovery / "publication-backup-0").is_symlink())
            (recovery / "publication-backup-0").rename(base)
            self.assertEqual(os.readlink(base), str(old_base))
            shutil.rmtree(recovery)
            result = self._run_prepare(fixture)
            self.assertEqual(len(result["resources"]["Game"]["chunks"]), CHUNK_COUNT)

    def _prepare_fixture(self, root: Path):
        output, zip_path, identity_path, base_path, identity, visual, archive, _ = self._patch_fixture(root)
        # This mode starts with an output that has unrelated content but no
        # Panel11 files, matching an accepted first-generation destination.
        shutil.rmtree(output)
        source = base_path.parent
        for edition in EDITIONS:
            for kind in ("map", "character", "ui"):
                path = source / "images" / edition / kind / "base.png"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(f"{edition}:{kind}".encode())
        base_path.write_text(json.dumps({"schema": "richman4.scene-images/v1", "maps": [{"path": f"images/{e}/map/base.png"} for e in EDITIONS], "characters": {e: {"path": f"images/{e}/character/base.png"} for e in EDITIONS}, "ui": {e: {"Panel": {"resources": {"3": {"chunks": {"0": {"path": f"images/{e}/ui/base.png"}}}}}} for e in EDITIONS}}), encoding="utf-8")
        identity_path.write_text("{}", encoding="utf-8")
        return output, zip_path, identity_path, base_path, identity, visual, archive

    @staticmethod
    def _run_prepare(fixture, *, bad_second=False, fail_png=None, fail_link=False):
        output, zip_path, identity_path, base_path, identity, visual, archive = fixture
        identity = {key: dict(value) for key, value in identity.items()}
        if bad_second:
            identity[(EDITIONS[1], RESOURCE_INDEX)]["archive_sha256"] = "wrong"
        def write(path, chunk, *_args, **_kwargs):
            if fail_png == chunk.index:
                raise OSError("injected PNG publication failure")
            Path(path).parent.mkdir(parents=True, exist_ok=True)
            Path(path).write_bytes(b"tiny-png:" + chunk.pixels)
        ensure = mock.Mock(side_effect=OSError("injected base-link failure")) if fail_link else inventory._ensure_base_link
        with mock.patch.object(inventory.zipfile, "ZipFile", archive), \
             mock.patch.object(inventory, "_load_identity", return_value=identity), \
             mock.patch.object(inventory, "parse_mkf", side_effect=lambda path, data: SimpleNamespace(entries=[object()] * CHUNK_COUNT, edition=Path(path).parts[-2])), \
             mock.patch.object(inventory, "decode_entry", side_effect=lambda mkf, entry: f"payload:{mkf.edition}".encode()), \
             mock.patch.object(inventory, "parse_visual_resource", return_value=visual), \
             mock.patch.object(inventory, "write_png", side_effect=write), \
             mock.patch.object(inventory, "_ensure_base_link", side_effect=ensure):
            return inventory.prepare(zip_path, output, identity_path, base_path)

    def _patch_fixture(self, root: Path):
        """Create only the tiny files that patch_existing owns or references."""
        output = root / "inventory"
        source = root / "source"
        output.mkdir()
        source_images = source / "images"
        for edition in EDITIONS:
            edition_map = source_images / edition / "map"
            edition_map.mkdir(parents=True)
            (edition_map / "1.png").write_bytes(f"base-map:{edition}".encode())
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
        for edition in EDITIONS:
            old_map = old_base / edition / "map"
            old_map.mkdir(parents=True)
            (old_map / "1.png").write_bytes(f"old-base-map:{edition}".encode())
        (old_base / "kept").mkdir(parents=True)
        (old_base / "kept" / "link-target").write_bytes(b"old")
        (image_root / "base").symlink_to(old_base, target_is_directory=True)

        chunks = {}
        scene_resources = {}
        expected_chunks = []
        for index in range(CHUNK_COUNT):
            expected_chunks.append({"index": index, "width": 1, "height": 1, "x": index, "y": 0, "pixel_data_sha256": inventory.hashlib.sha256(f"pixels:{index}".encode()).hexdigest()})
        resources = {}
        scene_ui = {}
        for edition in EDITIONS:
            chunks = {}
            scene_resources = {}
            for index in range(CHUNK_COUNT):
                relative = f"images/{edition}/ui/Panel/11/{index}.png"
                chunks[str(index)] = {"path": relative, "sha256": "old", "transparent_word_zero": index in TRANSPARENT_CHUNKS}
                scene_resources[str(index)] = {"path": relative, "sha256": "old", "transparent_word_zero": index in TRANSPARENT_CHUNKS}
            resources[edition] = {"source": {"edition": edition}, "chunks": chunks}
            scene_ui[edition] = {"Panel": {"resources": {"11": {"chunks": scene_resources}}}}
        scene = {"schema": "richman4.scene-images/v1", "maps": [{"path": f"images/{edition}/map/1.png"} for edition in EDITIONS], "characters": {}, "ui": scene_ui}
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
        with tempfile.TemporaryDirectory(prefix="asset-transaction-") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            before = self._snapshot(fixture[0])
            with self.assertRaises(inventory.AssetError):
                self._run_mock_patch(fixture, bad_second=True)
            self.assertEqual(self._snapshot(fixture[0]), before)

    def test_patch_preflight_rejects_redirected_panel_parent_before_any_publication_and_retries(self):
        with tempfile.TemporaryDirectory(prefix="asset-destination-preflight-") as temporary:
            root = Path(temporary)
            fixture = self._patch_fixture(root)
            output = fixture[0]
            canonical = output / "images" / "Game" / "ui" / "Panel" / "11"
            external = root / "outside-panel"
            external.mkdir()
            for index in range(CHUNK_COUNT):
                (external / f"{index}.png").write_bytes(f"outside:{index}".encode())
            shutil.rmtree(canonical)
            canonical.symlink_to(external, target_is_directory=True)
            old_base = os.readlink(output / "images" / "base")
            manifest_before = (output / "manifest.json").read_bytes()
            scene_before = (output / "scene-manifest.json").read_bytes()
            external_before = {path.name: (path.read_bytes(), path.is_symlink()) for path in external.iterdir()}
            with self.assertRaises(inventory.AssetError):
                self._run_mock_patch(fixture)
            self.assertEqual({path.name: (path.read_bytes(), path.is_symlink()) for path in external.iterdir()}, external_before)
            self.assertEqual((output / "manifest.json").read_bytes(), manifest_before)
            self.assertEqual((output / "scene-manifest.json").read_bytes(), scene_before)
            self.assertEqual(os.readlink(output / "images" / "base"), old_base)
            canonical.unlink()
            canonical.mkdir()
            for index in range(CHUNK_COUNT):
                (canonical / f"{index}.png").write_bytes(f"original:Game:{index}".encode())
            manifest = self._run_mock_patch(fixture)
            self.assertEqual((canonical / "15.png").read_bytes(), b"new-png:pixels:15")
            self.assertEqual(manifest["resources"]["Game"]["chunks"]["15"]["path"], "images/Game/ui/Panel/11/15.png")

    def test_patch_preflight_rejects_noncanonical_paths_without_mutation_and_retries(self):
        for traversal in ("../outside.png",):
            with self.subTest(destination=traversal), tempfile.TemporaryDirectory(prefix="asset-destination-path-") as temporary:
                root = Path(temporary)
                fixture = self._patch_fixture(root)
                output = fixture[0]
                outside = root / "outside.png"
                outside.write_bytes(b"outside sentinel")
                for destination in (traversal, str(outside.resolve())):
                    with self.subTest(destination=destination):
                        original_manifest = json.loads((output / "manifest.json").read_text())
                        original_manifest["resources"]["Game"]["chunks"]["15"]["path"] = destination
                        manifest_path = output / "manifest.json"
                        manifest_path.write_text(json.dumps(original_manifest))
                        manifest_before = manifest_path.read_bytes()
                        scene_before = (output / "scene-manifest.json").read_bytes()
                        base_entry = output / "images" / "base"
                        old_base = os.readlink(base_entry) if base_entry.is_symlink() else None
                        with self.assertRaises(inventory.AssetError):
                            self._run_mock_patch(fixture)
                        self.assertEqual(outside.read_bytes(), b"outside sentinel")
                        self.assertEqual(manifest_path.read_bytes(), manifest_before)
                        self.assertEqual((output / "scene-manifest.json").read_bytes(), scene_before)
                        self.assertEqual(os.readlink(base_entry) if base_entry.is_symlink() else None, old_base)
                        original_manifest["resources"]["Game"]["chunks"]["15"]["path"] = "images/Game/ui/Panel/11/15.png"
                        manifest_path.write_text(json.dumps(original_manifest))
                        self._run_mock_patch(fixture)

    def test_patch_preflight_requires_scene_and_inventory_to_name_same_canonical_png(self):
        with tempfile.TemporaryDirectory(prefix="asset-destination-record-") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output = fixture[0]
            scene_path = output / "scene-manifest.json"
            scene = json.loads(scene_path.read_text())
            scene["ui"]["Game"]["Panel"]["resources"]["11"]["chunks"]["15"]["path"] = "images/Game/ui/Panel/11/16.png"
            scene_path.write_text(json.dumps(scene))
            before = self._snapshot(output)
            with self.assertRaises(inventory.AssetError):
                self._run_mock_patch(fixture)
            self.assertEqual(self._snapshot(output), before)
            scene["ui"]["Game"]["Panel"]["resources"]["11"]["chunks"]["15"]["path"] = "images/Game/ui/Panel/11/15.png"
            scene_path.write_text(json.dumps(scene))
            manifest = self._run_mock_patch(fixture)
            scene_after = json.loads(scene_path.read_text())
            record = scene_after["ui"]["Game"]["Panel"]["resources"]["11"]["chunks"]["15"]
            self.assertEqual(record["path"], "images/Game/ui/Panel/11/15.png")
            self.assertEqual(record["sha256"], inventory._sha256(output / record["path"]))
            self.assertEqual(manifest["resources"]["Game"]["chunks"]["15"]["sha256"], record["sha256"])

    def test_prepare_preflight_rejects_images_parent_symlink_before_publication_and_retries(self):
        with tempfile.TemporaryDirectory(prefix="fresh-destination-preflight-") as temporary:
            root = Path(temporary)
            fixture = self._prepare_fixture(root)
            output = fixture[0]
            output.mkdir()
            outside = root / "outside-images"
            outside.mkdir()
            sentinel = outside / "sentinel"
            sentinel.write_bytes(b"outside data")
            (output / "images").symlink_to(outside, target_is_directory=True)
            before_link = os.readlink(output / "images")
            with self.assertRaises(inventory.AssetError):
                self._run_prepare(fixture)
            self.assertEqual(sentinel.read_bytes(), b"outside data")
            self.assertEqual(os.readlink(output / "images"), before_link)
            self.assertEqual(list(outside.iterdir()), [sentinel])
            (output / "images").unlink()
            manifest = self._run_prepare(fixture)
            self.assertEqual(len(manifest["resources"]["Game"]["chunks"]), CHUNK_COUNT)

    def test_patch_existing_base_link_failure_restores_original_link_and_bytes(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-") as temporary:
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

    def test_patch_existing_missing_authoritative_base_path_rolls_back_links_and_bytes(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output, _, _, base_manifest = fixture[:4]
            before = self._snapshot(output)
            authoritative_path = base_manifest.parent / "images" / "MultiverseJourney" / "map" / "1.png"
            authoritative_path.unlink()
            self.assertEqual((output / "images" / "base" / "MultiverseJourney" / "map" / "1.png").read_bytes(), b"old-base-map:MultiverseJourney")
            with self.assertRaisesRegex(inventory.AssetError, "unresolved image paths"):
                self._run_mock_patch(fixture)
            self.assertEqual(self._snapshot(output), before)
            self.assertTrue((output / "images" / "base" / "MultiverseJourney" / "map" / "1.png").is_file())

    def test_patch_existing_readonly_png_is_not_rewritten_when_base_validation_fails(self):
        with tempfile.TemporaryDirectory(prefix="asset-readonly-rollback-") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output, _, _, base_manifest = fixture[:4]
            target = output / "images" / "Game" / "ui" / "Panel" / "11" / "15.png"
            target.chmod(0o444)
            original = (target.lstat().st_mode, target.read_bytes())
            base_link = output / "images" / "base"
            original_link = os.readlink(base_link)
            original_map = base_link / "MultiverseJourney" / "map" / "1.png"
            original_map_resolution = original_map.resolve()
            original_map_bytes = original_map.read_bytes()
            missing = base_manifest.parent / "images" / "MultiverseJourney" / "map" / "1.png"
            missing.unlink()
            direct_writes = []
            real_write_bytes = Path.write_bytes

            def observe_write(path, data):
                if path == target:
                    direct_writes.append(path)
                return real_write_bytes(path, data)

            with mock.patch.object(Path, "write_bytes", observe_write):
                with self.assertRaisesRegex(inventory.AssetError, "unresolved image paths"):
                    self._run_mock_patch(fixture)
            self.assertEqual(direct_writes, [], "rollback must not write an untouched read-only PNG")
            self.assertTrue(target.is_file())
            self.assertFalse(target.is_symlink())
            self.assertEqual((target.lstat().st_mode, target.read_bytes()), original)
            self.assertTrue(base_link.is_symlink())
            self.assertEqual(os.readlink(base_link), original_link)
            self.assertEqual(original_map.resolve(), original_map_resolution)
            self.assertEqual(original_map.read_bytes(), original_map_bytes)

            # A complete authoritative base still permits rename-based replacement
            # of the same read-only entry, followed by a successful retry.
            missing.write_bytes(b"restored authoritative map")
            self._run_mock_patch(fixture)
            self.assertEqual(target.read_bytes(), b"new-png:pixels:15")
            self.assertEqual(target.stat().st_mode & 0o777, 0o644)

    def test_patch_existing_late_failure_restores_metadata_symlink_entry_and_retries(self):
        with tempfile.TemporaryDirectory(prefix="asset-symlink-rollback-") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output = fixture[0]
            manifest = output / "manifest.json"
            backing = Path(temporary) / "backing-manifest.json"
            backing.write_bytes(manifest.read_bytes())
            backing_before = backing.read_bytes()
            manifest.unlink()
            manifest.symlink_to(backing)
            before = self._snapshot(output)
            target = output / "images" / "Game" / "ui" / "Panel" / "11" / "15.png"
            observed_changed_png = False
            real_replace = os.replace
            injected = False

            def fail_after_png(source, destination):
                nonlocal injected, observed_changed_png
                source, destination = Path(source), Path(destination)
                if destination == (output / "scene-manifest.json").resolve() and not injected:
                    injected = True
                    observed_changed_png = target.read_bytes() == b"new-png:pixels:15"
                    raise OSError("injected late metadata publication failure")
                return real_replace(source, destination)

            with mock.patch.object(os, "replace", fail_after_png), self.assertRaisesRegex(OSError, "late metadata publication"):
                self._run_mock_patch(fixture)
            self.assertTrue(observed_changed_png, "failure must follow a published PNG change")
            self.assertEqual(self._snapshot(output), before)
            self.assertTrue(manifest.is_symlink())
            self.assertEqual(os.readlink(manifest), str(backing))
            self.assertEqual(backing.read_bytes(), backing_before)
            self._run_mock_patch(fixture)
            self.assertFalse(manifest.is_symlink(), "successful publication replaces the symlink entry")
            self.assertEqual(target.read_bytes(), b"new-png:pixels:15")

    def test_patch_existing_incomplete_rollback_keeps_recovery_backup_and_other_restores(self):
        with tempfile.TemporaryDirectory(prefix="asset-recovery-material-") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output = fixture[0]
            base = output / "images" / "base"
            original_files = self._snapshot(output)[0]
            original_base_target = os.readlink(base)
            original_png = (output / "images" / "Game" / "ui" / "Panel" / "11" / "15.png").read_bytes()
            original_manifest = (output / "manifest.json").read_bytes()
            real_replace = os.replace
            failed_restore = False

            def fail_base_restore(source, target):
                nonlocal failed_restore
                source, target = Path(source), Path(target)
                if (source.name == "base-link-backup" and target == output.resolve() / "images" / "base" and not failed_restore):
                    failed_restore = True
                    raise OSError("injected base restoration failure")
                return real_replace(source, target)

            def inject_failures(source, target):
                source, target = Path(source), Path(target)
                if source.name == "base-link-backup" and target == output.resolve() / "images" / "base":
                    return fail_base_restore(source, target)
                if source.name == "metadata-1.json" and target == (output / "scene-manifest.json").resolve():
                    raise OSError("injected late metadata publication failure")
                return real_replace(source, target)

            with mock.patch.object(os, "replace", side_effect=inject_failures), self.assertRaisesRegex(OSError, "late metadata publication") as caught:
                self._run_mock_patch(fixture)
            self.assertTrue(failed_restore)
            self.assertEqual((output / "images" / "Game" / "ui" / "Panel" / "11" / "15.png").read_bytes(), original_png)
            self.assertEqual((output / "manifest.json").read_bytes(), original_manifest)
            live_files = {path: data for path, data in self._snapshot(output)[0].items() if not path.startswith(".inventory-patch-")}
            self.assertEqual(live_files, original_files)
            self.assertFalse(base.exists() or base.is_symlink())
            diagnostic = str(caught.exception) + " " + " ".join(getattr(caught.exception, "__notes__", []))
            self.assertIn("recovery", diagnostic.lower())
            recovery_paths = list(output.glob(".inventory-patch-*"))
            self.assertEqual(len(recovery_paths), 1, "incomplete rollback must preserve backup material")
            recovery = recovery_paths[0]
            self.assertTrue(any(recovery.rglob("base-link-backup")))

            # Manual recovery remains possible, and a corrected retry succeeds.
            (recovery / "base-link-backup").rename(base)
            self.assertEqual(os.readlink(base), original_base_target)
            shutil.rmtree(recovery)
            self._run_mock_patch(fixture)
            self.assertTrue((base / "Game" / "map" / "1.png").is_file())

    def test_patch_existing_metadata_failure_restores_pngs_json_and_links(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-") as temporary:
            fixture = self._patch_fixture(Path(temporary))
            output = fixture[0]
            before = self._snapshot(output)
            target = output / "images" / "Game" / "ui" / "Panel" / "11" / "15.png"
            real_replace = os.replace
            observed_png = False
            injected = False

            def fail_on_scene(source, destination):
                nonlocal observed_png, injected
                source, destination = Path(source), Path(destination)
                if destination == (output / "scene-manifest.json").resolve() and not injected:
                    injected = True
                    observed_png = target.read_bytes() == b"new-png:pixels:15"
                    raise OSError("injected metadata publication failure")
                return real_replace(source, destination)

            with mock.patch.object(os, "replace", fail_on_scene), self.assertRaisesRegex(OSError, "injected metadata publication failure"):
                self._run_mock_patch(fixture)
            self.assertTrue(observed_png)
            self.assertEqual(self._snapshot(output), before)

    def test_patch_existing_success_and_repeat_are_stable(self):
        with tempfile.TemporaryDirectory(prefix="asset-transaction-") as temporary:
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
