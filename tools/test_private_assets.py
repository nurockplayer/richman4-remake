"""Regression tests for private asset binding and bootstrap retrieval."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "tools" / "verify_private_assets.py"
BOOTSTRAP = ROOT / "tools" / "bootstrap_private_assets.sh"


def run(
    command: list[str],
    *,
    cwd: Path,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, check=check, text=True, capture_output=True, env=env)


def bootstrap_env() -> dict[str, str]:
    environment = os.environ.copy()
    environment.update({
        "RICHMAN4_DISK_WARN_GIB": "0",
        "RICHMAN4_DISK_HARD_MIN_GIB": "0",
    })
    return environment


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
            ], cwd=ROOT, env=bootstrap_env())
            self.assertIn("Verified private asset revision", result.stdout)
            self.assertEqual((destination / "source/dfw4cskzl_136622/Game/map.mkf").read_bytes(), b"fixture original asset\n")
            self.assertEqual(run(["git", "-C", str(destination), "rev-parse", "HEAD"], cwd=ROOT).stdout.strip(), revision)

    def test_bootstrap_reuses_existing_verified_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, revision = self._make_fixture(temporary)
            destination = Path(temporary) / "installed"
            command = [
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--destination", str(destination),
            ]
            run(command, cwd=ROOT, env=bootstrap_env())
            second = run(command, cwd=ROOT, env=bootstrap_env())
            self.assertIn("Reusing verified private assets", second.stdout)
            self.assertEqual(run(["git", "-C", str(destination), "rev-parse", "HEAD"], cwd=ROOT).stdout.strip(), revision)

    def test_default_cache_layout_creates_only_a_worktree_link(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, revision = self._make_fixture(temporary)
            cache_root = Path(temporary) / "cache"
            worktree_link = Path(temporary) / "worktree" / ".local" / "private-assets"
            result = run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--cache-root", str(cache_root),
                "--link", str(worktree_link),
            ], cwd=ROOT, env=bootstrap_env())
            expected = cache_root / "private-assets" / revision
            self.assertTrue(worktree_link.is_symlink())
            self.assertEqual(worktree_link.resolve(), expected.resolve())
            self.assertIn("Worktree private asset link", result.stdout)
            self.assertEqual((expected / "source/dfw4cskzl_136622/Game/map.mkf").read_bytes(), b"fixture original asset\n")

    def test_default_cache_adopts_verified_legacy_worktree_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, revision = self._make_fixture(temporary)
            worktree_path = Path(temporary) / "worktree" / ".local" / "private-assets"
            worktree_path.parent.mkdir(parents=True)
            run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--destination", str(worktree_path),
            ], cwd=ROOT, env=bootstrap_env())
            self.assertTrue(worktree_path.is_dir())

            cache_root = Path(temporary) / "cache"
            result = run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--cache-root", str(cache_root),
                "--link", str(worktree_path),
            ], cwd=ROOT, env=bootstrap_env())
            expected = cache_root / "private-assets" / revision
            self.assertIn("Adopted verified worktree-local private assets", result.stdout)
            self.assertTrue(worktree_path.is_symlink())
            self.assertEqual(worktree_path.resolve(), expected.resolve())
            self.assertEqual((expected / "source/dfw4cskzl_136622/Game/map.mkf").read_bytes(), b"fixture original asset\n")

    def test_bootstrap_rejects_same_physical_destination_and_link_without_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, revision = self._make_fixture(temporary)
            temporary_root = Path(temporary)
            real_parent = temporary_root / "real-parent"
            real_parent.mkdir()
            checkout = real_parent / "private-assets"
            run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--destination", str(checkout),
            ], cwd=ROOT, env=bootstrap_env())
            payload_path = checkout / "source/dfw4cskzl_136622/Game/map.mkf"
            before = payload_path.read_bytes()

            alias_parent = temporary_root / "alias-parent"
            alias_parent.symlink_to(real_parent, target_is_directory=True)
            result = run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--destination", str(alias_parent / "private-assets"),
                "--link", str(checkout),
            ], cwd=ROOT, check=False, env=bootstrap_env())

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("destination/link paths overlap", result.stderr)
            self.assertTrue(checkout.is_dir())
            self.assertFalse(checkout.is_symlink())
            self.assertEqual(payload_path.read_bytes(), before)
            self.assertEqual(run(["git", "-C", str(checkout), "rev-parse", "HEAD"], cwd=ROOT).stdout.strip(), revision)

    def test_bootstrap_rejects_invalid_existing_destination_without_overwrite(self) -> None:
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
            ], cwd=ROOT, check=False, env=bootstrap_env())
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("existing shared cache failed verification", result.stderr)
            self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_bootstrap_rejects_invalid_destination_created_during_publish(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, revision = self._make_fixture(temporary)
            temporary_root = Path(temporary)
            destination = temporary_root / "installed"
            fake_bin = temporary_root / "bin"
            fake_bin.mkdir()
            real_git = subprocess.check_output(["/usr/bin/which", "git"], text=True).strip()
            wrapper = fake_bin / "git"
            wrapper.write_text(
                "#!/usr/bin/env python3\n"
                "import os\n"
                "from pathlib import Path\n"
                "import subprocess\n"
                "import sys\n"
                "result = subprocess.run([os.environ['PRIVATE_ASSET_REAL_GIT'], *sys.argv[1:]])\n"
                "if result.returncode == 0 and sys.argv[1:2] == ['clone']:\n"
                "    destination = Path(os.environ['PRIVATE_ASSET_RACE_DESTINATION'])\n"
                "    destination.mkdir()\n"
                "    (destination / 'marker').write_text('race', encoding='utf-8')\n"
                "sys.exit(result.returncode)\n",
                encoding="utf-8",
            )
            wrapper.chmod(0o755)
            environment = bootstrap_env()
            environment.update({
                "PATH": f"{fake_bin}:{environment['PATH']}",
                "PRIVATE_ASSET_REAL_GIT": real_git,
                "PRIVATE_ASSET_RACE_DESTINATION": str(destination),
            })
            result = run([
                "bash", str(BOOTSTRAP),
                "--config", str(config),
                "--repo-url", str(repository),
                "--revision", revision,
                "--destination", str(destination),
            ], cwd=ROOT, check=False, env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("shared cache appeared during bootstrap but is not the verified pinned source", result.stderr)
            self.assertEqual((destination / "marker").read_text(encoding="utf-8"), "race")
            self.assertFalse((destination / "repository").exists())

    def test_verifier_rejects_manifest_path_case_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository, config, _ = self._make_fixture(temporary)
            manifest_path = repository / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["files"][0]["path"] = "Game/Map.mkf"
            manifest_path.write_text(json.dumps(manifest) + "\n", encoding="utf-8")
            binding = json.loads(config.read_text(encoding="utf-8"))
            binding["manifest_sha256"] = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
            config.write_text(json.dumps(binding) + "\n", encoding="utf-8")
            result = run([
                "python3", str(VERIFY),
                "--asset-root", str(repository),
                "--config", str(config),
            ], cwd=ROOT, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest path does not match Git tree exactly", result.stderr)

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
