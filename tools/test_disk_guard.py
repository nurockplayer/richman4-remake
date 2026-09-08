"""Regression tests for the local disk materialization guard."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DISK_GUARD = ROOT / "tools" / "disk_guard.sh"


def run_guard(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(DISK_GUARD), *args],
        cwd=ROOT,
        check=False,
        text=True,
        capture_output=True,
        env=env,
    )


class DiskGuardTests(unittest.TestCase):
    def test_zero_thresholds_allow_materialization(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result = run_guard(
                "--path", temporary,
                "--operation", "fixture",
                "--warn-gib", "0",
                "--hard-gib", "0",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Disk guard:", result.stdout)

    def test_impossible_threshold_blocks_without_explicit_override(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result = run_guard(
                "--path", temporary,
                "--operation", "fixture",
                "--warn-gib", "999999999",
                "--hard-gib", "999999999",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("is blocked below", result.stderr)

    def test_explicit_low_disk_override_is_visible(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            environment = os.environ.copy()
            environment["RICHMAN4_ALLOW_LOW_DISK"] = "1"
            result = run_guard(
                "--path", temporary,
                "--operation", "fixture",
                "--warn-gib", "999999999",
                "--hard-gib", "999999999",
                env=environment,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("RICHMAN4_ALLOW_LOW_DISK=1", result.stderr)


if __name__ == "__main__":
    unittest.main()
