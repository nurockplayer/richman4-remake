"""Tests for opt-in verified private music packaging."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from package_music import package
from verify_private_assets import VerificationError


ROOT = Path(__file__).resolve().parents[1]


class PrivateMusicPackageTests(unittest.TestCase):
    def _make_fixture(self) -> tuple[Path, Path, Path, str]:
        temporary = Path(tempfile.mkdtemp())
        repository = temporary / "repo"
        source = repository / "source" / "dfw4cskzl_136622"
        music = source / "Media" / "Music"
        music.mkdir(parents=True)
        tracks = {
            "Media/Music/track01.ogg": b"tiny synthetic ogg one\n",
            "Media/Music/track02.OGG": b"tiny synthetic ogg two\n",
            "Media/Music/readme.txt": b"ignore this non-ogg file\n",
        }
        for relative, payload in tracks.items():
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
        manifest = {
            "schema": "richman4.private-assets/v1",
            "version": 1,
            "source_root": "source/dfw4cskzl_136622",
            "source_name": "dfw4cskzl_136622",
            "file_count": len(tracks),
            "source_bytes": sum(len(payload) for payload in tracks.values()),
            "files": [
                {"path": relative, "size": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
                for relative, payload in tracks.items()
            ],
        }
        manifest_path = repository / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
        subprocess.run(["git", "init", "--initial-branch=main"], cwd=repository, check=True, capture_output=True)
        subprocess.run(["git", "add", "."], cwd=repository, check=True, capture_output=True)
        subprocess.run(
            ["git", "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"],
            cwd=repository,
            check=True,
            capture_output=True,
        )
        revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
        config = temporary / "private-assets.json"
        config.write_text(
            json.dumps(
                {
                    "schema": "richman4.private-assets-binding/v1",
                    "version": 1,
                    "repository": "nurockplayer/richman4-remake-assets",
                    "clone_url": "https://github.com/nurockplayer/richman4-remake-assets.git",
                    "revision": revision,
                    "manifest": "manifest.json",
                    "manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                    "source_root": "source/dfw4cskzl_136622",
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return temporary, repository, config, revision

    def test_copies_only_verified_music_and_writes_hash_manifest(self) -> None:
        temporary, repository, config, revision = self._make_fixture()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(temporary)], check=False))
        destination = temporary / "audio"

        result = package(repository, destination, config)

        self.assertEqual(result["source_revision"], revision)
        self.assertEqual(result["file_count"], 2)
        self.assertEqual((destination / "Media/Music/track01.ogg").read_bytes(), b"tiny synthetic ogg one\n")
        self.assertEqual((destination / "Media/Music/track02.OGG").read_bytes(), b"tiny synthetic ogg two\n")
        self.assertFalse((destination / "Media/Music/readme.txt").exists())
        manifest = json.loads((destination / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema"], "richman4.audio-package/v1")
        self.assertEqual(manifest["source_revision"], revision)
        self.assertEqual([record["path"] for record in manifest["files"]], ["Media/Music/track01.ogg", "Media/Music/track02.OGG"])
        self.assertEqual(manifest["files"][0]["sha256"], hashlib.sha256(b"tiny synthetic ogg one\n").hexdigest())

    def test_rejects_tampered_audio_before_copy(self) -> None:
        temporary, repository, config, _ = self._make_fixture()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(temporary)], check=False))
        (repository / "source/dfw4cskzl_136622/Media/Music/track01.ogg").write_bytes(b"tampered\n")
        destination = temporary / "audio"

        with self.assertRaises(VerificationError):
            package(repository, destination, config)
        self.assertFalse(destination.exists())

    def test_rejects_lfs_pointer_before_copy(self) -> None:
        temporary, repository, config, _ = self._make_fixture()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(temporary)], check=False))
        pointer = b"version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 23\n"
        (repository / "source/dfw4cskzl_136622/Media/Music/track01.ogg").write_bytes(pointer)
        destination = temporary / "audio"

        with self.assertRaises(VerificationError):
            package(repository, destination, config)
        self.assertFalse(destination.exists())

    def test_rejects_symlink_in_private_source_before_copy(self) -> None:
        temporary, repository, config, _ = self._make_fixture()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(temporary)], check=False))
        link = repository / "source/dfw4cskzl_136622/Media/Music/link.ogg"
        link.symlink_to("track01.ogg")
        destination = temporary / "audio"

        with self.assertRaises(VerificationError):
            package(repository, destination, config)
        self.assertFalse(destination.exists())

    def test_rejects_manifest_path_escape_before_copy(self) -> None:
        temporary, repository, config, _ = self._make_fixture()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(temporary)], check=False))
        manifest_path = repository / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["files"][0]["path"] = "../escape.ogg"
        manifest_path.write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
        binding = json.loads(config.read_text(encoding="utf-8"))
        binding["manifest_sha256"] = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
        config.write_text(json.dumps(binding) + "\n", encoding="utf-8")
        destination = temporary / "audio"

        with self.assertRaises(VerificationError):
            package(repository, destination, config)
        self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
