"""Synthetic regression tests for the bounded S17/S18 UI asset slice.

These tests never read or distribute the owner-provided original images.  The
MKF/SMP fixtures are deliberately tiny and exercise the same explicit resource
and chunk validation used by the private incremental exporter.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parent))
from decode_original_images import (  # noqa: E402
    FormatError,
    VisualChunk,
    VisualResource,
    write_png,
)
import original_ui_assets as assets  # noqa: E402


def make_mkf(resources: list[tuple[bytes, int, int, int]]) -> bytes:
    """Build an uncompressed MKF fixture from payload and image metadata."""

    body = bytearray(struct.pack("<I", 0))
    starts: list[int] = []
    for payload, decoded_size, image_offset, image_size in resources:
        starts.append(len(body))
        body.extend(struct.pack("<4I", decoded_size, len(payload), image_offset, image_size))
        body.extend(payload)
    table_offset = len(body)
    body[0:4] = struct.pack("<I", table_offset)
    body.extend(struct.pack(f"<{len(starts)}I", *starts))
    return bytes(body)


def make_smp_chunks(count: int) -> bytes:
    """Build count 1x1 RGB555 chunks with source-like anchors."""

    start_offset = 12 + count * 12
    table = b"".join(
        struct.pack("<hhhhI", 1, 1, chunk, -chunk, 2) for chunk in range(count)
    )
    pixels = b"".join(struct.pack("<H", 0x03E0 + chunk) for chunk in range(count))
    return b"SMP\0" + struct.pack("<II", count, start_offset) + table + pixels


def make_spr_chunks(count: int) -> bytes:
    """Build count 1x1 indexed chunks with a valid 256-colour palette."""

    start_offset = 12 + count * 12
    table = b"".join(
        struct.pack("<hhhhI", 1, 1, chunk, -chunk, 1) for chunk in range(count)
    )
    palette = bytearray(512)
    struct.pack_into("<H", palette, 2, 0x7C00)
    return b"SPR\0" + struct.pack("<II", count, start_offset) + table + bytes(palette) + bytes([1]) * count


class MonthlyUiAssetTests(unittest.TestCase):

    @staticmethod
    def _indexed_archive(
        count: int,
        replacements: dict[int, tuple[bytes, int, int, int]],
    ) -> bytes:
        small = make_smp_chunks(1)
        entries = [(small, len(small), 24, 2)] * count
        for index, replacement in replacements.items():
            if index < count:
                entries[index] = replacement
        return make_mkf(entries)

    @classmethod
    def _panel_archive(
        cls,
        *,
        panel25_count: int = 83,
        panel76_count: int = 1,
        entry_count: int = 77,
    ) -> bytes:
        panel21 = make_spr_chunks(26)
        panel23 = make_smp_chunks(24)
        panel24 = make_smp_chunks(30)
        panel25 = make_smp_chunks(panel25_count)
        panel76 = make_smp_chunks(panel76_count)
        replacements = {
            21: (panel21, len(panel21), 12 + 26 * 12, 512),
            23: (panel23, len(panel23), 12 + 24 * 12, 48),
            24: (panel24, len(panel24), 12 + 30 * 12, 60),
            25: (panel25, len(panel25), 12 + panel25_count * 12, 2 * panel25_count),
            76: (panel76, len(panel76), 12 + panel76_count * 12, 2 * panel76_count),
        }
        return cls._indexed_archive(entry_count, replacements)

    @staticmethod
    def _required_api() -> None:
        required = {
            "UI_RESOURCES": getattr(assets, "UI_RESOURCES", None),
            "BANK_UI_CHUNK_COUNTS": getattr(assets, "BANK_UI_CHUNK_COUNTS", None),
            "REQUIRED_UI_CHUNKS": getattr(assets, "REQUIRED_UI_CHUNKS", None),
            "EXPECTED_UI_CHUNK_COUNTS": getattr(assets, "EXPECTED_UI_CHUNK_COUNTS", None),
            "export_ui_resources": getattr(assets, "export_ui_resources", None),
            "update_ui_manifest": getattr(assets, "update_ui_manifest", None),
        }
        for name, value in required.items():
            if value is None:
                raise AssertionError(f"monthly exporter API {name} is absent (qualified RED)")

    def test_bindings_and_exact_metadata_cover_both_editions(self) -> None:
        self._required_api()
        self.assertIn(25, assets.UI_RESOURCES["Panel"])
        self.assertIn(76, assets.UI_RESOURCES["Panel"])
        self.assertEqual(assets.BANK_UI_CHUNK_COUNTS[25], 83)
        self.assertEqual(assets.BANK_UI_CHUNK_COUNTS[76], 1)
        for edition in ("Game", "MultiverseJourney"):
            self.assertEqual(
                assets.REQUIRED_UI_CHUNKS[(edition, "Panel", 25)],
                tuple(range(83)),
            )
            self.assertEqual(
                assets.REQUIRED_UI_CHUNKS[(edition, "Panel", 76)],
                (0,),
            )
            self.assertEqual(
                assets.EXPECTED_UI_CHUNK_COUNTS[(edition, "Panel", 25)], 83
            )
            self.assertEqual(
                assets.EXPECTED_UI_CHUNK_COUNTS[(edition, "Panel", 76)], 1
            )

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for edition in ("Game", "MultiverseJourney"):
                source = root / edition
                source.mkdir()
                archive = self._panel_archive()
                (source / "Panel.mkf").write_bytes(archive)
                stage = root / f"{edition}-stage"
                group = assets.export_ui_resources(edition, source, stage)
                panel = group["Panel"]
                self.assertEqual(
                    set(panel["resources"]),
                    {"0", "1", "2", "21", "23", "24", "25", "75", "76"},
                )
                monthly = panel["resources"]["25"]
                dividend = panel["resources"]["76"]
                self.assertEqual(monthly["source"]["edition"], edition)
                self.assertEqual(monthly["source"]["resource_index"], 25)
                self.assertEqual(monthly["signature"], "SMP")
                self.assertEqual(set(monthly["chunks"]), {str(i) for i in range(83)})
                self.assertEqual(
                    monthly["chunks"]["24"]["logical"],
                    {"width": 1, "height": 1, "anchor_x": 24, "anchor_y": -24},
                )
                self.assertEqual(dividend["source"]["resource_index"], 76)
                self.assertEqual(set(dividend["chunks"]), {"0"})
                self.assertTrue((stage / monthly["chunks"]["82"]["path"]).is_file())
                self.assertTrue((stage / dividend["chunks"]["0"]["path"]).is_file())

    def test_missing_monthly_resource_fails_closed(self) -> None:
        self._required_api()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Game"
            source.mkdir()
            (source / "Panel.mkf").write_bytes(
                self._panel_archive(entry_count=76)
            )
            with self.assertRaisesRegex(FormatError, r"required UI resource.*76"):
                assets.export_ui_resources("Game", source, root / "missing-stage")

    def test_missing_chunk_and_count_mismatch_fail_closed(self) -> None:
        self._required_api()
        cases = [
            (82, r"missing chunk\(s\): 82"),
            (84, r"has 84 chunks; expected 83"),
        ]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for count, message in cases:
                source = root / f"Game-{count}"
                source.mkdir()
                (source / "Panel.mkf").write_bytes(
                    self._panel_archive(panel25_count=count)
                )
                with self.assertRaisesRegex(FormatError, message):
                    assets.export_ui_resources("Game", source, root / f"stage-{count}")

    def test_incremental_merge_preserves_unrelated_ui_and_rolls_back_invalid_monthly(self) -> None:
        self._required_api()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_root = root / "source"
            source = source_root / "Game"
            source.mkdir(parents=True)
            (source / "map.mkf").write_bytes(
                make_mkf([(make_smp_chunks(1), len(make_smp_chunks(1)), 24, 2)])
            )
            archive = self._panel_archive()
            (source / "Panel.mkf").write_bytes(archive)

            output = root / "scene"
            output.mkdir()
            base = output / "images/base.png"
            base_chunk = VisualChunk(0, 1, 1, 0, 0, struct.pack("<H", 0x03E0))
            base_visual = VisualResource("SMP", 1, 0, None, (base_chunk,))
            write_png(base, base_chunk, base_visual, pixel_format="rgb555")
            base_bytes = base.read_bytes()
            base_record = {
                "path": "images/base.png",
                "sha256": hashlib.sha256(base_bytes).hexdigest(),
                "width": 1,
                "height": 1,
            }
            archive_sha = hashlib.sha256(archive).hexdigest()
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
                        "Panel": {
                            "archive": "Panel.mkf",
                            "archive_sha256": archive_sha,
                            "resources": {"999": {"chunks": {"0": base_record}}},
                        },
                        "Data": {"preserved": True},
                    }
                },
            }
            manifest_path = output / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            updated = assets.update_ui_manifest(
                source_root, manifest_path, editions={"Game"}
            )
            panel = updated["ui"]["Game"]["Panel"]
            self.assertIn("999", panel["resources"])
            self.assertIn("25", panel["resources"])
            self.assertIn("76", panel["resources"])
            self.assertEqual(updated["ui"]["Game"]["Data"], {"preserved": True})
            self.assertEqual(base.read_bytes(), base_bytes)
            self.assertTrue((output / "images/Game/ui/Panel/25/82.png").is_file())
            before_manifest = manifest_path.read_bytes()
            before_images = {
                path.relative_to(output): path.read_bytes()
                for path in output.rglob("*.png")
            }

            (source / "Panel.mkf").write_bytes(
                self._panel_archive(panel25_count=82)
            )
            with self.assertRaisesRegex(FormatError, r"missing chunk\(s\): 82"):
                assets.update_ui_manifest(
                    source_root, manifest_path, editions={"Game"}
                )
            self.assertEqual(manifest_path.read_bytes(), before_manifest)
            self.assertEqual(
                {
                    path.relative_to(output): path.read_bytes()
                    for path in output.rglob("*.png")
                },
                before_images,
            )


if __name__ == "__main__":
    unittest.main()
