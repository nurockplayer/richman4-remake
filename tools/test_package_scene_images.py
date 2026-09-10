"""Private packaging must not copy unrelated files or corrupt scene images."""
from __future__ import annotations

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
    JUMP_RESOURCE_RANGES,
    RAW_RGB555_BYTES,
    RAW_RGB555_HEIGHT,
    RAW_RGB555_WIDTH,
    REQUIRED_UI_CHUNKS,
    export_ui_resources,
    update_ui_manifest,
)
from test_decode_original_images import make_mkf, make_smp, make_spr, read_png_rgba
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
    def _make_raw_rgb555(*, zero: bool = False) -> bytes:
        pixels = bytearray(RAW_RGB555_BYTES)
        if not zero:
            struct.pack_into("<H", pixels, 0, 0x7C00)
            struct.pack_into("<H", pixels, 2, 0x03E0)
        return bytes(pixels)

    @classmethod
    def _jump_archive(cls, edition: str, *, raw_override: bytes | None = None) -> bytes:
        """Build the complete bounded jump index range for one edition."""

        ranges = JUMP_RESOURCE_RANGES[edition]
        raw = cls._make_raw_rgb555() if raw_override is None else raw_override
        replacements = {
            index: (raw, len(raw), 0, len(raw))
            for index in ranges["map_backgrounds"]
        }
        if edition == "MultiverseJourney":
            zero = cls._make_raw_rgb555(zero=True)
            replacements[4] = (zero, len(zero), 0, len(zero))
        setup = cls._make_smp_chunks(2)
        setup_index = ranges["setup"][0]
        replacements[setup_index] = (setup, len(setup), 12 + 2 * 12, 4)
        sprite = make_spr()
        replacements.update(
            {
                index: (sprite, len(sprite), 24, 512)
                for index in ranges["character_previews"]
            }
        )
        return cls._indexed_archive(max(replacements) + 1, replacements)

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
            game_save_load = self._make_smp_chunks(7)
            mj_save_load = self._make_smp_chunks(11)
            raw = self._make_raw_rgb555()
            game_jump = self._jump_archive("Game")
            mj_jump = self._jump_archive("MultiverseJourney")
            (game / "jump.mkf").write_bytes(game_jump)
            (mj / "jump.mkf").write_bytes(mj_jump)
            game_data = self._indexed_archive(
                561,
                {
                    479: (game_save_load, len(game_save_load), 12 + 7 * 12, 14),
                    560: (raw, len(raw), 4, len(raw) - 4),
                },
            )
            mj_data = self._indexed_archive(
                602,
                {
                    520: (mj_save_load, len(mj_save_load), 12 + 11 * 12, 22),
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

            game_jump_indices = JUMP_RESOURCE_RANGES["Game"]
            mj_jump_indices = JUMP_RESOURCE_RANGES["MultiverseJourney"]
            self.assertEqual(game_jump_indices["map_backgrounds"], (0, 1, 2, 3))
            self.assertEqual(game_jump_indices["setup"], (4,))
            self.assertEqual(game_jump_indices["character_previews"], tuple(range(5, 41)))
            self.assertEqual(mj_jump_indices["map_backgrounds"], tuple(range(8)))
            self.assertEqual(mj_jump_indices["setup"], (8,))
            self.assertEqual(mj_jump_indices["character_previews"], tuple(range(9, 45)))
            self.assertEqual(
                set(game_group["jump"]["resources"]),
                {str(index) for values in game_jump_indices.values() for index in values},
            )
            self.assertEqual(
                set(mj_group["jump"]["resources"]),
                {str(index) for values in mj_jump_indices.values() for index in values},
            )
            for index in game_jump_indices["map_backgrounds"]:
                resource = game_group["jump"]["resources"][str(index)]
                self.assertEqual(resource["signature"], "RAW-RGB555")
                self.assertEqual(resource["chunks"]["0"]["width"], RAW_RGB555_WIDTH)
                self.assertEqual(resource["chunks"]["0"]["height"], RAW_RGB555_HEIGHT)
            for index in mj_jump_indices["map_backgrounds"]:
                resource = mj_group["jump"]["resources"][str(index)]
                self.assertEqual(resource["signature"], "RAW-RGB555")
                self.assertEqual(resource["chunks"]["0"]["width"], RAW_RGB555_WIDTH)
                self.assertEqual(resource["chunks"]["0"]["height"], RAW_RGB555_HEIGHT)
            for index in game_jump_indices["character_previews"]:
                self.assertEqual(
                    game_group["jump"]["resources"][str(index)]["signature"], "SPR"
                )
            for index in mj_jump_indices["character_previews"]:
                self.assertEqual(
                    mj_group["jump"]["resources"][str(index)]["signature"], "SPR"
                )
            mj_zero_frame = mj_group["jump"]["resources"]["4"]["chunks"]["0"]
            _, _, mj_zero_rgba = read_png_rgba(
                (root / "mj-stage" / mj_zero_frame["path"]).read_bytes()
            )
            self.assertEqual(mj_zero_rgba[:4], bytes((0, 0, 0, 255)))
            for base, ranges in ((5, game_jump_indices), (9, mj_jump_indices)):
                for character_id in range(12):
                    for vehicle_index in range(3):
                        index = base + character_id * 3 + vehicle_index
                        self.assertIn(index, ranges["character_previews"])
            self.assertEqual(set(game_group["Data"]["resources"]), {"1", "2", "3", "479", "560"})
            self.assertEqual(set(mj_group["Data"]["resources"]), {"1", "2", "3", "520", "601"})
            self.assertEqual(set(game_group["Data"]["resources"]["479"]["chunks"]), {str(i) for i in range(7)})
            self.assertEqual(set(mj_group["Data"]["resources"]["520"]["chunks"]), {str(i) for i in range(11)})
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
            save_load = self._make_smp_chunks(7)
            archive = self._indexed_archive(
                561,
                {
                    479: (save_load, len(save_load), 12 + 7 * 12, 14),
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
            setup = self._make_smp_chunks(7)
            archive = self._indexed_archive(
                561,
                {
                    479: (setup, len(setup), 12 + 7 * 12, 14),
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
            save_load = self._make_smp_chunks(7)
            (source / "Data.mkf").write_bytes(
                self._indexed_archive(
                    561,
                    {
                        479: (save_load, len(save_load), 12 + 7 * 12, 14),
                        560: (short_raw, len(short_raw), 0, 0),
                    },
                )
            )
            with self.assertRaisesRegex(FormatError, "raw RGB555 UI resource"):
                export_ui_resources("Game", source, root / "short-stage")

            (source / "Data.mkf").unlink()
            (source / "jump.mkf").write_bytes(
                self._jump_archive("Game", raw_override=b"\0" * (RAW_RGB555_BYTES - 2))
            )
            with self.assertRaisesRegex(FormatError, "raw RGB555 UI resource"):
                export_ui_resources("Game", source, root / "short-jump-stage")

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

    def test_save_load_requires_complete_source_chunk_ranges(self):
        self.assertEqual(REQUIRED_UI_CHUNKS[("Game", "Data", 479)], tuple(range(7)))
        self.assertEqual(
            REQUIRED_UI_CHUNKS[("MultiverseJourney", "Data", 520)], tuple(range(11))
        )
        cases = (
            ("Game", 479, 561, 7),
            ("MultiverseJourney", 520, 602, 11),
        )
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for edition, index, archive_count, required_count in cases:
                source = root / edition
                source.mkdir()
                partial = self._make_smp_chunks(2)
                (source / "Data.mkf").write_bytes(
                    self._indexed_archive(
                        archive_count,
                        {index: (partial, len(partial), 12 + 2 * 12, 4)},
                    )
                )
                with self.assertRaisesRegex(FormatError, r"missing chunk\(s\): 2"):
                    export_ui_resources(edition, source, root / f"{edition}-stage")

    def test_ui_manifest_update_is_incremental_and_preserves_existing_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "Game"
            source.mkdir(parents=True)
            raw = self._make_raw_rgb555()
            save_load = self._make_smp_chunks(7)
            (source / "map.mkf").write_bytes(
                make_mkf([(make_smp((0x03E0,)), len(make_smp((0x03E0,))), 24, 2)])
            )
            (source / "Data.mkf").write_bytes(
                self._indexed_archive(
                    561,
                    {
                        479: (save_load, len(save_load), 12 + 7 * 12, 14),
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

    def test_ui_manifest_merges_resources_with_matching_archive_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "Game"
            source.mkdir(parents=True)
            save_load = self._make_smp_chunks(7)
            raw = self._make_raw_rgb555()
            archive = self._indexed_archive(
                561,
                {
                    479: (save_load, len(save_load), 12 + 7 * 12, 14),
                    560: (raw, len(raw), 4, len(raw) - 4),
                },
            )
            (source / "map.mkf").write_bytes(
                make_mkf([(make_smp((0x03E0,)), len(make_smp((0x03E0,))), 24, 2)])
            )
            (source / "Data.mkf").write_bytes(archive)

            output = root / "scene"
            output.mkdir()
            existing = output / "images/Game/ui/Data/999/0.png"
            existing_chunk = VisualChunk(0, 1, 1, 0, 0, struct.pack("<H", 0x03E0))
            existing_visual = VisualResource("SMP", 1, 0, None, (existing_chunk,))
            write_png(existing, existing_chunk, existing_visual, pixel_format="rgb555")
            existing_bytes = existing.read_bytes()
            existing_record = {
                "path": "images/Game/ui/Data/999/0.png",
                "sha256": hashlib.sha256(existing_bytes).hexdigest(),
                "width": 1,
                "height": 1,
            }
            base = output / "images/base.png"
            write_png(base, existing_chunk, existing_visual, pixel_format="rgb555")
            base_record = {
                "path": "images/base.png",
                "sha256": hashlib.sha256(base.read_bytes()).hexdigest(),
                "width": 1,
                "height": 1,
            }
            data_group = {
                "archive": "Data.mkf",
                "archive_sha256": hashlib.sha256(archive).hexdigest(),
                "resources": {"999": {"chunks": {"0": existing_record}}},
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
                "ui": {"Game": {"Data": data_group}},
            }
            manifest_path = output / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            updated = update_ui_manifest(root / "source", manifest_path, editions={"Game"})
            self.assertIn("999", updated["ui"]["Game"]["Data"]["resources"])
            self.assertEqual(existing.read_bytes(), existing_bytes)

    def test_ui_manifest_rejects_archive_hash_mismatch_without_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "Game"
            source.mkdir(parents=True)
            save_load = self._make_smp_chunks(7)
            raw = self._make_raw_rgb555()
            archive = self._indexed_archive(
                561,
                {
                    479: (save_load, len(save_load), 12 + 7 * 12, 14),
                    560: (raw, len(raw), 4, len(raw) - 4),
                },
            )
            (source / "map.mkf").write_bytes(
                make_mkf([(make_smp((0x03E0,)), len(make_smp((0x03E0,))), 24, 2)])
            )
            data_path = source / "Data.mkf"
            data_path.write_bytes(archive)
            changed = bytearray(archive)
            changed[archive.index(raw) + 4] ^= 1
            data_path.write_bytes(changed)

            output = root / "scene"
            output.mkdir()
            existing = output / "images/Game/ui/Data/999/0.png"
            existing_chunk = VisualChunk(0, 1, 1, 0, 0, struct.pack("<H", 0x03E0))
            existing_visual = VisualResource("SMP", 1, 0, None, (existing_chunk,))
            write_png(existing, existing_chunk, existing_visual, pixel_format="rgb555")
            existing_bytes = existing.read_bytes()
            existing_record = {
                "path": "images/Game/ui/Data/999/0.png",
                "sha256": hashlib.sha256(existing_bytes).hexdigest(),
                "width": 1,
                "height": 1,
            }
            base = output / "images/base.png"
            write_png(base, existing_chunk, existing_visual, pixel_format="rgb555")
            base_record = {
                "path": "images/base.png",
                "sha256": hashlib.sha256(base.read_bytes()).hexdigest(),
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
                "ui": {
                    "Game": {
                        "Data": {
                            "archive": "Data.mkf",
                            "archive_sha256": hashlib.sha256(archive).hexdigest(),
                            "resources": {"999": {"chunks": {"0": existing_record}}},
                        }
                    }
                },
            }
            manifest_path = output / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            before_manifest = manifest_path.read_bytes()

            with self.assertRaisesRegex(InputError, "archive SHA"):
                update_ui_manifest(root / "source", manifest_path, editions={"Game"})
            self.assertEqual(manifest_path.read_bytes(), before_manifest)
            self.assertEqual(existing.read_bytes(), existing_bytes)
            self.assertFalse((output / "images/Game/ui/Data/479/0.png").exists())

    def test_invalid_destination_manifest_has_zero_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "Game"
            source.mkdir(parents=True)
            save_load = self._make_smp_chunks(7)
            (source / "Data.mkf").write_bytes(
                self._indexed_archive(
                    561,
                    {479: (save_load, len(save_load), 12 + 7 * 12, 14)},
                )
            )
            output = root / "scene"
            output.mkdir()
            manifest_path = output / "manifest.json"
            manifest_path.write_bytes(b"{invalid json")
            before_manifest = manifest_path.read_bytes()

            with self.assertRaises(ValueError):
                update_ui_manifest(root / "source", manifest_path, editions={"Game"})
            self.assertEqual(manifest_path.read_bytes(), before_manifest)
            self.assertFalse((output / "images/Game/ui/Data/479/0.png").exists())

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
