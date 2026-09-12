#!/usr/bin/env python3
"""Acceptance seed for the bounded Tachiko M2 character-catalog mirror."""
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

LIMIT = 128 * 1024
PREFIX = "RICHMAN4_CHARACTER_ORACLE="
ORACLE_PATH = Path(__file__).with_name("oracle.json")
EDITED_NAME = "約翰喬（M2驗證）"


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
    require(len(data) <= LIMIT, "input exceeds 128 KiB M2 seed limit")
    return json.loads(data.decode("utf-8"), object_pairs_hook=unique_object, parse_constant=invalid_constant)


def read(path: Path) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(LIMIT + 1)
    require(len(data) <= LIMIT, f"input too large: {path.name}")
    return data


def git_blob_sha(data: bytes) -> str:
    header = b"blob " + str(len(data)).encode() + b"\0"
    return hashlib.sha1(header + data).hexdigest()


def equal(actual: Any, expected: Any, path: str = "$") -> None:
    require(type(actual) is type(expected), f"{path}: wrong type")
    if isinstance(expected, dict):
        require(actual.keys() == expected.keys(), f"{path}: missing/extra fields")
        for key in expected:
            equal(actual[key], expected[key], f"{path}.{key}")
    elif isinstance(expected, list):
        require(len(actual) == len(expected), f"{path}: wrong record count")
        for index, item in enumerate(expected):
            equal(actual[index], item, f"{path}[{index}]")
    else:
        require(actual == expected, f"{path}: value mismatch")


def expected_projection(oracle: dict[str, Any]) -> dict[str, Any]:
    return {"characters": copy.deepcopy(oracle["characters"])}


def qualify_runtime_source(data: bytes, oracle: dict[str, Any]) -> None:
    require(git_blob_sha(data) == oracle["runtime_source_blob"], "runtime source blob drift; Steward reconciliation required")
    text = data.decode("utf-8")
    names_match = re.search(r"^const SETUP_CHARACTER_NAMES = \[\n(.*?)^\]", text, re.MULTILINE | re.DOTALL)
    require(names_match is not None, "SETUP_CHARACTER_NAMES not found")
    body = re.sub(r",\s*$", "", names_match.group(1).strip())
    names = json.loads("[" + body + "]")
    count_match = re.search(r"^const SETUP_CHARACTER_COUNT = ([0-9]+)$", text, re.MULTILINE)
    require(count_match is not None, "SETUP_CHARACTER_COUNT not found")
    require(int(count_match.group(1)) == 12, "character count drift")
    equal(names, [row["display_name"] for row in oracle["characters"]], "$.SETUP_CHARACTER_NAMES")


def qualify_research_source(data: bytes, oracle: dict[str, Any]) -> None:
    require(git_blob_sha(data) == oracle["research_source_blob"], "research source blob drift; Steward reconciliation required")


def godot_projection(data: bytes) -> Any:
    payloads = [line[len(PREFIX):] for line in data.decode("utf-8").splitlines() if line.startswith(PREFIX)]
    require(len(payloads) == 1, "expected exactly one Godot character oracle record")
    return decode(payloads[0].encode())


def repeated(a: bytes, b: bytes) -> None:
    require(a == b, "independent normalized character outputs are not byte-identical")


def self_test(oracle: dict[str, Any]) -> bool:
    baseline = expected_projection(oracle)

    class Checks(unittest.TestCase):
        def test_fixture_witnesses(self) -> None:
            self.assertEqual(len(baseline["characters"]), 12)
            self.assertEqual([row["legacy_id"] for row in baseline["characters"]], list(range(12)))
            self.assertEqual(baseline["characters"][0]["display_name"], "約翰喬")
            self.assertEqual(baseline["characters"][-1]["display_name"], "金貝貝")
            self.assertEqual(len({row["display_name"] for row in baseline["characters"]}), 12)

        def test_identity(self) -> None:
            equal(decode(json.dumps(baseline, ensure_ascii=False).encode()), baseline)

        def test_object_key_order_is_not_semantics(self) -> None:
            equal({"characters": baseline["characters"]}, baseline)

        def test_duplicate_key_rejected(self) -> None:
            with self.assertRaises(ValueError):
                decode(b'{"legacy_id":0,"legacy_id":1}')

        def test_nonfinite_rejected(self) -> None:
            for value in (b"NaN", b"Infinity", b"-Infinity"):
                with self.assertRaises(ValueError):
                    decode(value)

        def test_godot_log_record(self) -> None:
            line = PREFIX.encode() + json.dumps(baseline, ensure_ascii=False).encode()
            equal(godot_projection(b"Godot Engine\n" + line + b"\n"), baseline)

        def test_repeat_checks_bytes(self) -> None:
            repeated(b'{"characters":[]}\n', b'{"characters":[]}\n')
            with self.assertRaises(ValueError):
                repeated(b'{"characters":[]}\n', b'{"characters":[]}')

    mutants = {
        "missing_row": lambda x: x["characters"].pop(),
        "duplicate_row": lambda x: x["characters"].append(copy.deepcopy(x["characters"][0])),
        "row_order": lambda x: x["characters"].reverse(),
        "legacy_id": lambda x: x["characters"][0].__setitem__("legacy_id", 1),
        "id_string": lambda x: x["characters"][0].__setitem__("legacy_id", "0"),
        "name": lambda x: x["characters"][0].__setitem__("display_name", "wrong"),
        "empty_name": lambda x: x["characters"][0].__setitem__("display_name", ""),
        "extra_field": lambda x: x["characters"][0].__setitem__("portrait", "x"),
        "gameplay_leak": lambda x: x["characters"][0].__setitem__("init_cash_ratio", 50),
        "extra_root": lambda x: x.__setitem__("setup_initial_funds", [300000]),
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
    parser.add_argument("--runtime-source", type=Path)
    parser.add_argument("--research-source", type=Path)
    parser.add_argument("--godot-log", type=Path)
    parser.add_argument("--projection", type=Path)
    parser.add_argument("--repeat", type=Path)
    parser.add_argument("--edited-projection", type=Path)
    args = parser.parse_args()
    if not any(vars(args).values()):
        parser.error("select at least one check")
    if args.repeat and not args.projection:
        parser.error("--repeat requires --projection")
    try:
        oracle = decode(read(ORACLE_PATH))
        expected = expected_projection(oracle)
        if args.self_test and not self_test(oracle):
            return 1
        if args.runtime_source:
            qualify_runtime_source(read(args.runtime_source), oracle)
            print("RUNTIME_SOURCE_STATIC_PASS")
        if args.research_source:
            qualify_research_source(read(args.research_source), oracle)
            print("RESEARCH_SOURCE_PIN_PASS")
        if args.godot_log:
            equal(godot_projection(read(args.godot_log)), expected)
            print("GODOT_CHARACTER_DATA_PASS")
        if args.projection:
            data = read(args.projection)
            equal(decode(data), expected)
            print("PROJECTION_DATA_PASS")
            if args.repeat:
                other = read(args.repeat)
                equal(decode(other), expected)
                repeated(data, other)
                print("REPEAT_BYTES_PASS")
        if args.edited_projection:
            edited = copy.deepcopy(expected)
            edited["characters"][0]["display_name"] = EDITED_NAME
            equal(decode(read(args.edited_projection)), edited)
            print("EDIT_DATA_PASS")
        return 0
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
