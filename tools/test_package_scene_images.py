"""Private packaging must not copy unrelated files or corrupt scene images."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from decode_original_images import (
    FormatError,
    InputError,
    VisualChunk,
    VisualResource,
    decode_entry,
    write_png,
)
from original_ui_assets import (
    RAW_RGB555_BYTES,
    RAW_RGB555_HEIGHT,
    RAW_RGB555_WIDTH,
    export_ui_resources,
    update_ui_manifest,
)
from test_decode_original_images import make_mkf, make_smp, read_png_rgba
from package_scene_images import validate


class PackageSceneTests(unittest.TestCase):
    @staticmethod
    def _make_smp_chunks(count: int) -> bytes:
        """Build a tiny multi-chunk SMP fixture for selected chunk tests."""

        start_offset = 12 + count * 12
        chunks = b"".join(
            struct.pack("<hhhhI", 1, 1, chunk, -chunk, 2)
            for chunk in range(count)
        )
        pixels = b"".join(struct.pack("<H", 0x03E0 + chunk) for chunk in range(count))
        return b"SMP\0" + struct.pack("<II", count, start_offset) + chunks + pixels

    @staticmethod
    def _make_raw_rgb555() -> bytes:
        pixels = bytearray(RAW_RGB555_BYTES)
        struct.pack_into("<H", pixels, 0, 0x7C00)
        struct.pack_into("<H", pixels, 2, 0x03E0)
        return bytes(pixels)

    @classmethod
    def _indexed_archive(
        cls,
        count: int,
        replacements: dict[int, tuple[bytes, int, int, int]],
    ) -> bytes:
        small = make_smp((0x03E0,))
        entries = [(small, len(small), 24, 2)] * count
        for index, entry in replacements.items():
            entries[index] = entry
        return make_mkf(entries)

    def test_edition_bindings_keep_setup_and_save_indices_separate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            game = root / "Game"
            mj = root / "MultiverseJourney"
            game.mkdir()
            mj.mkdir()
            setup = self._make_smp_chunks(2)
            save_load = self._make_smp_chunks(2)
            raw = self._make_raw_rgb555()
            game_jump = self._indexed_archive(
                5, {4: (setup, len(setup), 12 + 2 * 12, 4)}
            )
            mj_jump = self._indexed_archive(
                9, {8: (setup, len(setup), 12 + 2 * 12, 4)}
            )
            (game / "jump.mkf").write_bytes(game_jump)
            (mj / "jump.mkf").write_bytes(mj_jump)
            game_data = self._indexed_archive(
                561,
                {
                    479: (save_load, len(save_load), 12 + 2 * 12, 4),
                    560: (raw, len(raw), 4, len(raw) - 4),
                },
            )
            mj_data = self._indexed_archive(
                602,
                {
                    520: (save_load, len(save_load), 12 + 2 * 12, 4),
                    601: (raw, len(raw), 4, len(raw) - 4),
                },
            )
            (game / "Data.mkf").write_bytes(game_data)
            (mj / "Data.mkf").write_bytes(mj_data)
            (game / "help.mkf").write_bytes(
                make_mkf([(self._make_smp_chunks(3), len(self._make_smp_chunks(3)), 48, 6)])
            )
            (mj / "help.mkf").write_bytes(
                make_mkf([(self._make_smp_chunks(3), len(self._make_smp_chunks(3)), 48, 6)])
            )

            game_group = export_ui_resources("Game", game, root / "game-stage")
            mj_group = export_ui_resources("MultiverseJourney", mj, root / "mj-stage")

            self.assertEqual(set(game_group["jump"]["resources"]), {"4"})
            self.assertEqual(set(mj_group["jump"]["resources"]), {"8"})
            self.assertEqual(set(game_group["Data"]["resources"]), {"1", "2", "3", "479", "560"})
            self.assertEqual(set(mj_group["Data"]["resources"]), {"1", "2", "3", "520", "601"})
            self.assertNotIn("520", game_group["Data"]["resources"])
            self.assertNotIn("479", mj_group["Data"]["resources"])
            self.assertEqual(game_group["Data"]["resources"]["479"]["source"]["resource_index"], 479)
            self.assertEqual(mj_group["Data"]["resources"]["520"]["source"]["resource_index"], 520)

    def test_headerless_loading_resource_has_explicit_rgb555_binding_and_hashes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Game"
            source.mkdir()
            raw = self._make_raw_rgb555()
            save_load = self._make_smp_chunks(2)
            archive = self._indexed_archive(
                561,
                {
                    479: (save_load, len(save_load), 12 + 2 * 12, 4),
                    560: (raw, len(raw), 4, len(raw) - 4),
                },
            )
            (source / "Data.mkf").write_bytes(archive)
            stage = root / "stage"
            group = export_ui_resources("Game", source, stage)
            resource = group["Data"]["resources"]["560"]
            self.assertEqual(resource["signature"], "RAW-RGB555")
            self.assertEqual(resource["format"], "raw-rgb555")
            self.assertEqual(resource["pixel_format"], "rgb555")
            self.assertFalse(resource["transparent_word_zero"])
            self.assertEqual(resource["source"]["payload_sha256"], hashlib.sha256(raw).hexdigest())
            self.assertEqual(resource["source"]["archive_sha256"], hashlib.sha256(archive).hexdigest())
            frame = resource["chunks"]["0"]
            self.assertEqual((frame["width"], frame["height"]), (RAW_RGB555_WIDTH, RAW_RGB555_HEIGHT))
            image = stage / frame["path"]
            self.assertEqual(frame["sha256"], hashlib.sha256(image.read_bytes()).hexdigest())
            width, height, rgba = read_png_rgba(image.read_bytes())
            self.assertEqual((width, height), (RAW_RGB555_WIDTH, RAW_RGB555_HEIGHT))
            self.assertEqual(rgba[:8], bytes([255, 0, 0, 255, 0, 255, 0, 255]))

    def test_export_decodes_only_configured_entries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Game"
            source.mkdir()
            setup = self._make_smp_chunks(2)
            archive = self._indexed_archive(
                561,
                {
                    479: (setup, len(setup), 12 + 2 * 12, 4),
                    560: (self._make_raw_rgb555(), RAW_RGB555_BYTES, 4, RAW_RGB555_BYTES - 4),
                },
            )
            (source / "Data.mkf").write_bytes(archive)
            calls = []

            def traced_decode(archive_arg, entry):
                calls.append(entry.index)
                return decode_entry(archive_arg, entry)

            with patch("original_ui_assets.decode_entry", side_effect=traced_decode):
                export_ui_resources("Game", source, root / "stage")
            self.assertEqual(calls, [1, 2, 3, 479, 560])

    def test_invalid_or_truncated_bound_resources_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Game"
            source.mkdir()
            short_raw = b"\0" * (RAW_RGB555_BYTES - 2)
            save_load = self._make_smp_chunks(2)
            (source / "Data.mkf").write_bytes(
                self._indexed_archive(
                    561,
                    {
                        479: (save_load, len(save_load), 12 + 2 * 12, 4),
                        560: (short_raw, len(short_raw), 0, 0),
                    },
                )
            )
            with self.assertRaisesRegex(FormatError, "raw RGB555 UI resource"):
                export_ui_resources("Game", source, root / "short-stage")

            one_chunk = make_smp((0x03E0,))
            (source / "Data.mkf").write_bytes(
                self._indexed_archive(
                    561,
                    {479: (one_chunk, len(one_chunk), 24, 2)},
                )
            )
            with self.assertRaisesRegex(FormatError, "missing chunk"):
                export_ui_resources("Game", source, root / "missing-chunk-stage")

            valid = (source / "Data.mkf").read_bytes()
            (source / "Data.mkf").write_bytes(valid[:-3])
            with self.assertRaisesRegex(FormatError, "index table|stored size|outside file"):
                export_ui_resources("Game", source, root / "truncated-stage")

    def test_ui_manifest_update_is_incremental_and_preserves_existing_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "Game"
            source.mkdir(parents=True)
            raw = self._make_raw_rgb555()
            save_load = self._make_smp_chunks(2)
            (source / "map.mkf").write_bytes(
                make_mkf([(make_smp((0x03E0,)), len(make_smp((0x03E0,))), 24, 2)])
            )
            (source / "Data.mkf").write_bytes(
                self._indexed_archive(
                    561,
                    {
                        479: (save_load, len(save_load), 12 + 2 * 12, 4),
                        560: (raw, len(raw), 4, len(raw) - 4),
                    },
                )
            )
            output = root / "scene"
            output.mkdir()
            existing = output / "images" / "base.png"
            chunk = VisualChunk(0, 1, 1, 0, 0, struct.pack("<H", 0x03E0))
            visual = VisualResource("SMP", 1, 0, None, (chunk,))
            write_png(existing, chunk, visual, pixel_format="rgb555")
            existing_bytes = existing.read_bytes()
            base_record = {
                "path": "images/base.png",
                "sha256": hashlib.sha256(existing_bytes).hexdigest(),
                "width": 1,
                "height": 1,
            }
            manifest = {
                "schema": "richman4.scene-images/v1",
                "version": 1,
                "pixel_format": "rgb555",
                "maps": [
                    {
                        "world_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
                        "image": base_record,
                    }
                ],
                "characters": {},
            }
            manifest_path = output / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            updated = update_ui_manifest(root / "source", manifest_path, editions={"Game"})
            self.assertEqual(set(updated["ui"]["Game"]["Data"]["resources"]), {"1", "2", "3", "479", "560"})
            self.assertEqual(existing.read_bytes(), existing_bytes)
            self.assertTrue((output / "images/Game/ui/Data/479/0.png").is_file())
            self.assertTrue((output / "images/Game/ui/Data/560/0.png").is_file())
            self.assertFalse((output / "images/Game/ui/jump/4/0.png").exists())

            preserved_temp = output / "manifest.json.ui-tmp"
            preserved_temp.write_bytes(b"leave this unrelated file alone")
            before_missing = manifest_path.read_bytes()
            with self.assertRaisesRegex(InputError, "requested UI editions"):
                update_ui_manifest(
                    root / "source",
                    manifest_path,
                    editions={"Game", "MultiverseJourney"},
                )
            self.assertEqual(manifest_path.read_bytes(), before_missing)
            self.assertEqual(preserved_temp.read_bytes(), b"leave this unrelated file alone")

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
            record["path"] = "images/../../elsewhere.png"
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "unsafe"):
                validate(path)
            record["path"] = "images/test.png"
            path.write_text(json.dumps(manifest))
            image.write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                validate(path)
