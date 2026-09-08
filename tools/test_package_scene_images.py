"""Private packaging must not copy unrelated files or corrupt scene images."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from decode_original_images import VisualChunk, VisualResource, write_png
from package_scene_images import validate


class PackageSceneTests(unittest.TestCase):
    def test_referenced_png_integrity_and_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image = root / "images" / "test.png"
            chunk = VisualChunk(0, 4, 4, 0, 0, bytes(16))
            visual = VisualResource("SPR", 1, 0, bytes(512), (chunk,))
            write_png(image, chunk, visual, pixel_format="rgb555")
            record = {"path": "images/test.png", "width": 4, "height": 4, "sha256": hashlib.sha256(image.read_bytes()).hexdigest()}
            manifest = {"schema": "richman4.scene-images/v1", "characters": {},
                        "maps": [{"world_rect": {"x": 0, "y": 0, "width": 2304, "height": 2304}, "image": record}]}
            path = root / "manifest.json"
            path.write_text(json.dumps(manifest))
            self.assertEqual(validate(path)[1], [Path("images/test.png")])
            for multiplier in (2, 4):
                chunk = VisualChunk(0, 4 * multiplier, 4 * multiplier, 0, 0, bytes(16 * multiplier * multiplier))
                write_png(image, chunk, VisualResource("SPR", 1, 0, bytes(512), (chunk,)), pixel_format="rgb555")
                record.update(width=4 * multiplier, height=4 * multiplier, sha256=hashlib.sha256(image.read_bytes()).hexdigest())
                path.write_text(json.dumps(manifest))
                self.assertEqual(validate(path)[0]["maps"][0]["world_rect"]["width"], 2304)
            record["path"] = "images/../../elsewhere.png"
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "unsafe"):
                validate(path)
            record["path"] = "images/test.png"
            path.write_text(json.dumps(manifest))
            image.write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                validate(path)
