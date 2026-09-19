#!/usr/bin/env python3
"""Focused acceptance tests for the private help package helper.

Fixtures are synthetic only: the two pinned editions are represented by little
MKF archives generated through ``test_export_original_help``'s helpers, so no
original body text or archives are committed here.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

_IMPORT_ERROR = ""
try:
    import export_original_help as exporter
    import package_help
    import test_export_original_help as fixtures
    from decode_original_images import DecodeError
except ImportError as exc:  # pragma: no cover - availability RED only
    exporter = None
    package_help = None
    fixtures = None
    _IMPORT_ERROR = str(exc)

    class DecodeError(Exception):
        """Placeholder so the availability RED still collects."""


class PackageHelpTestCase(unittest.TestCase):
    def setUp(self) -> None:
        if package_help is None or exporter is None or fixtures is None:
            self.fail(
                "availability RED: private help packaging modules are not importable "
                "(%s)" % _IMPORT_ERROR
            )
        self._temporary = tempfile.TemporaryDirectory(prefix="help-package-")
        self.addCleanup(self._temporary.cleanup)
        self.base = Path(self._temporary.name)
        self.root = fixtures.make_root(self.base)
        self.bundle = self.base / "bundle"
        exporter.export_help_bundle(self.root, self.bundle)
        self.manifest = self.bundle / "manifest.json"


class PackageHelpSuccessTests(PackageHelpTestCase):
    def test_valid_two_edition_bundle_round_trips_identical_bytes(self) -> None:
        destination = self.base / "package"
        package_help.package_help(self.manifest, destination)
        self.assertEqual(
            (destination / "manifest.json").read_bytes(), self.manifest.read_bytes()
        )
        for name in ("Game", "MultiverseJourney"):
            relative = Path("content") / ("%s.json" % name)
            self.assertEqual(
                (destination / relative).read_bytes(), (self.bundle / relative).read_bytes()
            )
        manifest, referenced = exporter.validate(destination / "manifest.json")
        self.assertEqual(len(referenced), 2)
        self.assertTrue(manifest["editions"])


class PackageHelpRejectionTests(PackageHelpTestCase):
    def test_invalid_input_creates_no_output(self) -> None:
        broken = self.base / "broken"
        broken.mkdir(parents=True)
        (broken / "manifest.json").write_text(
            '{"schema":"richman4.help/v2","editions":{}}', encoding="utf-8"
        )
        destination = self.base / "rejected"
        with self.assertRaises(DecodeError):
            package_help.package_help(broken / "manifest.json", destination)
        self.assertFalse(destination.exists())

    def test_existing_destination_is_left_unchanged(self) -> None:
        destination = self.base / "existing"
        destination.mkdir(parents=True)
        sentinel = destination / "keep.txt"
        sentinel.write_text("keep", encoding="utf-8")
        with self.assertRaises(OSError):
            package_help.package_help(self.manifest, destination)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")
        self.assertFalse((destination / "manifest.json").exists())

    def test_copy_failure_removes_only_the_newly_created_destination(self) -> None:
        sibling = self.base / "sibling"
        sibling.mkdir(parents=True)
        (sibling / "keep.txt").write_text("keep", encoding="utf-8")
        destination = self.base / "failure"
        with mock.patch.object(
            package_help.shutil, "copyfile", side_effect=OSError("injected copy failure")
        ):
            with self.assertRaises(OSError):
                package_help.package_help(self.manifest, destination)
        self.assertFalse(destination.exists())
        self.assertEqual((sibling / "keep.txt").read_text(encoding="utf-8"), "keep")

    def test_post_copy_validation_failure_cleans_only_the_new_destination(self) -> None:
        sibling = self.base / "sibling-two"
        sibling.mkdir(parents=True)
        (sibling / "keep.txt").write_text("keep", encoding="utf-8")
        destination = self.base / "validate-failure"
        with mock.patch.object(
            package_help,
            "validate",
            side_effect=[({}, []), DecodeError("injected validation failure")],
        ):
            with self.assertRaises(DecodeError):
                package_help.package_help(self.manifest, destination)
        self.assertFalse(destination.exists())
        self.assertEqual((sibling / "keep.txt").read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main()
