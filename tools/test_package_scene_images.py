"""Private packaging must not copy unrelated files or corrupt scene images."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from decode_original_images import FormatError, VisualChunk, VisualResource, write_png
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


def panel_archive(bank_counts=None):
    """Tiny original-format fixtures; Panel22 is deliberately not an image."""
    payload = make_smp((0, 0x8000, 0x03E0))
    entries = [(payload, len(payload), 24, 6)] * 77
    for resource, count in (bank_counts or {21: 26, 23: 24, 24: 30}).items():
        offset = 12 + count * 12
        bank = (b"SMP\0" + struct.pack("<II", count, offset)
                + struct.pack("<hhhhI", 3, 1, -2, 5, 6) * count
                + struct.pack("<3H", 0, 0x8000, resource) * count)
        entries[resource] = (bank, len(bank), offset, 6 * count)
    entries[22] = (b"nonvisual", 9, 0, 0)
    return make_mkf(entries)


def write_bank_scene(root):
    """Build a valid package independently of the production exporter."""
    background = png_record(root / "images/background.png", "images/background.png")
    path = write_scene_manifest(root, [background])
    manifest = json.loads(path.read_text())
    manifest["ui"] = {}
    for edition in ("Game", "MultiverseJourney"):
        resources = {}
        for resource, count in (("21", 26), ("23", 24), ("24", 30)):
            chunks = {}
            for index in range(count):
                relative = f"images/{edition}/ui/Panel/{resource}/{index}.png"
                chunks[str(index)] = dict(png_record(root / relative, relative),
                    logical={"width": 3, "height": 1, "anchor_x": -2, "anchor_y": 5})
            resources[resource] = {"payload_sha256": "1" * 64, "signature": "SMP",
                                   "transparent_word_zero": True, "chunks": chunks}
        manifest["ui"][edition] = {"Panel": {"archive_sha256": "2" * 64,
                                                 "resources": resources}}
    path.write_text(json.dumps(manifest))
    return path, manifest


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
            archive = panel_archive()
            (source / "Panel.mkf").write_bytes(archive)
            stage = root / "stage"
            group = export_ui_resources("Game", source, stage)
            self.assertEqual(set(group), {"Panel"})
            self.assertEqual(group["Panel"]["archive_sha256"], hashlib.sha256(archive).hexdigest())
            self.assertEqual(set(group["Panel"]["resources"]), {"0", "1", "2", "21", "23", "24", "75"})
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
            self.assertEqual(len(paths), 84)
            (stage / group["Panel"]["resources"]["1"]["chunks"]["0"]["path"]).write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                validate(path)

    def test_bank_export_and_required_cli_copy_cover_both_editions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            archive = panel_archive()
            (source / "Panel.mkf").write_bytes(archive)
            stage = root / "stage"
            ui = {edition: export_ui_resources(edition, source, stage)
                  for edition in ("Game", "MultiverseJourney")}
            for edition, group in ui.items():
                resources = group["Panel"]["resources"]
                self.assertEqual(set(resources), {"0", "1", "2", "21", "23", "24", "75"})
                for resource, count in (("21", 26), ("23", 24), ("24", 30)):
                    atlas = resources[resource]
                    self.assertEqual(set(atlas["chunks"]), {str(index) for index in range(count)})
                    self.assertTrue(atlas["transparent_word_zero"])
                    record = atlas["chunks"][str(count - 1)]
                    self.assertEqual(record["logical"], {"width": 3, "height": 1, "anchor_x": -2, "anchor_y": 5})
                    self.assertEqual(record["path"], f"images/{edition}/ui/Panel/{resource}/{count - 1}.png")
                    self.assertEqual(read_png_rgba((stage / record["path"]).read_bytes())[2][:8],
                                     bytes([0, 0, 0, 0, 0, 0, 0, 255]))
            path = write_scene_manifest(stage, [ui["Game"]["Panel"]["resources"]["0"]["chunks"]["0"]])
            manifest = json.loads(path.read_text())
            manifest["ui"] = ui
            path.write_text(json.dumps(manifest))
            (stage / "images/unrelated.png").write_bytes(b"not copied")
            destination = root / "package"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("package_scene_images.py")),
                                     str(path), "--require-bank-ui", "--destination", str(destination)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(validate(destination / "manifest.json", require_bank_ui=True)[1]), 168)
            self.assertEqual((destination / "manifest.json").read_bytes(), path.read_bytes())
            self.assertFalse((destination / "images/unrelated.png").exists())

    def test_bank_export_rejects_wrong_chunk_counts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            for resource, expected in ((21, 26), (23, 24), (24, 30)):
                for delta in (-1, 1):
                    with self.subTest(resource=resource, delta=delta):
                        counts = {21: 26, 23: 24, 24: 30}
                        counts[resource] = expected + delta
                        (source / "Panel.mkf").write_bytes(panel_archive(counts))
                        with self.assertRaisesRegex(FormatError, "bank|Bank|chunks"):
                            export_ui_resources("Game", source, root / f"stage-{resource}-{delta}")

    def test_required_bank_ui_rejects_omitted_atlases_and_parent_groups(self):
        with tempfile.TemporaryDirectory() as temp:
            path, complete = write_bank_scene(Path(temp))
            self.assertEqual(len(validate(path, require_bank_ui=True)[1]), 161)
            for keys in (("ui",), ("ui", "Game"), ("ui", "MultiverseJourney"),
                         ("ui", "Game", "Panel"), ("ui", "Game", "Panel", "resources"),
                         *(("ui", edition, "Panel", "resources", resource)
                           for edition in ("Game", "MultiverseJourney")
                           for resource in ("21", "23", "24"))):
                with self.subTest(omitted=keys):
                    manifest = json.loads(json.dumps(complete))
                    parent = manifest
                    for key in keys[:-1]:
                        parent = parent[key]
                    del parent[keys[-1]]
                    path.write_text(json.dumps(manifest))
                    # Inventory/shop overlays may intentionally use partial base UI.
                    validate(path)
                    with self.assertRaisesRegex(ValueError, "bank|Bank"):
                        validate(path, require_bank_ui=True)

    def test_present_bank_atlas_rejects_missing_extra_and_malformed_chunks(self):
        with tempfile.TemporaryDirectory() as temp:
            path, complete = write_bank_scene(Path(temp))
            for edition in ("Game", "MultiverseJourney"):
                for resource in ("21", "23", "24"):
                    for fault in ("missing", "extra", "wrong-index", "null", "no-path", "no-logical", "bad-logical"):
                        with self.subTest(edition=edition, resource=resource, fault=fault):
                            manifest = json.loads(json.dumps(complete))
                            chunks = manifest["ui"][edition]["Panel"]["resources"][resource]["chunks"]
                            if fault == "missing":
                                del chunks["0"]
                            elif fault == "extra":
                                chunks["999"] = chunks["0"]
                            elif fault == "wrong-index":
                                chunks["999"] = chunks.pop("0")
                            elif fault == "null":
                                chunks["0"] = None
                            elif fault == "no-path":
                                del chunks["0"]["path"]
                            elif fault == "no-logical":
                                del chunks["0"]["logical"]
                            else:
                                chunks["0"]["logical"]["anchor_x"] = 65536
                            path.write_text(json.dumps(manifest))
                            with self.assertRaisesRegex(ValueError, "bank|Bank|logical"):
                                validate(path)

    def test_required_bank_ui_still_checks_png_integrity(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path, manifest = write_bank_scene(root)
            record = manifest["ui"]["MultiverseJourney"]["Panel"]["resources"]["24"]["chunks"]["29"]
            (root / record["path"]).write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                validate(path, require_bank_ui=True)

    def test_present_bank_ui_rejects_invalid_archive_metadata(self):
        with tempfile.TemporaryDirectory() as temp:
            path, complete = write_bank_scene(Path(temp))
            for required in (False, True):
                self.assertEqual(len(validate(path, require_bank_ui=required)[1]), 161)
            for edition in ("Game", "MultiverseJourney"):
                for fault, value in (("missing", None), ("null", None),
                                     ("non-string", ["2"] * 64),
                                     ("short", "2" * 63), ("long", "2" * 65)):
                    for required in (False, True):
                        with self.subTest(edition=edition, fault=fault, required=required):
                            manifest = json.loads(json.dumps(complete))
                            panel = manifest["ui"][edition]["Panel"]
                            if fault == "missing":
                                del panel["archive_sha256"]
                            else:
                                panel["archive_sha256"] = value
                            path.write_text(json.dumps(manifest))
                            with self.assertRaisesRegex(ValueError,
                                    f"invalid bank UI archive_sha256: {edition}/Panel"):
                                validate(path, require_bank_ui=required)

    def test_required_cli_rejects_missing_archive_metadata_before_copying(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path, manifest = write_bank_scene(root / "stage")
            del manifest["ui"]["Game"]["Panel"]["archive_sha256"]
            path.write_text(json.dumps(manifest))
            destination = root / "package"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("package_scene_images.py")),
                                     str(path), "--require-bank-ui", "--destination", str(destination)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("invalid bank UI archive_sha256: Game/Panel", result.stderr)
            self.assertFalse(destination.exists())

    def test_nonbank_partial_panel_does_not_require_archive_metadata(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            background = png_record(root / "images/background.png", "images/background.png")
            path = write_scene_manifest(root, [background])
            manifest = json.loads(path.read_text())
            manifest["ui"] = {edition: {"Panel": {"resources": {
                "0": {"chunks": {"0": background}}}}}
                for edition in ("Game", "MultiverseJourney")}
            path.write_text(json.dumps(manifest))
            self.assertEqual(validate(path)[1], [Path("images/background.png")])
            with self.assertRaisesRegex(ValueError, "missing bank UI resource: Game/Panel/21"):
                validate(path, require_bank_ui=True)

    def test_bank_ui_rejects_wrong_image_bindings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path, complete = write_bank_scene(root)
            self.assertEqual(len(validate(path, require_bank_ui=True)[1]), 161)
            aliases = {
                "edition": "images/MultiverseJourney/ui/Panel/21/0.png",
                "resource": "images/Game/ui/Panel/23/0.png",
                "chunk": "images/Game/ui/Panel/21/1.png",
                "archive": "images/Game/ui/Data/21/0.png",
                "background": "images/background.png",
                "repeated-base": "images/base/base/Game/ui/Panel/21/0.png",
            }
            for relative in (aliases["archive"], aliases["repeated-base"]):
                png_record(root / relative, relative)
            for fault, relative in aliases.items():
                for required in (False, True):
                    with self.subTest(fault=fault, required=required):
                        manifest = json.loads(json.dumps(complete))
                        record = manifest["ui"]["Game"]["Panel"]["resources"]["21"]["chunks"]["0"]
                        record["path"] = relative
                        data = (root / relative).read_bytes()
                        self.assertEqual(hashlib.sha256(data).hexdigest(), record["sha256"])
                        self.assertEqual(struct.unpack_from(">II", data, 16),
                                         (record["width"], record["height"]))
                        path.write_text(json.dumps(manifest))
                        with self.assertRaisesRegex(ValueError,
                                "bank UI image path does not match Game/Panel/21/0"):
                            validate(path, require_bank_ui=required)

    def test_bank_ui_rejects_malformed_image_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            path, complete = write_bank_scene(Path(temp))
            for relative in (None, False, 7, [], {}, "", "images/../0.png", "images\\0.png"):
                with self.subTest(path=relative):
                    manifest = json.loads(json.dumps(complete))
                    manifest["ui"]["Game"]["Panel"]["resources"]["21"]["chunks"]["0"]["path"] = relative
                    path.write_text(json.dumps(manifest))
                    with self.assertRaisesRegex(ValueError, "path"):
                        validate(path, require_bank_ui=True)

    def test_required_cli_rejects_wrong_image_binding_before_copying(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path, manifest = write_bank_scene(root / "stage")
            game_chunks = manifest["ui"]["Game"]["Panel"]["resources"]["21"]["chunks"]
            game_chunks["0"] = manifest["ui"]["MultiverseJourney"]["Panel"]["resources"]["21"]["chunks"]["0"]
            path.write_text(json.dumps(manifest))
            destination = root / "package"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("package_scene_images.py")),
                                     str(path), "--require-bank-ui", "--destination", str(destination)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("bank UI image path does not match Game/Panel/21/0", result.stderr)
            self.assertFalse(destination.exists())

    def test_required_bank_ui_allows_already_inherited_base_records(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            base = root / "base"
            base_manifest, manifest = write_bank_scene(base)
            (base / "images").rename(base / "original-images")
            (base / "images").mkdir()
            (base / "images/base").symlink_to(base / "original-images", target_is_directory=True)
            for record in package_scene_images._image_records(manifest):
                record["path"] = "images/base/" + record["path"][len("images/"):]
            base_manifest.write_text(json.dumps(manifest))
            self.assertEqual(len(validate(base_manifest, require_bank_ui=True)[1]), 161)
            overlay = root / "overlay"
            (overlay / "images").mkdir(parents=True)
            (overlay / "images/base").symlink_to(base / "images/base", target_is_directory=True)
            path = overlay / "manifest.json"
            path.write_text(json.dumps(manifest))
            self.assertEqual(len(validate(path, base_manifest=base_manifest, require_bank_ui=True)[1]), 161)
            with self.assertRaisesRegex(ValueError, "escapes|base"):
                validate(path, require_bank_ui=True)

    def test_present_bank_atlas_rejects_malformed_resource_containers(self):
        with tempfile.TemporaryDirectory() as temp:
            path, complete = write_bank_scene(Path(temp))
            for value in (None, [], {}, {"chunks": []}, {"chunks": None}):
                with self.subTest(resource=value):
                    manifest = json.loads(json.dumps(complete))
                    manifest["ui"]["Game"]["Panel"]["resources"]["21"] = value
                    path.write_text(json.dumps(manifest))
                    with self.assertRaisesRegex(ValueError, "bank|Bank"):
                        validate(path)

    def test_required_cli_rejects_missing_atlas_before_copying(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path, manifest = write_bank_scene(root / "stage")
            del manifest["ui"]["MultiverseJourney"]["Panel"]["resources"]["23"]
            path.write_text(json.dumps(manifest))
            destination = root / "package"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("package_scene_images.py")),
                                     str(path), "--require-bank-ui", "--destination", str(destination)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing bank UI resource: MultiverseJourney/Panel/23", result.stderr)
            self.assertFalse(destination.exists())

    def test_required_bank_ui_allows_exact_inherited_base_records(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            base = root / "base"
            base_manifest, manifest = write_bank_scene(base)
            overlay = root / "overlay"
            (overlay / "images").mkdir(parents=True)
            (overlay / "images/base").symlink_to(base / "images", target_is_directory=True)
            for record in package_scene_images._image_records(manifest):
                record["path"] = "images/base/" + record["path"][len("images/"):]
            path = overlay / "manifest.json"
            path.write_text(json.dumps(manifest))
            destination = root / "package"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("package_scene_images.py")),
                                     str(path), "--require-bank-ui", "--base-manifest", str(base_manifest),
                                     "--destination", str(destination)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(validate(destination / "manifest.json", require_bank_ui=True)[1]), 161)
            with self.assertRaisesRegex(ValueError, "escapes|base"):
                validate(path, require_bank_ui=True)

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
