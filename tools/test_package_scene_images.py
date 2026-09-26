"""Private packaging must not copy unrelated files or corrupt scene images."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from decode_original_images import VisualChunk, VisualResource, write_png
from original_ui_assets import export_ui_resources
from test_decode_original_images import make_mkf, make_smp, read_png_rgba
import package_scene_images
from package_scene_images import validate


def write_scene_manifest(root, records, filename="manifest.json"):
    root.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": "richman4.scene-images/v1", "characters": {},
                "maps": [{"world_rect": {"x": 0, "y": 0, "width": 3, "height": 1},
                          "image": records[0]}],
                "ui": {"records": records[1:]}}
    path = root / filename
    path.write_text(json.dumps(manifest))
    return path


def png_record(path, relative):
    chunk = VisualChunk(0, 3, 1, 0, 0, bytes(12))
    write_png(path, chunk, VisualResource("SPR", 1, 0, bytes(512), (chunk,)), pixel_format="rgb555")
    return {"path": relative, "width": 3, "height": 1,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


class PackageSceneTests(unittest.TestCase):
    def test_explicit_base_manifest_authorizes_exact_direct_and_nested_records(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            base = root / "base"
            direct = png_record(base / "images" / "direct.png", "images/direct.png")
            nested = png_record(base / "images" / "base" / "nested.png", "images/base/nested.png")
            base_manifest = write_scene_manifest(base, [direct, nested])
            overlay = root / "overlay"
            (overlay / "images").mkdir(parents=True)
            (overlay / "images" / "base").mkdir()
            (overlay / "images" / "base" / "direct.png").symlink_to(base / "images" / "direct.png")
            (overlay / "images" / "base" / "nested.png").symlink_to(base / "images" / "base" / "nested.png")
            own = png_record(overlay / "images" / "Panel11.png", "images/Panel11.png")
            inherited_direct = dict(direct, path="images/base/direct.png")
            inherited_nested = dict(nested)
            manifest = write_scene_manifest(overlay, [own, inherited_direct, inherited_nested])

            self.assertEqual(validate(manifest, base_manifest=base_manifest)[1], sorted(map(Path, [
                "images/Panel11.png", "images/base/direct.png", "images/base/nested.png"])))
            with self.assertRaisesRegex(ValueError, "escapes|symlink|base"):
                validate(manifest)

    def test_explicit_base_rejects_wrong_base_retarget_unlisted_and_collision(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def base_tree(name, relative="images/shared.png"):
                base = root / name
                record = png_record(base / relative, relative)
                return base, record, write_scene_manifest(base, [record])
            base, record, base_manifest = base_tree("base")
            other, _, other_manifest = base_tree("other")
            overlay = root / "overlay"
            (overlay / "images").mkdir(parents=True)
            (overlay / "images" / "base").symlink_to(base / "images", target_is_directory=True)
            own = png_record(overlay / "images" / "Panel11.png", "images/Panel11.png")
            inherited = dict(record, path="images/base/shared.png")
            manifest = write_scene_manifest(overlay, [own, inherited])
            with self.assertRaisesRegex(ValueError, "base|inherit|record"):
                validate(manifest, base_manifest=other_manifest)

            (overlay / "images" / "base").unlink()
            (overlay / "images" / "base").symlink_to(other / "images", target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "base|inherit|record"):
                validate(manifest, base_manifest=base_manifest)

            (overlay / "images" / "base").unlink()
            (overlay / "images" / "base").symlink_to(base / "images", target_is_directory=True)
            unlisted = dict(record, path="images/base/unlisted.png")
            manifest = write_scene_manifest(overlay, [own, unlisted])
            (base / "images" / "unlisted.png").write_bytes((base / "images" / "shared.png").read_bytes())
            with self.assertRaisesRegex(ValueError, "base|inherit|record"):
                validate(manifest, base_manifest=base_manifest)

            # A transformed inherited path cannot alias a newly produced Panel11 file.
            (overlay / "images" / "base").unlink()
            (overlay / "images" / "base").mkdir()
            collision = png_record(overlay / "images" / "base" / "shared.png", "images/base/shared.png")
            manifest = write_scene_manifest(overlay, [own, collision])
            with self.assertRaisesRegex(ValueError, "collision|ambiguous|duplicate"):
                validate(manifest, base_manifest=base_manifest)

    def test_cli_base_manifest_copies_only_referenced_and_destination_is_strict(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            base = root / "base"
            inherited = png_record(base / "images" / "old.png", "images/old.png")
            base_manifest = write_scene_manifest(base, [inherited])
            overlay = root / "overlay"
            (overlay / "images").mkdir(parents=True)
            (overlay / "images" / "base").symlink_to(base / "images", target_is_directory=True)
            own = png_record(overlay / "images" / "Panel11.png", "images/Panel11.png")
            manifest = write_scene_manifest(overlay, [own, dict(inherited, path="images/base/old.png")])
            (overlay / "images" / "unrelated.png").write_bytes(b"not copied")
            destination = root / "package"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("package_scene_images.py")),
                                     str(manifest), "--base-manifest", str(base_manifest),
                                     "--destination", str(destination)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(validate(destination / "manifest.json")[1], sorted(map(Path, [
                "images/Panel11.png", "images/base/old.png"])))
            self.assertFalse((destination / "images" / "unrelated.png").exists())

    def test_cli_symlink_manifest_uses_canonical_manifest_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            base = root / "base"
            inherited = png_record(base / "images" / "old.png", "images/old.png")
            base_manifest = write_scene_manifest(base, [inherited])
            canonical = root / "overlay"
            (canonical / "images").mkdir(parents=True)
            (canonical / "images" / "base").symlink_to(base / "images", target_is_directory=True)
            own = png_record(canonical / "images" / "Panel11.png", "images/Panel11.png")
            manifest = write_scene_manifest(canonical, [own, dict(inherited, path="images/base/old.png")])
            link_dir = root / "manifest-link"
            link_dir.mkdir()
            linked_manifest = link_dir / "scene.json"
            linked_manifest.symlink_to(manifest)
            destination = root / "package"

            result = subprocess.run([sys.executable, str(Path(__file__).with_name("package_scene_images.py")),
                                     str(linked_manifest), "--base-manifest", str(base_manifest),
                                     "--destination", str(destination)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(validate(destination / "manifest.json")[1], sorted(map(Path, [
                "images/Panel11.png", "images/base/old.png"])))

    def test_cli_symlink_manifest_does_not_copy_identical_byte_sibling_shadows(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            base = root / "base"
            inherited = png_record(base / "images" / "old.png", "images/old.png")
            base_manifest = write_scene_manifest(base, [inherited])
            canonical = root / "overlay"
            (canonical / "images").mkdir(parents=True)
            (canonical / "images" / "base").symlink_to(base / "images", target_is_directory=True)
            own = png_record(canonical / "images" / "Panel11.png", "images/Panel11.png")
            manifest = write_scene_manifest(canonical, [own, dict(inherited, path="images/base/old.png")])
            link_dir = root / "manifest-link"
            (link_dir / "images" / "base").mkdir(parents=True)
            (link_dir / "images" / "Panel11.png").write_bytes((canonical / "images" / "Panel11.png").read_bytes())
            (link_dir / "images" / "base" / "old.png").write_bytes((base / "images" / "old.png").read_bytes())
            linked_manifest = link_dir / "scene.json"
            linked_manifest.symlink_to(manifest)
            destination = root / "package"
            copied_sources = []
            real_copyfile = package_scene_images.shutil.copyfile

            def record_copy(source, target, *args, **kwargs):
                if Path(target) != destination / "manifest.json":
                    copied_sources.append(Path(source).resolve())
                return real_copyfile(source, target, *args, **kwargs)

            with mock.patch.object(sys, "argv", ["package_scene_images.py", str(linked_manifest),
                                                   "--base-manifest", str(base_manifest),
                                                   "--destination", str(destination)]), \
                    mock.patch.object(package_scene_images.shutil, "copyfile", side_effect=record_copy):
                package_scene_images.main()

            expected_sources = sorted([(canonical / "images" / "Panel11.png").resolve(),
                                       (base / "images" / "old.png").resolve()])
            self.assertEqual(sorted(copied_sources), expected_sources)
            self.assertEqual(validate(destination / "manifest.json")[1], sorted(map(Path, [
                "images/Panel11.png", "images/base/old.png"])))

    def test_ui_export_is_bounded_provenanced_and_packaged(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            payload = make_smp((0, 0x8000, 0x03E0))
            item = (payload, len(payload), 24, 6)
            archive = make_mkf([item] * 77)
            (source / "Panel.mkf").write_bytes(archive)
            stage = root / "stage"
            group = export_ui_resources("Game", source, stage)
            self.assertEqual(set(group), {"Panel"})
            self.assertEqual(group["Panel"]["archive_sha256"], hashlib.sha256(archive).hexdigest())
            self.assertEqual(set(group["Panel"]["resources"]), {"0", "1", "2", "75"})
            record = group["Panel"]["resources"]["75"]["chunks"]["0"]
            self.assertEqual(record["logical"], {"width": 3, "height": 1, "anchor_x": -2, "anchor_y": 5})
            width, height, pixels = read_png_rgba((stage / record["path"]).read_bytes())
            self.assertEqual((width, height), (3, 1))
            self.assertEqual(pixels[:8], bytes([0, 0, 0, 0, 0, 0, 0, 255]))
            manifest = {"schema": "richman4.scene-images/v1", "characters": {},
                        "maps": [{"world_rect": {"x": 0, "y": 0, "width": 3, "height": 1}, "image": record}],
                        "ui": {"Game": group}}
            path = stage / "manifest.json"
            path.write_text(json.dumps(manifest))
            _, paths = validate(path)
            self.assertEqual(len(paths), 4)
            (stage / group["Panel"]["resources"]["1"]["chunks"]["0"]["path"]).write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                validate(path)

    def test_referenced_png_integrity_and_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image = root / "images" / "test.png"
            chunk = VisualChunk(0, 4, 4, 0, 0, bytes(16))
            visual = VisualResource("SPR", 1, 0, bytes(512), (chunk,))
            write_png(image, chunk, visual, pixel_format="rgb555")
            record = {"path": "images/test.png", "width": 4, "height": 4, "sha256": hashlib.sha256(image.read_bytes()).hexdigest()}
            manifest = {"schema": "richman4.scene-images/v1", "characters": {},
                        "maps": [{"world_rect": {"x": 0, "y": 0, "width": 2304, "height": 2304}, "image": record}]}
            path = root / "manifest.json"
            path.write_text(json.dumps(manifest))
            self.assertEqual(validate(path)[1], [Path("images/test.png")])
            for multiplier in (2, 4):
                chunk = VisualChunk(0, 4 * multiplier, 4 * multiplier, 0, 0, bytes(16 * multiplier * multiplier))
                write_png(image, chunk, VisualResource("SPR", 1, 0, bytes(512), (chunk,)), pixel_format="rgb555")
                record.update(width=4 * multiplier, height=4 * multiplier, sha256=hashlib.sha256(image.read_bytes()).hexdigest())
                path.write_text(json.dumps(manifest))
            self.assertEqual(validate(path)[0]["maps"][0]["world_rect"]["width"], 2304)
            record["width"] = 999
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "dimensions mismatch"):
                validate(path)
            record["width"] = 16
            manifest["ui"] = {"frames": [{"logical": {"width": 4, "height": 1, "anchor_x": 0, "anchor_y": 0}}]}
            path.write_text(json.dumps(manifest))
            self.assertEqual(validate(path)[0]["ui"]["frames"][0]["logical"]["width"], 4)
            manifest["ui"]["frames"][0]["logical"]["anchor_x"] = 65536
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "logical bounds"):
                validate(path)
            record["path"] = "images/../../elsewhere.png"
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "unsafe"):
                validate(path)
            record["path"] = "images/test.png"
            path.write_text(json.dumps(manifest))
            image.write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                validate(path)
