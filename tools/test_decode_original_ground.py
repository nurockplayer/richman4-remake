"""Synthetic GND contract tests; no original bytes or images are included."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from decode_original_ground import (
    PAYLOAD_SIZE, PIXEL_OFFSET, PLACEMENT_OFFSET, SIDE, TILE_COUNT,
    FormatError, InputError, decode_ground, decode_source, scene_objects,
)
from test_decode_original_images import make_mkf, init_git_repo
from test_import_original import make_map_payload


def fixture() -> bytes:
    data = bytearray(PAYLOAD_SIZE)
    data[:16] = b"GND\0" + struct.pack("<HHII", SIDE, SIDE, TILE_COUNT, 0)
    struct.pack_into("<3H", data, 16, 0x7C00, 0x03E0, 0x001F)
    placements = list(range(TILE_COUNT))
    placements[0], placements[1] = 1, 0
    struct.pack_into(f"<{TILE_COUNT}H", data, PLACEMENT_OFFSET, *placements)
    data[PIXEL_OFFSET + 1024:PIXEL_OFFSET + 2048] = bytes([1]) * 1024
    data[PIXEL_OFFSET + 1024 + 31 * 32 + 31] = 2
    return bytes(data)


class GroundTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.payload = fixture()

    def test_unignored_output_fails_before_creation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo = root / "repo"
            init_git_repo(repo)
            source = root / "source"
            source.mkdir()
            output = repo / "derived-scenes"
            with self.assertRaisesRegex(InputError, "ignored"):
                decode_source(source, output)
            self.assertFalse(output.exists())

    def test_scenery_uses_source_resource_and_orientation_fields(self):
        graph = bytearray(160)
        struct.pack_into("<H", graph, 28 + 26, 61)
        graph[28 + 24] = 7
        struct.pack_into("<H", graph, 56 + 52 + 32, 50)
        graph[56 + 52 + 27] = 2
        parsed = {"sections": {"landscapes": {"offset": 0, "record_size": 28},
                               "companies": {"offset": 56, "record_size": 52}},
                  "landscapes": [{"id": 1, "x": 319, "y": 990}],
                  "companies": [{"id": 1, "x": 400, "y": 500}]}
        objects = scene_objects(bytes(graph), parsed)
        self.assertEqual([(o["sprite_id"], o["direction"]) for o in objects], [(61, 1), (50, 6)])
        self.assertEqual((objects[0]["x"], objects[0]["y"]), (319, 990))

    def test_non_identity_tiles_and_pixel_orientation(self):
        ground = decode_ground(self.payload)
        chunk = ground.chunks[0]
        self.assertEqual((chunk.width, chunk.height), (2304, 2304))
        self.assertEqual(chunk.pixels[0], 1)
        self.assertEqual(chunk.pixels[32], 0)
        self.assertEqual(chunk.pixels[31 * 2304 + 31], 2)
        self.assertEqual(chunk.pixels[32 * 2304], 0)

    def test_invalid_layouts_are_rejected(self):
        for offset, replacement in [(0, b"SPR\0"), (4, struct.pack("<H", 73)),
                                    (8, struct.pack("<I", 1)),
                                    (12, struct.pack("<I", 1)),
                                    (PLACEMENT_OFFSET, struct.pack("<H", TILE_COUNT))]:
            with self.subTest(offset=offset):
                data = bytearray(self.payload)
                data[offset:offset + len(replacement)] = replacement
                with self.assertRaises(FormatError):
                    decode_ground(bytes(data))
        with self.assertRaises(FormatError):
            decode_ground(self.payload[:-1])

    def test_import_provenance_and_opaque_zero(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "source"
            game = source / "Game"
            game.mkdir(parents=True)
            graph = make_map_payload()
            archive = make_mkf([(self.payload, len(self.payload), 16, 512),
                                (graph, len(graph), 0, 0)])
            (game / "map.mkf").write_bytes(archive)
            output = Path(root) / "output"
            manifest = decode_source(source, output)
            item = manifest["maps"][0]
            self.assertEqual(item["id"], "Game:1")
            self.assertEqual(item["source_file_sha256"], hashlib.sha256(archive).hexdigest())
            self.assertEqual(item["graph_payload_sha256"], hashlib.sha256(graph).hexdigest())
            self.assertEqual(json.loads((output / "manifest.json").read_text()), manifest)
            png = (output / item["image"]["path"]).read_bytes()
            self.assertEqual(hashlib.sha256(png).hexdigest(), item["image"]["sha256"])
            # Writer emits standard PNG filter zero; inspect actual RGBA bytes.
            cursor, compressed = 8, bytearray()
            while cursor < len(png):
                length = struct.unpack_from(">I", png, cursor)[0]
                if png[cursor + 4:cursor + 8] == b"IDAT":
                    compressed.extend(png[cursor + 8:cursor + 8 + length])
                cursor += length + 12
            rgba = zlib.decompress(compressed)
            self.assertEqual(rgba[1:5], bytes([0, 255, 0, 255]))
            self.assertEqual(rgba[1 + 32 * 4:1 + 33 * 4], bytes([255, 0, 0, 255]))
            self.assertFalse((output / ".images-publish-lock").exists())
            # A later invalid source cannot replace a valid publication.
            (game / "map.mkf").write_bytes(b"invalid")
            with self.assertRaises(FormatError):
                decode_source(source, output)
            self.assertEqual(json.loads((output / "manifest.json").read_text()), manifest)
            self.assertEqual((output / item["image"]["path"]).read_bytes(), png)

    def test_source_and_output_must_not_overlap(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "source"
            source.mkdir()
            for output in [source, source / "derived", source.parent]:
                with self.assertRaises(InputError):
                    decode_source(source, output)


if __name__ == "__main__":
    unittest.main()
