"""Regression tests for private asset binding and bootstrap retrieval."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "tools" / "verify_private_assets.py"
BOOTSTRAP = ROOT / "tools" / "bootstrap_private_assets.sh"


def run(command: list[str], *, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, check=check, text=True, capture_output=True)


class PrivateAssetBootstrapTests(unittest.TestCase):
    def _make_fixture(self, temporary: str) -> tuple[Path, Path, str]:
        root = Path(temporary)
        source = root / "repo" / "source" / "dfw4cskzl_136622" / "Game"
        source.mkdir(parents=True)
        payload = b"fixture original asset\n"
        (source / "map.mkf").write_bytes(payload)
        manifest = {
            "schema": "richman4.private-assets/v1",
            "version": 1,
            "source_root": "source/dfw4cskzl_136622",
            "source_name": "dfw4cskzl_136622",
            "file_count": 1,
            "source_bytes": len(payload),
            "files": [{
                "path": "Game/map.mkf",
                "size": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }],
        }
        (root / "repo" / "manifest.json").write_text(json.dumps(manifest) + "\n", encoding="utf-8")
        (root / "repo" / ".gitattributes").write_text("source/**/*.mkf filter=lfs diff=lfs merge=lfs -text\n", encoding="utf-8")
        run(["git", "init", "--initial-branch=main"], cwd=root / "repo")
        run(["git", "add", "."], cwd=root / "repo")
        run(["git", "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"], cwd=root / "repo")
        revision = run(["git", "rev-parse", "HEAD"], cwd=root / "repo").stdout.strip()
        config = root / "config.json"
        config.write_text(json.dumps({
            "schema": "richman4.private-assets-binding/v1",
            "version": 1,
            "repository": "nurockplayer/richman4-remake-assets",
            "clone_url": "https://github.com/nurockplayer/richman4-remake-assets.git",
            "revision": revision,
            "manifest": "manifest.json",
            "manifest_sha256": hashlib.sha256((root / "repo" / "manifest.json").read_bytes()).hexdigest(),
            "source_root": "source/dfw4cskzl_136622",
        }) + "\n", encoding="utf-8")
        return root / "repo", config, revision

    def test_bootstrap_clones_explicit_fixture_and_verifies_all_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, revision = self._make_fixture(temporary)
            destination = Path(temporary) / "installed"
            result = run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--destination", str(destination),
            ], cwd=ROOT)
            self.assertIn("Verified private asset revision", result.stdout)
            self.assertEqual((destination / "source/dfw4cskzl_136622/Game/map.mkf").read_bytes(), b"fixture original asset\n")
            self.assertEqual(run(["git", "-C", str(destination), "rev-parse", "HEAD"], cwd=ROOT).stdout.strip(), revision)

    def test_bootstrap_rejects_existing_destination_without_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, revision = self._make_fixture(temporary)
            destination = Path(temporary) / "installed"
            destination.mkdir()
            marker = destination / "marker"
            marker.write_text("preserve", encoding="utf-8")
            result = run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--destination", str(destination),
            ], cwd=ROOT, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("destination already exists", result.stderr)
            self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_verifier_rejects_revision_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, _ = self._make_fixture(temporary)
            binding = json.loads(config.read_text(encoding="utf-8"))
            binding["revision"] = "0" * 40
            config.write_text(json.dumps(binding) + "\n", encoding="utf-8")
            result = run(["python3", str(VERIFY), "--asset-root", str(repository), "--config", str(config)], cwd=ROOT, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("asset revision mismatch", result.stderr)

    def test_public_entrypoint_has_no_legacy_source_fallback(self) -> None:
        script = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertNotIn("Dropbox", script)
        self.assertNotIn("dfw4cskzl_136622", script)
        self.assertNotIn("/Users/", script)


if __name__ == "__main__":
    unittest.main()
