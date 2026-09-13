#!/usr/bin/env python3
"""Steward-owned #184 preparation seed for the SCD M5 static map-event-name mirror.

This is a qualification seed only: no adapter, no Tachiko CLI, no runtime cutover.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path
from typing import Any

LIMIT = 128 * 1024
SOURCE_LIMIT = 64 * 1024
MAX_SAFE_INTEGER = 9007199254740991
MIN_EVENT_CODE = 0
MAX_EVENT_CODE = 16
EVENT_COUNT = 17
PREFIX = "RICHMAN4_MAP_EVENTS_ORACLE="
EXPECTED_SOURCE_BLOB = "a27ac49aba28548c5d40800b6332af00da1dec7f"
EXPECTED_EVENT_NAMES = (
    "道路", "道路", "新聞", "命運", "監獄入口", "醫院入口", "企鵝小遊戲",
    "氣球小遊戲", "接物小遊戲", "彩券", "點數 50", "點數 30", "點數 10",
    "卡片", "銀行", "商店", "魔法屋",
)
HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "oracle.json"
ROW_KEYS = {"event_code", "display_name"}
EDITED_NAME = "魔法屋（M5驗證）"
BLOCK_RE = re.compile(r"^const EVENT_NAMES := \{\n(.*?)^\}\s*$", re.MULTILINE | re.DOTALL)
ENTRY_RE = re.compile(r'([0-9]+)\s*:\s*("(?:\\.|[^"\\])*")')


class PreconditionError(Exception):
    """An unavailable tool/input is not a reproduced product rejection."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read(path: Path, limit: int = LIMIT) -> bytes:
    try:
        with path.open("rb") as stream:
            data = stream.read(limit + 1)
    except OSError as exc:
        raise PreconditionError(f"cannot read {path}: {exc}") from exc
    require(len(data) <= limit, f"{path}: input exceeds {limit} bytes")
    return data


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant: {value}")


def decode(raw: bytes | str) -> Any:
    data = raw if isinstance(raw, bytes) else raw.encode("utf-8")
    require(len(data) <= LIMIT, "JSON input too large")
    return json.loads(
        data.decode("utf-8"),
        object_pairs_hook=unique_object,
        parse_float=Decimal,
        parse_constant=reject_constant,
    )


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def exact_keys(value: Any, expected: set[str], where: str) -> None:
    require(type(value) is dict, f"{where}: expected object")
    require(set(value) == expected, f"{where}: missing/extra fields")


def integer(value: Any, minimum: int, maximum: int, where: str) -> int:
    require(type(value) in (int, Decimal), f"{where}: expected Number, not Text/Boolean/null")
    if isinstance(value, Decimal):
        require(value.is_finite(), f"{where}: non-finite Number")
    require(value == int(value), f"{where}: fractional Number")
    result = int(value)
    require(minimum <= result <= maximum, f"{where}: out of range")
    return result


def text(value: Any, where: str) -> str:
    require(type(value) is str and bool(value.strip()), f"{where}: expected non-empty Text")
    return value


def oracle_projection(oracle: dict[str, Any], edited: bool = False) -> dict[str, Any]:
    rows = copy.deepcopy(oracle["event_names"])
    if edited:
        for row in rows:
            if row["event_code"] == MAX_EVENT_CODE:
                row["display_name"] = EDITED_NAME
    return {"event_names": rows}


def normalize_projection(data: Any, require_source_order: bool = False) -> dict[str, Any]:
    exact_keys(data, {"event_names"}, "$")
    rows = data["event_names"]
    require(type(rows) is list and len(rows) == EVENT_COUNT, f"$.event_names: expected exactly {EVENT_COUNT} rows")

    normalized: list[dict[str, Any]] = []
    codes: set[int] = set()
    for index, row in enumerate(rows):
        where = f"$.event_names[{index}]"
        exact_keys(row, ROW_KEYS, where)
        event_code = integer(row["event_code"], MIN_EVENT_CODE, MAX_EVENT_CODE, where + ".event_code")
        require(event_code not in codes, f"{where}: duplicate event_code {event_code}")
        codes.add(event_code)
        normalized.append(
            {
                "event_code": event_code,
                "display_name": text(row["display_name"], where + ".display_name"),
            }
        )

    require(codes == set(range(MIN_EVENT_CODE, MAX_EVENT_CODE + 1)), "$.event_names: codes must be exactly 0..16")
    canonical = sorted(normalized, key=lambda row: row["event_code"])
    if require_source_order:
        require(normalized == canonical, "$.event_names: projection is not in frozen source-key order")
    return {"event_names": canonical}


