#!/usr/bin/env python3
"""Read-only, consumer-local acceptance seed; not a Tachiko runtime/exporter."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
import unittest
from pathlib import Path
from typing import Any

LIMIT = 256 * 1024
PREFIX = "RICHMAN4_CATALOG_ORACLE="
ORACLE_PATH = Path(__file__).with_name("oracle.json")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def invalid_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant: {value}")


def decode(data: bytes) -> Any:
    require(len(data) <= LIMIT, "input exceeds 256 KiB pilot limit")
    return json.loads(data.decode("utf-8"), object_pairs_hook=unique_object,
                      parse_constant=invalid_constant)


def read(path: Path) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(LIMIT + 1)
    require(len(data) <= LIMIT, f"input too large: {path.name}")
    return data


def equal(actual: Any, expected: Any, path: str = "$") -> None:
    require(type(actual) is type(expected), f"{path}: wrong type")
    if isinstance(expected, dict):
        require(actual.keys() == expected.keys(), f"{path}: missing/extra fields")
        for key in expected:
            equal(actual[key], expected[key], f"{path}.{key}")
    elif isinstance(expected, list):
        require(len(actual) == len(expected), f"{path}: wrong record count")
        for i, item in enumerate(expected):
            equal(actual[i], item, f"{path}[{i}]")
    else:
        require(actual == expected, f"{path}: value mismatch")


def expected_projection(oracle: dict[str, Any]) -> dict[str, Any]:
    result = {key: oracle[key] for key in ("card_capacity", "tool_capacity_per_type")}
    for kind in ("card", "tool"):
        result[kind + "s"] = [
            {"id": row[0], "name": row[1], "source_id": i + 1,
             "initial_supply": row[2], "price": row[3],
             "source_flags": [row[4], row[5]]}
            for i, row in enumerate(oracle[kind + "_rows"])
        ]
    return result


def qualify_source(data: bytes, oracle: dict[str, Any]) -> None:
    # Git blob identity pins both constants and their public record mapping.
    blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    require(blob == oracle["source_blob"], "source blob drift; reconcile before proceeding")
    text = data.decode("utf-8")
    for kind in ("card", "tool"):
        match = re.search(r"^const " + kind.upper() + r"_ROWS := \[\n(.*?)^\]",
                          text, re.MULTILINE | re.DOTALL)
        require(match is not None, "pinned table not found")
        rows = [decode(line.strip().removesuffix(",").encode())
                for line in match.group(1).splitlines() if line.strip()]
        equal(rows, oracle[kind + "_rows"], kind + "_rows")
    for field in ("card_capacity", "tool_capacity_per_type"):
        match = re.search(r"^const " + field.upper() + r" := ([0-9]+)$", text, re.MULTILINE)
        require(match is not None, "pinned capacity not found")
        equal(int(match.group(1)), oracle[field], field)


def godot_projection(data: bytes) -> Any:
    lines = data.decode("utf-8").splitlines()
    payloads = [line[len(PREFIX):] for line in lines if line.startswith(PREFIX)]
    require(len(payloads) == 1, "expected exactly one Godot oracle record")
    return decode(payloads[0].encode())


def repeated(a: bytes, b: bytes) -> None:
    require(a == b, "independent projection outputs are not byte-identical")


def self_test(oracle: dict[str, Any]) -> bool:
    baseline = expected_projection(oracle)

    class Checks(unittest.TestCase):
        def test_fixture_witnesses(self) -> None:
            self.assertEqual(len(baseline["cards"]), 30)
            self.assertEqual(len(baseline["tools"]), 13)
            self.assertEqual(baseline["cards"][0]["id"], "均富")
            self.assertEqual(baseline["cards"][-1]["id"], "烏龜")
            self.assertEqual(baseline["tools"][1]["price"], 30)
            self.assertEqual(baseline["tools"][-1]["price"], 250)
            self.assertEqual(sum(row["initial_supply"] == 0 for row in baseline["tools"]), 5)
            for kind in ("cards", "tools"):
                self.assertEqual(len({row["id"] for row in baseline[kind]}), len(baseline[kind]))

        def test_identity(self) -> None:
            equal(decode(json.dumps(baseline, ensure_ascii=False).encode()), baseline)

        def test_object_key_order_is_not_semantics(self) -> None:
            equal(dict(reversed(list(baseline.items()))), baseline)

        def test_duplicate_key_rejected(self) -> None:
            with self.assertRaises(ValueError):
                decode(b'{"price":30,"price":31}')

        def test_nonfinite_rejected(self) -> None:
            for value in (b'NaN', b'Infinity', b'-Infinity'):
                with self.assertRaises(ValueError):
                    decode(value)

        def test_oversize_rejected(self) -> None:
            with self.assertRaises(ValueError):
                decode(b' ' * (LIMIT + 1))

        def test_godot_log_record(self) -> None:
            line = PREFIX.encode() + json.dumps(baseline).encode() + b'\n'
            equal(godot_projection(b'Godot Engine\n' + line), baseline)
            with self.assertRaises(ValueError):
                godot_projection(line + line)
            with self.assertRaises(ValueError):
                godot_projection(b'Godot Engine\n')

        def test_repeat_checks_bytes_not_just_values(self) -> None:
            repeated(b'{}\n', b'{}\n')
            with self.assertRaises(ValueError):
                repeated(b'{}\n', b'{}')

        def test_source_drift_rejected(self) -> None:
            with self.assertRaises(ValueError):
                qualify_source(b'not the pinned source', oracle)

    # These mutants exercise the harness only; they are NOT implementation RED evidence.
    mutants = {
        "missing_row": lambda x: x["cards"].pop(),
        "duplicate_row": lambda x: x["tools"].append(x["tools"][0]),
        "same_count_duplicate": lambda x: x["cards"].__setitem__(1, x["cards"][0]),
        "row_order": lambda x: x["tools"].reverse(),
        "renamed_legacy_id": lambda x: x["cards"][0].__setitem__("id", "new-id"),
        "source_id": lambda x: x["tools"][0].__setitem__("source_id", 0),
        "price": lambda x: x["tools"][1].__setitem__("price", 31),
        "price_unit": lambda x: x["tools"][4].__setitem__("price", 3000),
        "numeric_string": lambda x: x["tools"][1].__setitem__("price", "30"),
        "boolean_number": lambda x: x["cards"][0].__setitem__("initial_supply", True),
        "fractional_number": lambda x: x["tools"][1].__setitem__("price", 30.5),
        "unnormalized_float": lambda x: x["tools"][1].__setitem__("price", 30.0),
        "zero_supply_to_null": lambda x: x["tools"][-1].__setitem__("initial_supply", None),
        "flags_swapped": lambda x: x["tools"][6].__setitem__("source_flags", [2, 1]),
        "extra_field": lambda x: x["tools"][0].__setitem__("supported", True),
        "capacity": lambda x: x.__setitem__("card_capacity", 16),
        "extra_root": lambda x: x.__setitem__("save_state", {}),
    }
    for name, mutate in mutants.items():
        def test(self: unittest.TestCase, mutate=mutate) -> None:
            actual = copy.deepcopy(baseline)
            mutate(actual)
            with self.assertRaises(ValueError):
                equal(actual, baseline)
        setattr(Checks, "test_reject_" + name, test)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Checks)
    return unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--source", type=Path, help="exact public original_inventory.gd")
    parser.add_argument("--godot-log", type=Path, help="successful source_oracle.gd stdout")
    parser.add_argument("--projection", type=Path, help="real roundtrip normalized JSON")
    parser.add_argument("--repeat", type=Path, help="second independent normalized JSON")
    parser.add_argument("--edited-projection", type=Path, help="only tool 路障 price 30 -> 31")
    args = parser.parse_args()
    if not any(vars(args).values()):
        parser.error("select at least one check; no product check runs by default")
    if args.repeat and not args.projection:
        parser.error("--repeat requires --projection")
    try:
        oracle = decode(read(ORACLE_PATH))
        expected = expected_projection(oracle)
        if args.self_test and not self_test(oracle):
            return 1
        if args.source:
            qualify_source(read(args.source), oracle)
            print("SOURCE_STATIC_PASS: pinned blob, 43 rows and capacities; not Godot execution")
        if args.godot_log:
            equal(godot_projection(read(args.godot_log)), expected)
            print("GODOT_CATALOG_DATA_PASS: check process exit and exact checkout separately")
        if args.projection:
            data = read(args.projection)
            equal(decode(data), expected)
            print("PROJECTION_DATA_PASS: producer/Rust provenance requires separate evidence")
            if args.repeat:
                other = read(args.repeat)
                equal(decode(other), expected)
                repeated(data, other)
                print("REPEAT_BYTES_PASS: independent generation must be established separately")
        if args.edited_projection:
            expected["tools"][1]["price"] = 31
            equal(decode(read(args.edited_projection)), expected)
            print("EDIT_DATA_PASS: real semantic edit/diff/save/reopen evidence still required")
        return 0
    except (ValueError, OSError, KeyError, TypeError, RecursionError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
