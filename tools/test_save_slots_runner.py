"""Keep focused save-slot checks wired into the repository runner."""

from pathlib import Path
import unittest


class SaveSlotsRunnerTests(unittest.TestCase):
    def test_focused_save_slot_checks_are_run(self):
        runner = Path(__file__).resolve().parents[1] / "tools" / "check.sh"
        runner_text = runner.read_text(encoding="utf-8")
        expected_commands = (
            'run_checked "$GODOT_BIN" --headless --path . --script tests/save_slots.gd',
            'run_checked "$GODOT_BIN" --headless --path . --script tests/source_save_panel.gd',
        )
        for command in expected_commands:
            with self.subTest(command=command):
                self.assertEqual(runner_text.count(command), 1)


if __name__ == "__main__":
    unittest.main()