def projection(data: Any, oracle: dict[str, Any], edited: bool = False, source_order: bool = False) -> None:
    actual = normalize_projection(data, require_source_order=source_order)
    require(actual == oracle_projection(oracle, edited), "projection differs from frozen oracle")


def parse_event_names(body: str, where: str) -> list[dict[str, Any]]:
    entries = list(ENTRY_RE.finditer(body))
    require(len(entries) == EVENT_COUNT, f"{where}: expected exactly {EVENT_COUNT} entries")
    remainder = ENTRY_RE.sub("", body)
    require(re.sub(r"[\s,]", "", remainder) == "", f"{where}: unrecognized tokens in event table")
    rows: list[dict[str, Any]] = []
    for entry in entries:
        event_code = int(entry.group(1))
        display_name = decode(entry.group(2))
        require(type(display_name) is str, f"{where}: event {event_code} name must be Text")
        rows.append({"event_code": event_code, "display_name": display_name})
    return rows


def parse_source(data: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    require(git_blob_sha(data) == oracle["source_blob"], "source blob drift; Steward reconciliation required")
    match = BLOCK_RE.search(data.decode("utf-8"))
    require(match is not None, "EVENT_NAMES source dictionary not found")
    result = {"event_names": parse_event_names(match.group(1), "EVENT_NAMES")}
    projection(result, oracle, source_order=True)
    return result


def godot_projection(raw: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    lines = raw.decode("utf-8").splitlines()
    require(not any(re.match(r"^\s*(SCRIPT ERROR|ERROR):", line) for line in lines), "Godot error in log")
    payloads = [line[len(PREFIX):] for line in lines if line.startswith(PREFIX)]
    require(len(payloads) == 1, "expected exactly one Godot M5 oracle marker")
    data = decode(payloads[0])
    projection(data, oracle, source_order=True)
    return data


def identity_map(data: Any) -> dict[str, Any]:
    exact_keys(data, {"document_id", "schema_id", "field_ids", "rows"}, "$identity")
    for field in ("document_id", "schema_id"):
        text(data[field], "$identity." + field)
    exact_keys(data["field_ids"], ROW_KEYS, "$identity.field_ids")
    field_ids = [text(value, "$identity.field_ids") for value in data["field_ids"].values()]
    require(len(set(field_ids)) == len(ROW_KEYS), "$identity: duplicate field identity")

    rows = data["rows"]
    require(type(rows) is list and len(rows) == EVENT_COUNT, f"$identity.rows: expected {EVENT_COUNT} rows")
    normalized: list[dict[str, Any]] = []
    entity_ids: set[str] = set()
    codes: set[int] = set()
    for index, row in enumerate(rows):
        where = f"$identity.rows[{index}]"
        exact_keys(row, {"event_code", "entity_id"}, where)
        event_code = integer(row["event_code"], MIN_EVENT_CODE, MAX_EVENT_CODE, where + ".event_code")
        entity_id = text(row["entity_id"], where + ".entity_id")
        require(event_code not in codes, f"{where}: duplicate event code")
        require(entity_id not in entity_ids, f"{where}: duplicate entity identity")
        codes.add(event_code)
        entity_ids.add(entity_id)
        normalized.append({"event_code": event_code, "entity_id": entity_id})
    require(codes == set(range(MIN_EVENT_CODE, MAX_EVENT_CODE + 1)), "$identity.rows: codes must be exactly 0..16")
    return {
        "document_id": data["document_id"],
        "schema_id": data["schema_id"],
        "field_ids": data["field_ids"],
        "rows": sorted(normalized, key=lambda row: row["event_code"]),
    }


def compare_identity_maps(maps: list[Any]) -> None:
    require(len(maps) >= 2, "need at least two identity maps")
    normalized = [identity_map(data) for data in maps]
    require(all(data == normalized[0] for data in normalized[1:]), "identity drift across journey/reorder/edit")


def identity_inputs(data: Any) -> tuple[int, ...]:
    """Return the only identity inputs in the static projection."""
    return tuple(row["event_code"] for row in normalize_projection(data)["event_names"])


def negative_cases(baseline: dict[str, Any]) -> dict[str, bytes]:
    cases: dict[str, bytes] = {}

    def add(name: str, mutator) -> None:
        data = copy.deepcopy(baseline)
        mutator(data)
        cases[name] = json.dumps(data, ensure_ascii=False).encode("utf-8")

    add("missing_row", lambda x: x["event_names"].pop())
    add("duplicate_code", lambda x: x["event_names"][-1].__setitem__("event_code", 0))
    add("gap_and_duplicate", lambda x: x["event_names"][5].__setitem__("event_code", 6))
    add("code_negative", lambda x: x["event_names"][0].__setitem__("event_code", -1))
    add("code_high", lambda x: x["event_names"][0].__setitem__("event_code", 17))
    add("code_fraction", lambda x: x["event_names"][0].__setitem__("event_code", 0.5))
    add("code_boolean", lambda x: x["event_names"][0].__setitem__("event_code", True))
    add("code_text", lambda x: x["event_names"][0].__setitem__("event_code", "0"))
    add("code_unsafe", lambda x: x["event_names"][0].__setitem__("event_code", MAX_SAFE_INTEGER + 1))
    add("empty_name", lambda x: x["event_names"][0].__setitem__("display_name", ""))
    add("whitespace_name", lambda x: x["event_names"][0].__setitem__("display_name", "   "))
    add("name_boolean", lambda x: x["event_names"][0].__setitem__("display_name", True))
    add("name_number", lambda x: x["event_names"][0].__setitem__("display_name", 0))
    add("name_null", lambda x: x["event_names"][0].__setitem__("display_name", None))
    add("unknown_field", lambda x: x["event_names"][0].__setitem__("kind", "rest"))
    add("row_runtime_leak_status_bits", lambda x: x["event_names"][0].__setitem__("status_bits", 0))
    add("row_runtime_leak_type_and_idx", lambda x: x["event_names"][0].__setitem__("type_and_idx", 0))
    add("row_runtime_leak_visual_index", lambda x: x["event_names"][0].__setitem__("visual_index", 0))
    add("row_gameplay_leak_owner", lambda x: x["event_names"][0].__setitem__("owner", -1))
    add("row_gameplay_leak_cost", lambda x: x["event_names"][0].__setitem__("cost", 0))
    add("root_runtime_leak_maps", lambda x: x.__setitem__("maps", []))
    add("root_gameplay_leak_schema", lambda x: x.__setitem__("schema", "richman4.runtime-map/v1"))
    add("unknown_root", lambda x: x.__setitem__("catalog", {}))
    cases["root_not_object"] = b"[]"
    cases["rows_not_array"] = json.dumps({"event_names": {}}, ensure_ascii=False).encode("utf-8")
    for field in ROW_KEYS:
        add("missing_" + field, lambda x, field=field: x["event_names"][0].pop(field))

    raw = json.dumps(baseline, ensure_ascii=False).encode("utf-8")
    cases["duplicate_json_key"] = raw.replace(b'"event_code": 0', b'"event_code": 0, "event_code": 0', 1)
    cases["numeric_nan"] = raw.replace(b'"event_code": 0', b'"event_code": NaN', 1)
    cases["numeric_infinity"] = raw.replace(b'"event_code": 0', b'"event_code": Infinity', 1)
    cases["numeric_huge_exp"] = raw.replace(b'"event_code": 0', b'"event_code": 1e309', 1)
    cases["malformed_json"] = b'{"event_names": ['
    cases["oversized"] = b" " * (LIMIT + 1)
    return cases


def invoke_candidate(adapter: Path, source: Path, output: Path) -> int:
    try:
        result = subprocess.run(
            [str(adapter), "candidate", str(source), str(output)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PreconditionError(f"candidate invocation unavailable: {exc}") from exc
    return result.returncode


def native(cli: Path, *args: str) -> int:
    try:
        result = subprocess.run(
            [str(cli), *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PreconditionError(f"Tachiko invocation unavailable: {exc}") from exc
    return result.returncode


def candidate_boundary(adapter: Path, cli: Path, oracle: dict[str, Any]) -> None:
    adapter, cli = adapter.resolve(), cli.resolve()
    if not adapter.is_file() or not cli.is_file():
        raise PreconditionError("M5 adapter or real Tachiko CLI is absent; not behavioral RED")
    baseline = oracle_projection(oracle)
    with tempfile.TemporaryDirectory(prefix="richman4-m5-candidate-") as folder:
        root = Path(folder)
        source = root / "candidate.json"
        output = root / "candidate.ro"

        def run(payload: bytes) -> int:
            source.write_bytes(payload)
            before = source.read_bytes()
            code = invoke_candidate(adapter, source, output)
            require(source.read_bytes() == before, "candidate mutated input")
            return code

        baseline_raw = json.dumps(baseline, ensure_ascii=False).encode("utf-8")
        require(run(baseline_raw) == 0 and output.is_file() and output.stat().st_size > 0, "valid candidate failed")
        require(native(cli, "validate", str(output)) == 0, "real Rust admission failed")
        project = root / "base.roproj"
        require(native(cli, "roproj", "materialize", str(output), str(project)) == 0, "materialize failed")
        require(native(cli, "roproj", "validate", str(project)) == 0, ".roproj validation failed")

        output.unlink()
        for name, payload in negative_cases(baseline).items():
            require(run(payload) == 1, f"{name}: expected deliberate exit 1")
            require(not output.exists() and not output.is_symlink(), f"{name}: partial output")

    print(f"CANDIDATE_BOUNDARY_PASS: {len(negative_cases(baseline))} negatives; not full M5 PASS")


def self_test(oracle: dict[str, Any]) -> bool:
    baseline = oracle_projection(oracle)

    class Checks(unittest.TestCase):
        def test_frozen_fixture(self) -> None:
            normalized = normalize_projection(baseline, require_source_order=True)
            self.assertEqual(normalized, baseline)
            self.assertEqual([row["event_code"] for row in baseline["event_names"]], list(range(EVENT_COUNT)))
            self.assertEqual(
                [row["display_name"] for row in baseline["event_names"]],
                list(EXPECTED_EVENT_NAMES),
            )

        def test_duplicate_display_names_allowed(self) -> None:
            self.assertEqual(baseline["event_names"][0]["display_name"], baseline["event_names"][1]["display_name"])
            self.assertEqual(normalize_projection(baseline), baseline)

        def test_gap_rejected(self) -> None:
            gapped = copy.deepcopy(baseline)
            for row in gapped["event_names"]:
                row["event_code"] += 1
            with self.assertRaises(ValueError):
                normalize_projection(gapped)

        def test_reorder_is_not_identity(self) -> None:
            reordered = copy.deepcopy(baseline)
            reordered["event_names"].reverse()
            self.assertEqual(normalize_projection(reordered), baseline)
            with self.assertRaises(ValueError):
                normalize_projection(reordered, require_source_order=True)

        def test_single_field_edit_keeps_identity(self) -> None:
            edited = oracle_projection(oracle, edited=True)
            self.assertEqual(normalize_projection(edited), edited)
            projection(edited, oracle, edited=True)
            self.assertEqual(identity_inputs(baseline), identity_inputs(edited))
            self.assertEqual(oracle_projection(oracle)["event_names"][16]["display_name"], "魔法屋")
            with self.assertRaises(ValueError):
                projection(edited, oracle)

        def test_negative_corpus(self) -> None:
            for name, payload in negative_cases(baseline).items():
                with self.subTest(name=name), self.assertRaises((ValueError, json.JSONDecodeError)):
                    normalize_projection(decode(payload))

        def test_source_parser_shape(self) -> None:
            lines = ["const EVENT_NAMES := {"]
            for row in baseline["event_names"]:
                lines.append("\t%d: %s," % (row["event_code"], json.dumps(row["display_name"], ensure_ascii=False)))
            lines.append("}")
            source = ("\n".join(lines) + "\n").encode("utf-8")
            test_oracle = copy.deepcopy(oracle)
            test_oracle["source_blob"] = git_blob_sha(source)
            self.assertEqual(parse_source(source, test_oracle), baseline)

        def test_malformed_source_rejected(self) -> None:
            source = b'const EVENT_NAMES := {\n\t0: "road",\n\t1: bare_identifier,\n}\n'
            test_oracle = copy.deepcopy(oracle)
            test_oracle["source_blob"] = git_blob_sha(source)
            with self.assertRaises(ValueError):
                parse_source(source, test_oracle)

        def test_godot_marker(self) -> None:
            raw = (PREFIX + json.dumps(baseline, ensure_ascii=False) + "\n").encode("utf-8")
            self.assertEqual(godot_projection(raw, oracle), baseline)
            for bad in (b"", raw + raw, raw + b"ERROR: failure\n"):
                with self.assertRaises(ValueError):
                    godot_projection(bad, oracle)

        def test_identity_maps(self) -> None:
            identity = {
                "document_id": "doc",
                "schema_id": "schema",
                "field_ids": {field: "field-" + field for field in sorted(ROW_KEYS)},
                "rows": [{"event_code": i, "entity_id": f"event-{i}"} for i in range(17)],
            }
            reordered = copy.deepcopy(identity)
            reordered["rows"].reverse()
            compare_identity_maps([identity, reordered])

        def test_committed_oracle_shape(self) -> None:
            self.assertEqual(oracle["source_blob"], EXPECTED_SOURCE_BLOB)
            self.assertEqual(
                [row["display_name"] for row in oracle["event_names"]],
                list(EXPECTED_EVENT_NAMES),
            )
            projection(baseline, oracle, source_order=True)

    return unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(Checks)
    ).wasSuccessful()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--godot-log", type=Path)
    parser.add_argument("--projection", type=Path)
    parser.add_argument("--edited-projection", type=Path)
    parser.add_argument("--identity-map", type=Path, action="append", default=[])
    parser.add_argument("--candidate-adapter", type=Path)
    parser.add_argument("--tachiko-cli", type=Path)
    args = parser.parse_args()
    if not any((args.self_test, args.source, args.godot_log, args.projection, args.edited_projection,
                args.identity_map, args.candidate_adapter, args.tachiko_cli)):
        parser.error("select at least one check")
    if bool(args.candidate_adapter) != bool(args.tachiko_cli):
        parser.error("--candidate-adapter and --tachiko-cli must be provided together")
    try:
        oracle = decode(read(ORACLE_PATH))
        exact_keys(oracle, {"source_blob", "event_names"}, "$oracle")
        text(oracle["source_blob"], "$oracle.source_blob")
        require(oracle["source_blob"] == EXPECTED_SOURCE_BLOB, "$oracle: source blob drift")
        require(
            [row.get("display_name") for row in oracle["event_names"]] == list(EXPECTED_EVENT_NAMES),
            "$oracle: event-name values drift",
        )
        projection({"event_names": oracle["event_names"]}, oracle, source_order=True)

        if args.self_test and not self_test(oracle):
            return 1
        if args.source:
            parse_source(read(args.source, SOURCE_LIMIT), oracle)
            print("SOURCE_STATIC_PASS")
        if args.godot_log:
            godot_projection(read(args.godot_log), oracle)
            print("GODOT_MAP_EVENTS_DATA_PASS")
        if args.projection:
            projection(decode(read(args.projection)), oracle)
            print("PROJECTION_DATA_PASS")
        if args.edited_projection:
            projection(decode(read(args.edited_projection)), oracle, edited=True)
            print("EDIT_DATA_PASS")
        if args.identity_map:
            compare_identity_maps([decode(read(path)) for path in args.identity_map])
            print("IDENTITY_STABILITY_PASS")
        if args.candidate_adapter and args.tachiko_cli:
            candidate_boundary(args.candidate_adapter, args.tachiko_cli, oracle)
        return 0
    except PreconditionError as error:
        print(f"PRECONDITION_UNMET: {error}", file=sys.stderr)
        return 2
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
