"""Synthetic bounded S04 export coverage; no third-party assets in fixtures."""
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import original_ui_assets as assets
from decode_original_images import FormatError, parse_mkf
from test_monthly_ui_assets import MonthlyUiAssetTests, make_mkf, make_smp_chunks

class TrusteeUiAssetTests(unittest.TestCase):
    def archive(self, count):
        baseline = parse_mkf(Path("fixture"), MonthlyUiAssetTests._panel_archive())
        entries = [(baseline.data[e.payload_offset:e.payload_end], e.uncompressed_size,
                    e.image_data_offset, e.image_data_size) for e in baseline.entries]
        payload = make_smp_chunks(count)
        entries.append((payload, len(payload), 12 + count * 12, 2 * count))
        return make_mkf(entries)

    def test_both_edition_export_and_identity(self):
        for edition in ["Game", "MultiverseJourney"]:
            with tempfile.TemporaryDirectory() as folder:
                source = Path(folder) / edition
                source.mkdir()
                (source / "Panel.mkf").write_bytes(self.archive(18))
                group = assets.export_ui_resources(edition, source, Path(folder) / "stage")
                self.assertIn("77", group["Panel"]["resources"])
                resource = group["Panel"]["resources"]["77"]
                self.assertEqual(resource["source"]["edition"], edition)
                self.assertEqual(set(resource["chunks"]), {str(i) for i in range(18)})

    def test_partial_trustee_atlas_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)
            (source / "Panel.mkf").write_bytes(self.archive(17))
            with self.assertRaises(FormatError):
                assets.export_ui_resources("Game", source, source / "stage")

if __name__ == "__main__":
    unittest.main()
