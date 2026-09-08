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


def fake_free_space_env(root: Path, gib: int) -> dict[str, str]:
    fake_bin = root / "bin"
    fake_bin.mkdir()
    available_kib = gib * 1024 * 1024
    df = fake_bin / "df"
    df.write_text(
        "#!/usr/bin/env sh\n"
        "printf '%s\\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'\n"
        f"printf '%s\\n' 'fixture 999999999 1 {available_kib} 1% /'\n",
        encoding="utf-8",
    )
    df.chmod(0o755)
    environment = os.environ.copy()
    environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
    environment.pop("RICHMAN4_DISK_WARN_GIB", None)
    environment.pop("RICHMAN4_DISK_HARD_MIN_GIB", None)
    environment.pop("RICHMAN4_ALLOW_LOW_DISK", None)
    return environment


class DiskGuardTests(unittest.TestCase):
    def test_default_policy_blocks_thirty_gib_free(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = run_guard(
                "--path", temporary,
                "--operation", "fixture",
                env=fake_free_space_env(root, 30),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("warn <60 GiB, hard <40 GiB", result.stdout)
            self.assertIn("blocked below 40 GiB free", result.stderr)

    def test_default_policy_warns_but_allows_fifty_gib_free(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = run_guard(
                "--path", temporary,
                "--operation", "fixture",
                env=fake_free_space_env(root, 50),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("warn <60 GiB, hard <40 GiB", result.stdout)
            self.assertIn("do not create another FULL asset/Godot lane", result.stderr)

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
