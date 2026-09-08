#!/usr/bin/env python3
"""Small stdlib-only regression tests for the local original-asset importer."""

from __future__ import annotations

import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_original import (  # noqa: E402
    FormatError,
    import_source,
    parse_map_payload,
    parse_mkf,
)


def make_mkf(payloads: list[bytes], *, stored_sizes: list[int] | None = None) -> bytes:
    """Build the documented container shape for parser-only fixtures."""

    if stored_sizes is None:
        stored_sizes = [len(payload) for payload in payloads]
    if len(stored_sizes) != len(payloads):
        raise ValueError("stored_sizes must match payload count")
    body = bytearray(struct.pack("<I", 0))
    starts: list[int] = []
    for payload, stored_size in zip(payloads, stored_sizes):
        starts.append(len(body))
        stored_payload = payload[:stored_size]
        body.extend(struct.pack("<4I", len(payload), stored_size, 0, 0))
        body.extend(stored_payload)
    table_offset = len(body)
    body[0:4] = struct.pack("<I", table_offset)
    body.extend(struct.pack(f"<{len(starts)}I", *starts))
    return bytes(body)


def make_map_payload() -> bytes:
    counts = {
        "nodes": 1,
        "lands": 1,
        "facilities": 1,
        "companies": 1,
        "landscapes": 1,
    }
    offsets = {
        "nodes": 40,
        "lands": 120,
        "facilities": 224,
        "companies": 336,
        "landscapes": 440,
    }
    payload = bytearray(496)
    struct.pack_into(
        "<10I",
        payload,
        0,
        counts["nodes"],
        offsets["nodes"],
        counts["lands"],
        offsets["lands"],
        counts["facilities"],
        offsets["facilities"],
        counts["companies"],
        offsets["companies"],
        counts["landscapes"],
        offsets["landscapes"],
    )

    # Every table has the original dummy record at index 0.
    node = offsets["nodes"] + 40
    struct.pack_into("<hh", payload, node, -3, 7)
    struct.pack_into("<4H", payload, node + 24, 1, 0, 0, 0)
    struct.pack_into("<2H", payload, node + 32, 2001, 9)
    struct.pack_into("<I", payload, node + 36, 0x8000000B)
    land = offsets["lands"] + 52
    payload[land : land + 4] = struct.pack("<HH", 100, 200)
    payload[land + 4 : land + 10] = "台北市".encode("cp950")
    payload[land + 23] = 2
    payload[land + 24] = 1
    payload[land + 25] = 0
    payload[land + 26] = 3
    struct.pack_into("<HH", payload, land + 28, 500, 2500)
    struct.pack_into("<6H", payload, land + 32, 500, 1200, 3000, 7500, 16000, 30000)
    facility = offsets["facilities"] + 56
    payload[facility : facility + 4] = struct.pack("<HH", 300, 400)
    payload[facility + 4 : facility + 8] = b"BANK"
    payload[facility + 24] = 4
    payload[facility + 25] = 1
    struct.pack_into("<HH", payload, facility + 34, 800, 100)
    company = offsets["companies"] + 52
    payload[company : company + 4] = struct.pack("<HH", 500, 600)
    payload[company + 24] = 2
    payload[company + 26] = 11
    struct.pack_into("<H", payload, company + 34, 75)
    landscape = offsets["landscapes"] + 28
    payload[landscape : landscape + 4] = struct.pack("<HH", 700, 800)
    payload[landscape + 4 : landscape + 8] = b"CITY"
    return bytes(payload)


class ImportOriginalTests(unittest.TestCase):
    def test_mkf_index_and_entry_span(self) -> None:
        data = make_mkf([b"abc", b"012345"])
        archive = parse_mkf(Path("fixture.mkf"), data)
        self.assertEqual(archive.table_offset, 4 + 16 + 3 + 16 + 6)
        self.assertEqual([entry.offset for entry in archive.entries], [4, 23])
        self.assertEqual(archive.payload(archive.entries[1], decoded=True), b"012345")

    def test_mkf_rejects_wrong_stored_span(self) -> None:
        data = bytearray(make_mkf([b"abc"]))
        # The header claims four stored bytes while the index span has three.
        struct.pack_into("<I", data, 8, 4)
        with self.assertRaises(FormatError):
            parse_mkf(Path("bad.mkf"), bytes(data))

    def test_map_records_and_cp950_round_trip(self) -> None:
        parsed = parse_map_payload(make_map_payload(), edition="fixture", entry_index=7)
        self.assertEqual(parsed["counts"], {
            "companies": 1,
            "facilities": 1,
            "lands": 1,
            "landscapes": 1,
            "nodes": 1,
        })
        self.assertEqual(parsed["nodes"][0]["adjacent"], [1])
        self.assertEqual(parsed["nodes"][0]["category"], "land")
        self.assertEqual(parsed["nodes"][0]["field_0x22"], 9)
        self.assertEqual(parsed["nodes"][0]["visual_index"], 9)
        self.assertEqual(parsed["nodes"][0]["status_bits"], 0x8000000B)
        self.assertEqual(parsed["nodes"][0]["event_code"], 11)
        self.assertEqual(parsed["lands"][0]["display_name"], "台北市")
        self.assertEqual(parsed["lands"][0]["display_name_encoding"], "cp950")
        self.assertEqual(parsed["lands"][0]["land_price"], 500)
        self.assertEqual(parsed["lands"][0]["house_price"], 2500)
        self.assertEqual(parsed["lands"][0]["price_per_level"], 2500)
        self.assertEqual(
            parsed["lands"][0]["rent_by_level"], [500, 1200, 3000, 7500, 16000, 30000]
        )
        self.assertEqual(parsed["facilities"][0]["facility_type"], 4)
        self.assertEqual(parsed["facilities"][0]["land_price"], 800)
        self.assertEqual(parsed["facilities"][0]["house_price"], 100)
        self.assertEqual(parsed["facilities"][0]["price_per_level"], 100)
        self.assertEqual(parsed["companies"][0]["commerce_type"], 11)
        self.assertEqual(parsed["landscapes"][0]["display_name"], "CITY")
        self.assertEqual(parsed["trailing_bytes"], 0)

    def test_import_source_writes_deterministic_local_catalog(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "installation"
            edition = source / "Game"
            edition.mkdir(parents=True)
            (edition / "map.mkf").write_bytes(make_mkf([b"not-a-map", make_map_payload()]))
            (edition / "Midi.txt").write_text("RICH08.MID\n", encoding="ascii")
            output_a = Path(temporary) / "out-a"
            output_b = Path(temporary) / "out-b"
            first = import_source(source, output_a, extract_map_payloads=True)
            second = import_source(source, output_b, extract_map_payloads=True)
            self.assertEqual(first, second)
            self.assertEqual(
                (output_a / "maps/catalog.json").read_bytes(),
                (output_b / "maps/catalog.json").read_bytes(),
            )
            catalog = json.loads((output_a / "maps/catalog.json").read_text())
            self.assertEqual(catalog["count"], 1)
            self.assertEqual(catalog["maps"][0]["entry_index"], 1)
            self.assertTrue((output_a / "raw/Game/map-01.bin").is_file())


if __name__ == "__main__":
    unittest.main()
