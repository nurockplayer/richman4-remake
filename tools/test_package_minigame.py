#!/usr/bin/env python3
"""Focused tests for packaging the private minigame input plane.

Fixtures are synthetic: a zero click mask and a generated coordinate grid.
"""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from package_minigame import package_minigame, validate


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_manifest(root: Path) -> Path:
    manifest_dir = root / "minigame"
    (manifest_dir / "input").mkdir(parents=True)
    mask = bytes(640 * 480)
    (manifest_dir / "input" / "penguin-mask.bin").write_bytes(mask)
    grid = {
        "schema": "richman4.private-source-penguin-coordinate-table/v1",
        "records": [
            {"x": index % 9, "y": index // 9, "source_initial_flags": 0}
            for index in range(81)
        ],
    }
    grid_bytes = json.dumps(grid).encode("utf-8")
    (manifest_dir / "input" / "penguin-grid.json").write_bytes(grid_bytes)
    manifest = {
        "schema": "richman4.minigame-assets/v1",
        "version": 1,
        "input": {
            "penguin_mask": {
                "path": "input/penguin-mask.bin",
                "sha256": _sha(mask),
                "width": 640,
                "height": 480,
            },
            "penguin_grid": {
                "path": "input/penguin-grid.json",
                "sha256": _sha(grid_bytes),
            },
        },
        "resources": {},
    }
    path = manifest_dir / "manifest.json"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    return path


class PackageMinigameTests(unittest.TestCase):
    def test_validate_returns_the_two_input_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest = make_manifest(Path(temp))
            _, paths = validate(manifest)
            self.assertEqual(
                [path.as_posix() for path in paths],
                ["input/penguin-mask.bin", "input/penguin-grid.json"],
            )

    def test_package_copies_only_referenced_input_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest = make_manifest(Path(temp))
            destination = Path(temp) / "package" / "minigame"
            package_minigame(manifest, destination)
            self.assertEqual(
                sorted(path.relative_to(destination).as_posix() for path in destination.rglob("*") if path.is_file()),
                ["input/penguin-grid.json", "input/penguin-mask.bin", "manifest.json"],
            )
            validate(destination / "manifest.json")

    def test_tampered_mask_digest_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest = make_manifest(Path(temp))
            (manifest.parent / "input" / "penguin-mask.bin").write_bytes(bytes(640 * 480 - 1))
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                validate(manifest)

    def test_incomplete_grid_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest = make_manifest(Path(temp))
            grid_path = manifest.parent / "input" / "penguin-grid.json"
            grid = json.loads(grid_path.read_text(encoding="utf-8"))
            grid["records"] = grid["records"][:80]
            grid_bytes = json.dumps(grid).encode("utf-8")
            grid_path.write_bytes(grid_bytes)
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["input"]["penguin_grid"]["sha256"] = _sha(grid_bytes)
            manifest.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "81 records"):
                validate(manifest)

    def test_escaping_input_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest = make_manifest(Path(temp))
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["input"]["penguin_mask"]["path"] = "../outside.bin"
            manifest.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "escapes"):
                validate(manifest)

    def test_existing_destination_is_never_replaced(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest = make_manifest(Path(temp))
            destination = Path(temp) / "package" / "minigame"
            destination.mkdir(parents=True)
            marker = destination / "keep.txt"
            marker.write_text("untouched", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                package_minigame(manifest, destination)
            self.assertEqual(marker.read_text(encoding="utf-8"), "untouched")


if __name__ == "__main__":
    unittest.main()
