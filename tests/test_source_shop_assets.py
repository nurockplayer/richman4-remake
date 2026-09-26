#!/usr/bin/env python3
"""Focused checks for the private S20 Panel10 preparation output."""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
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
    _verify_scene_paths,
    AssetError,
)
from test_decode_original_images import make_mkf  # noqa: E402
from test_package_scene_images import png_record, write_scene_manifest  # noqa: E402
from package_scene_images import validate as validate_scene_manifest  # noqa: E402


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
    def test_real_s19_to_s20_cli_and_guarded_package_regression(self):
        temporary = tempfile.TemporaryDirectory(prefix="source-shop-real-cli-", dir="/private/tmp")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        tools = Path(__file__).resolve().parents[1] / "tools"
        inventory_cli = tools / "prepare_inventory_assets.py"
        shop_cli = tools / "prepare_source_shop.py"
        package_cli = tools / "package_scene_images.py"
        editions = ("Game", "MultiverseJourney")

        def visual_resource(count):
            pixels = struct.pack("<3H", 0, 0x8000, 0x03e0)
            start = 12 + count * 12
            payload = b"SMP\0" + struct.pack("<II", count, start)
            payload += b"".join(struct.pack("<hhhhI", 3, 1, -2, 5, len(pixels)) for _ in range(count))
            payload += pixels * count
            return payload, pixels, start

        def owner_zip(path, resource_index, count):
            payload, pixels, image_start = visual_resource(count)
            hashes = {}
            with zipfile.ZipFile(path, "w") as archive:
                for edition in editions:
                    mkf = make_mkf([(b"plain", 5, 0, 0)] * resource_index + [
                        (payload, len(payload), image_start, len(pixels) * count)
                    ])
                    member = f"dfw4cskzl_136622/{edition}/Panel.mkf"
                    archive.writestr(member, mkf)
                    hashes[edition] = {
                        "archive": hashlib.sha256(mkf).hexdigest(),
                        "payload": hashlib.sha256(payload).hexdigest(),
                    }
            return hashes, hashlib.sha256(pixels).hexdigest()

        def identity(path, schema, resource_index, count, archive_hashes, pixels_hash):
            records = []
            for edition in editions:
                records.append({
                    "edition": edition,
                    "physical_index": resource_index,
                    "archive_sha256": archive_hashes[edition]["archive"],
                    "payload_sha256": archive_hashes[edition]["payload"],
                    "chunks": [
                        {"index": index, "width": 3, "height": 1, "x": -2, "y": 5,
                         "pixel_data_sha256": pixels_hash}
                        for index in range(count)
                    ],
                })
            document = {"records": records}
            if schema:
                document["schema"] = schema
            path.write_text(json.dumps(document), encoding="utf-8")

        base_root = root / "base-source"
        base_png = base_root / "images" / "base-map.png"
        base_record = png_record(base_png, "images/base-map.png")
        base_manifest = write_scene_manifest(base_root, [base_record], filename="resolved-s19-base.json")

        s19_zip = root / "s19-owner.zip"
        s19_hashes, s19_pixels_hash = owner_zip(s19_zip, 11, 17)
        s19_identity = root / "s19-identity.json"
        identity(s19_identity, None, 11, 17, s19_hashes, s19_pixels_hash)
        s19_output = root / "s19-output"
        s19_command = [sys.executable, str(inventory_cli), "--zip", str(s19_zip),
                       "--output", str(s19_output), "--identity", str(s19_identity),
                       "--base-manifest", str(base_manifest)]
        s19 = subprocess.run(s19_command, capture_output=True, text=True, timeout=120, check=False)
        self.assertEqual(s19.returncode, 0, f"S19 CLI stdout:\n{s19.stdout}\nS19 CLI stderr:\n{s19.stderr}")
        s19_scene = s19_output / "scene-manifest.json"
        self.assertTrue(s19_scene.is_file(), f"S19 output absent; stdout:\n{s19.stdout}\nstderr:\n{s19.stderr}")
        s19_value = json.loads(s19_output.joinpath("manifest.json").read_text(encoding="utf-8"))
        self.assertEqual({edition: len(s19_value["resources"][edition]["chunks"]) for edition in editions},
                         {edition: 17 for edition in editions})
        self.assertTrue(all((s19_output / s19_value["resources"][edition]["chunks"]["0"]["path"]).is_file()
                            for edition in editions), "S19 CLI output omitted declared decoded PNGs")
        validate_scene_manifest(s19_scene, base_manifest=base_manifest)
        s19_package = subprocess.run(
            [sys.executable, str(package_cli), str(s19_scene), "--base-manifest", str(base_manifest)],
            capture_output=True, text=True, timeout=120, check=False,
        )
        self.assertEqual(s19_package.returncode, 0,
                         f"S19 guarded package stdout:\n{s19_package.stdout}\nS19 guarded package stderr:\n{s19_package.stderr}")

        s20_zip = root / "s20-owner.zip"
        s20_hashes, s20_pixels_hash = owner_zip(s20_zip, 10, 38)
        s20_identity = root / "s20-identity.json"
        identity(s20_identity, "richman4.source-shop-panel10-identity/v1", 10, 38,
                 s20_hashes, s20_pixels_hash)
        s20_output = root / "s20-output"
        s20_command = [sys.executable, str(shop_cli), "--zip", str(s20_zip),
                       "--output", str(s20_output), "--identity", str(s20_identity),
                       "--base-manifest", str(s19_scene)]
        s20 = subprocess.run(s20_command, capture_output=True, text=True, timeout=120, check=False)
        self.assertEqual(s20.returncode, 0,
                         f"S20 CLI stdout:\n{s20.stdout}\nS20 CLI stderr:\n{s20.stderr}")
        s20_scene = s20_output / "scene-manifest.json"
        self.assertTrue(s20_scene.is_file(), f"S20 output absent; stdout:\n{s20.stdout}\nstderr:\n{s20.stderr}")
        s20_value = json.loads(s20_output.joinpath("manifest.json").read_text(encoding="utf-8"))
        self.assertTrue(all((s19_output / s19_value["resources"][edition]["chunks"]["0"]["path"]).is_file()
                            for edition in editions), "S20 CLI modified the S19 Panel11 source tree")
        self.assertEqual({edition: len(s20_value["resources"][edition]["chunks"]) for edition in editions},
                         {edition: 16 for edition in editions})
        validate_scene_manifest(s20_scene, base_manifest=s19_scene)
        package = subprocess.run(
            [sys.executable, str(package_cli), str(s20_scene), "--base-manifest", str(s19_scene)],
            capture_output=True, text=True, timeout=120, check=False,
        )
        self.assertEqual(package.returncode, 0,
                         f"S20 guarded package stdout:\n{package.stdout}\nS20 guarded package stderr:\n{package.stderr}")

    def test_missing_inherited_scene_image_refuses_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(AssetError, "unresolved image paths: images/base/Game/map/1.png"):
                _verify_scene_paths(
                    {"maps": [{"path": "images/base/Game/map/1.png"}]},
                    Path(temporary),
                )

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


    def _inputs(self, root: Path) -> tuple[Path, Path, Path]:
        zip_path = root / "owner.zip"
        identity = root / "identity.json"
        base = root / "base.json"
        zip_path.write_bytes(b"source")
        identity.write_text("{}", encoding="utf-8")
        base.write_text(json.dumps({"schema": "richman4.scene-images/v1", "maps": [], "characters": {}, "ui": {}}), encoding="utf-8")
        return zip_path, identity, base

    def test_staging_failure_preserves_existing_output(self):
        from unittest.mock import patch
        import prepare_source_shop as producer

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            zip_path, identity, base = self._inputs(root)
            output = root / "output"
            output.mkdir()
            old_manifest = output / "manifest.json"
            old_manifest.write_text("prior result", encoding="utf-8")

            def fail_after_staging(_zip, staged, _identity, _base):
                (staged / "partial.png").write_bytes(b"partial")
                raise producer.AssetError("synthetic decode fault")

            with patch.object(producer, "_prepare_into", side_effect=fail_after_staging):
                with self.assertRaisesRegex(producer.AssetError, "synthetic decode fault"):
                    producer.prepare(zip_path, output, identity, base)
            self.assertEqual(old_manifest.read_text(encoding="utf-8"), "prior result")
            self.assertEqual(sorted(path.name for path in output.iterdir()), ["manifest.json"])

    def test_redirected_output_parent_is_refused_before_staging(self):
        from unittest.mock import patch
        import prepare_source_shop as producer

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            zip_path, identity, base = self._inputs(root)
            target = root / "target"
            target.mkdir()
            redirected = root / "redirected"
            redirected.symlink_to(target, target_is_directory=True)
            with patch.object(producer, "_prepare_into") as prepare_into:
                with self.assertRaisesRegex(producer.AssetError, "redirected parent"):
                    producer.prepare(zip_path, redirected / "output", identity, base)
                prepare_into.assert_not_called()

    def test_input_output_identity_collision_is_refused(self):
        from unittest.mock import patch
        import prepare_source_shop as producer

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            zip_path, identity, base = self._inputs(root)
            with patch.object(producer, "_prepare_into") as prepare_into:
                with self.assertRaisesRegex(producer.AssetError, "aliases a source input"):
                    producer.prepare(zip_path, zip_path, identity, base)
                prepare_into.assert_not_called()

    def test_partial_publication_fault_rolls_back_prior_outputs(self):
        from unittest.mock import patch
        import prepare_source_shop as producer

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            zip_path, identity, base_manifest = self._inputs(root)
            base_images = root / "images" / "base"
            base_images.mkdir(parents=True)
            (base_images / "inherited.png").write_bytes(b"inherited")
            base_manifest.write_text(json.dumps({
                "schema": "richman4.scene-images/v1", "maps": [], "characters": {}, "ui": {},
                "image": "images/base/inherited.png",
            }), encoding="utf-8")
            output = root / "output"
            (output / "images" / "base").mkdir(parents=True)
            (output / "images" / "base" / "prior.png").write_bytes(b"prior-base")
            old = {name: f"prior-{name}" for name in ("manifest.json", "scene-manifest.json", "provenance.json")}
            for name, value in old.items():
                (output / name).write_text(value, encoding="utf-8")

            def synthetic_prepare(_zip, staged, _identity, _base):
                relative = "images/Game/ui/Panel/10/0.png"
                target = staged / relative
                target.parent.mkdir(parents=True)
                target.write_bytes(b"new-panel")
                inherited = staged / "images" / "base" / "inherited.png"
                inherited.parent.mkdir(parents=True, exist_ok=True)
                inherited.write_bytes(b"inherited")
                scene = {"schema": "richman4.scene-images/v1", "maps": [], "characters": {}, "ui": {}, "image": "images/base/inherited.png"}
                (staged / "manifest.json").write_text("new manifest", encoding="utf-8")
                (staged / "scene-manifest.json").write_text(json.dumps(scene), encoding="utf-8")
                (staged / "provenance.json").write_text("new provenance", encoding="utf-8")
                return {"resources": {"Game": {"chunks": {"0": {"path": relative}}}}}

            real_replace = producer.os.replace
            calls = 0
            def fail_during_publish(source, destination):
                nonlocal calls
                calls += 1
                if calls == 6:
                    raise OSError("synthetic publication fault")
                return real_replace(source, destination)

            with patch.object(producer, "_prepare_into", side_effect=synthetic_prepare), patch.object(producer.os, "replace", side_effect=fail_during_publish):
                with self.assertRaisesRegex(OSError, "synthetic publication fault"):
                    producer.prepare(zip_path, output, identity, base_manifest)
            for name, value in old.items():
                self.assertEqual((output / name).read_text(encoding="utf-8"), value)
            self.assertEqual((output / "images" / "base" / "prior.png").read_bytes(), b"prior-base")
            self.assertFalse((output / "images" / "Game" / "ui" / "Panel" / "10" / "0.png").exists())

    def test_public_prepare_publishes_inherited_overlay_files_and_rolls_back_late_fault(self):
        from unittest.mock import patch
        import prepare_source_shop as producer

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            zip_path, identity, base_manifest = self._inputs(root)
            source_images = root / "images"
            (source_images / "base").mkdir(parents=True)
            (source_images / "base" / "map.png").write_bytes(b"base-image")
            inherited = {}
            for edition in EDITIONS:
                source = source_images / edition / "ui" / "Panel" / "11" / "0.png"
                source.parent.mkdir(parents=True)
                source.write_bytes((edition + "-panel11").encode())
                inherited[edition] = source
            scene = {
                "schema": "richman4.scene-images/v1", "maps": [], "characters": {}, "ui": {},
                "base": "images/base/map.png",
                "held": [f"images/{edition}/ui/Panel/11/0.png" for edition in EDITIONS],
            }
            base_manifest.write_text(json.dumps(scene), encoding="utf-8")

            def stage(_zip, staged, _identity, _base):
                chunks = {}
                for edition in EDITIONS:
                    relative = f"images/{edition}/ui/Panel/10/0.png"
                    target = staged / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes((edition + "-panel10").encode())
                    chunks[edition] = {"path": relative, "chunks": {"0": {"path": relative}}}
                (staged / "images" / "base").symlink_to(source_images / "base", target_is_directory=True)
                for edition, source in inherited.items():
                    target = staged / "images" / edition / "ui" / "Panel" / "11" / "0.png"
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.symlink_to(source)
                staged_scene = dict(scene)
                staged_scene["shop"] = [value["path"] for value in chunks.values()]
                manifest = {"resources": {edition: {"chunks": {"0": {"path": value["path"]}}} for edition, value in chunks.items()}}
                for name, value in (("scene-manifest.json", staged_scene), ("manifest.json", manifest), ("provenance.json", {"preserved": True})):
                    (staged / name).write_text(json.dumps(value), encoding="utf-8")
                return manifest

            output = root / "fresh-output"
            original_replace = producer.os.replace
            fault_seen_links = False
            def fail_after_inherited_publication(source, destination):
                nonlocal fault_seen_links
                if Path(source).name == "scene-manifest.json":
                    fault_seen_links = all((output / f"images/{edition}/ui/Panel/11/0.png").is_file() and not (output / f"images/{edition}/ui/Panel/11/0.png").is_symlink() for edition in EDITIONS)
                    raise OSError("synthetic late metadata fault")
                return original_replace(source, destination)

            with patch.object(producer, "_prepare_into", side_effect=stage), patch.object(producer.os, "replace", side_effect=fail_after_inherited_publication):
                with self.assertRaisesRegex(OSError, "synthetic late metadata fault"):
                    producer.prepare(zip_path, output, identity, base_manifest)
            self.assertTrue(fault_seen_links)
            self.assertFalse(output.exists() and any(output.rglob("*.png")))
            self.assertEqual({edition: inherited[edition].read_bytes() for edition in EDITIONS}, {
                edition: (edition + "-panel11").encode() for edition in EDITIONS
            })

            # A retry may encounter a compatible old link. Replace the link
            # entry with owned bytes without writing through to its target.
            for edition, source in inherited.items():
                target = output / f"images/{edition}/ui/Panel/11/0.png"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(source)
            with patch.object(producer, "_prepare_into", side_effect=stage):
                result = producer.prepare(zip_path, output, identity, base_manifest)
            resolved_scene = json.loads((output / "scene-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(resolved_scene["held"], scene["held"])
            self.assertEqual(result["resources"].keys(), set(EDITIONS))
            for edition, source in inherited.items():
                published = output / f"images/{edition}/ui/Panel/11/0.png"
                self.assertTrue(published.is_file())
                self.assertFalse(published.is_symlink())
                self.assertEqual(published.read_bytes(), source.read_bytes())
                self.assertEqual(source.read_bytes(), (edition + "-panel11").encode())


if __name__ == "__main__":
    unittest.main()
