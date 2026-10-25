#!/usr/bin/env python3
"""Output-path guard for the original minigame asset preparation."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_minigame_assets import REPO_ROOT, AssetError, prepare, prepare_bomb_overlay

ZIP = Path("unread-source.zip")
MANIFEST = Path("unread-manifest.json")


class MinigameOutputGuardTests(unittest.TestCase):
    def test_output_inside_worktree_is_refused_before_any_read(self):
        for builder in (
            lambda output: prepare(ZIP, output, MANIFEST, Path("grid.json"), Path("catching.json")),
            lambda output: prepare_bomb_overlay(ZIP, output, MANIFEST),
        ):
            output = REPO_ROOT / "build" / "minigame-output-guard"
            with self.assertRaises(AssetError) as raised:
                builder(output)
            self.assertIn("work tree", str(raised.exception))
            self.assertFalse(output.exists())

    def test_nested_and_dotdot_worktree_paths_are_refused(self):
        for output in (REPO_ROOT / "images" / "minigame", REPO_ROOT / "build" / ".." / "assets-out"):
            with self.assertRaises(AssetError):
                prepare_bomb_overlay(ZIP, output, MANIFEST)
            self.assertFalse(output.exists())

    def test_worktree_root_itself_is_refused(self):
        with self.assertRaises(AssetError):
            prepare_bomb_overlay(ZIP, REPO_ROOT, MANIFEST)


if __name__ == "__main__":
    unittest.main()
