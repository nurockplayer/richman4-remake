#!/usr/bin/env python3
"""M7 #188 preparation seed for the static fate-name mirror.

This checker is intentionally a qualification witness, not an adapter or
runtime implementation.  It accepts only COUNT and _NAMES from the pinned
source and rejects gameplay/runtime fields at the projection boundary.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
import unittest
from decimal import Decimal
from pathlib import Path
from typing import Any

LIMIT = 128 * 1024
SOURCE_LIMIT = 64 * 1024
MAX_SAFE_INTEGER = 9007199254740991
MIN_FATE_ID = 0
MAX_FATE_ID = 36
FATE_COUNT = 37
MAX_DISPLAY_NAME_LENGTH = 256
PREFIX = "RICHMAN4_FATE_EVENTS_ORACLE="
EXPECTED_SOURCE_BLOB = "c04741a32b41df601dc20147f143a3507a83fb17"
EXPECTED_FATE_NAMES = (
    "拆除房屋", "出售土地", "取得貸款", "銀行拒絕貸款", "存款轉移",
    "失蹤", "失蹤", "失蹤", "股票小幅出售", "股票全部出售",
    "機車故障", "汽車故障", "住院", "住院", "交通罰款",
    "交通事故", "交通事故", "繳交費用", "支付費用", "支付費用",
    "獲得獎金", "獲得獎金", "獲得獎金", "支付費用", "支付費用",
    "獲得獎金", "支付費用", "獲得獎金", "獲得獎金", "獲得獎金",
    "支付費用", "獲得獎金", "出售所有物品", "酒後駕車入獄", "違規入獄",
    "違規入獄", "違規入獄",
)
HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "oracle.json"
ROW_KEYS = {"fate_id", "display_name"}
ROOT_KEYS = {"fate_names"}
EDITED_NAME = "違規入獄（M7驗證）"
BLOCK_RE = re.compile(r"^const _NAMES := \[\n(.*?)^\]\s*$", re.MULTILINE | re.DOTALL)
COUNT_RE = re.compile(r"^const COUNT := ([0-9]+)\s*$", re.MULTILINE)
STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')


class PreconditionError(Exception):
    """An unavailable input/tool is not behavioral rejection evidence."""


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
    require(type(value) is int, f"{where}: expected integer Number")
    require(abs(value) <= MAX_SAFE_INTEGER, f"{where}: unsafe integer")
    require(minimum <= value <= maximum, f"{where}: out of range")
    return value


def display_name(value: Any, where: str) -> str:
    require(type(value) is str and bool(value.strip()), f"{where}: expected non-empty Text")
    require(len(value) <= MAX_DISPLAY_NAME_LENGTH, f"{where}: display_name is oversized")
    return value


def oracle_projection(oracle: dict[str, Any], edited: bool = False) -> dict[str, Any]:
    rows = copy.deepcopy(oracle["fate_names"])
    if edited:
        for row in rows:
            if row["fate_id"] == MAX_FATE_ID:
                row["display_name"] = EDITED_NAME
    return {"fate_names": rows}


def normalize_projection(data: Any, require_source_order: bool = False) -> dict[str, Any]:
    exact_keys(data, ROOT_KEYS, "$")
    rows = data["fate_names"]
    require(type(rows) is list and len(rows) == FATE_COUNT,
            f"$.fate_names: expected exactly {FATE_COUNT} rows")
    normalized: list[dict[str, Any]] = []
    ids: set[int] = set()
    for index, row in enumerate(rows):
        where = f"$.fate_names[{index}]"
        exact_keys(row, ROW_KEYS, where)
        fate_id = integer(row["fate_id"], MIN_FATE_ID, MAX_FATE_ID, where + ".fate_id")
        require(fate_id not in ids, f"{where}: duplicate fate_id {fate_id}")
        ids.add(fate_id)
        normalized.append({
            "fate_id": fate_id,
            "display_name": display_name(row["display_name"], where + ".display_name"),
        })
    require(ids == set(range(FATE_COUNT)), "$.fate_names: IDs must be exactly 0..36")
    canonical = sorted(normalized, key=lambda row: row["fate_id"])
    if require_source_order:
        require(normalized == canonical, "$.fate_names: not in frozen source-key order")
    return {"fate_names": canonical}


def projection(data: Any, oracle: dict[str, Any], edited: bool = False,
               source_order: bool = False) -> None:
    actual = normalize_projection(data, require_source_order=source_order)
    require(actual == oracle_projection(oracle, edited), "projection differs from frozen oracle")


def parse_names(body: str, where: str) -> list[str]:
    entries = list(STRING_RE.finditer(body))
    require(len(entries) == FATE_COUNT, f"{where}: expected exactly {FATE_COUNT} entries")
    remainder = STRING_RE.sub("", body)
    require(re.sub(r"[\s,]", "", remainder) == "",
            f"{where}: unrecognized tokens in _NAMES table")
    names: list[str] = []
    for entry in entries:
        decoded = decode(entry.group(0))
        names.append(display_name(decoded, where))
    return names


def parse_source(data: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    require(git_blob_sha(data) == oracle["source_blob"],
            "source blob drift; Steward reconciliation required")
    text = data.decode("utf-8")
    count_match = COUNT_RE.search(text)
    require(count_match is not None and int(count_match.group(1)) == FATE_COUNT,
            "COUNT source constant is not exactly 37")
    block = BLOCK_RE.search(text)
    require(block is not None, "_NAMES source array not found")
    names = parse_names(block.group(1), "_NAMES")
    result = {"fate_names": [
        {"fate_id": index, "display_name": value}
        for index, value in enumerate(names)
    ]}
    projection(result, oracle, source_order=True)
    return result


def godot_projection(raw: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    lines = raw.decode("utf-8").splitlines()
    require(not any(re.match(r"^\s*(SCRIPT ERROR|ERROR):", line) for line in lines),
            "Godot error in log")
    payloads = [line[len(PREFIX):] for line in lines if line.startswith(PREFIX)]
    require(len(payloads) == 1, "expected exactly one Godot M7 oracle marker")
    data = decode(payloads[0])
    projection(data, oracle, source_order=True)
    return data


def identity_map(data: Any) -> dict[str, Any]:
    exact_keys(data, {"document_id", "schema_id", "field_ids", "rows"}, "$identity")
    for field in ("document_id", "schema_id"):
        display_name(data[field], "$identity." + field)
    exact_keys(data["field_ids"], ROW_KEYS, "$identity.field_ids")
    field_ids = [display_name(value, "$identity.field_ids") for value in data["field_ids"].values()]
    require(len(set(field_ids)) == len(ROW_KEYS), "$identity: duplicate field identity")
    rows = data["rows"]
    require(type(rows) is list and len(rows) == FATE_COUNT,
            f"$identity.rows: expected {FATE_COUNT} rows")
    normalized: list[dict[str, Any]] = []
    ids: set[int] = set()
    entity_ids: set[str] = set()
    for index, row in enumerate(rows):
        where = f"$identity.rows[{index}]"
        exact_keys(row, {"fate_id", "entity_id"}, where)
        fate_id = integer(row["fate_id"], MIN_FATE_ID, MAX_FATE_ID, where + ".fate_id")
        entity_id = display_name(row["entity_id"], where + ".entity_id")
        require(fate_id not in ids, f"{where}: duplicate fate ID")
        require(entity_id not in entity_ids, f"{where}: duplicate entity identity")
        ids.add(fate_id)
        entity_ids.add(entity_id)
        normalized.append({"fate_id": fate_id, "entity_id": entity_id})
    require(ids == set(range(FATE_COUNT)), "$identity.rows: IDs must be exactly 0..36")
    return {
        "document_id": data["document_id"],
        "schema_id": data["schema_id"],
        "field_ids": data["field_ids"],
        "rows": sorted(normalized, key=lambda row: row["fate_id"]),
    }


def compare_identity_maps(maps: list[Any]) -> None:
    require(len(maps) >= 2, "need at least two identity maps")
    normalized = [identity_map(data) for data in maps]
    require(all(data == normalized[0] for data in normalized[1:]),
            "identity drift across journey/reorder/edit")


def negative_cases(baseline: dict[str, Any]) -> dict[str, bytes]:
    cases: dict[str, bytes] = {}

    def add(name: str, mutator) -> None:
        data = copy.deepcopy(baseline)
        mutator(data)
        cases[name] = json.dumps(data, ensure_ascii=False).encode("utf-8")

    add("missing_row", lambda x: x["fate_names"].pop())
    add("duplicate_id", lambda x: x["fate_names"][-1].__setitem__("fate_id", 0))
    add("gap_and_duplicate", lambda x: x["fate_names"][5].__setitem__("fate_id", 6))
    add("id_negative", lambda x: x["fate_names"][0].__setitem__("fate_id", -1))
    add("id_high", lambda x: x["fate_names"][0].__setitem__("fate_id", 37))
    add("id_fraction", lambda x: x["fate_names"][0].__setitem__("fate_id", 0.5))
    add("id_boolean", lambda x: x["fate_names"][0].__setitem__("fate_id", True))
    add("id_text", lambda x: x["fate_names"][0].__setitem__("fate_id", "0"))
    add("id_unsafe", lambda x: x["fate_names"][0].__setitem__("fate_id", MAX_SAFE_INTEGER + 1))
    add("empty_name", lambda x: x["fate_names"][0].__setitem__("display_name", ""))
    add("whitespace_name", lambda x: x["fate_names"][0].__setitem__("display_name", "   "))
    add("name_boolean", lambda x: x["fate_names"][0].__setitem__("display_name", True))
    add("name_number", lambda x: x["fate_names"][0].__setitem__("display_name", 0))
    add("name_null", lambda x: x["fate_names"][0].__setitem__("display_name", None))
    add("name_oversized", lambda x: x["fate_names"][0].__setitem__("display_name", "x" * (MAX_DISPLAY_NAME_LENGTH + 1)))
    leakage_fields = (
        "support", "support_status", "effect", "effects", "state", "amount",
        "raw_amount", "map_slot", "map_slot_id", "deck", "deck_order", "rng",
        "rng_seed", "eligibility", "eligible", "resolver", "resolve", "target",
        "targets", "outcome", "changes", "draw_count", "cursor", "candidate_id",
        "id", "adapter_status",
    )
    for field in leakage_fields:
        add("row_leak_" + field, lambda x, field=field: x["fate_names"][0].__setitem__(field, 0))
        add("root_leak_" + field, lambda x, field=field: x.__setitem__(field, 0))
    add("unknown_row", lambda x: x["fate_names"][0].__setitem__("unknown", 0))
    add("unknown_root", lambda x: x.__setitem__("unknown", 0))
    cases["root_not_object"] = b"[]"
    cases["rows_not_array"] = json.dumps({"fate_names": {}}, ensure_ascii=False).encode("utf-8")
    for field in ROW_KEYS:
        add("missing_" + field, lambda x, field=field: x["fate_names"][0].pop(field))
    raw = json.dumps(baseline, ensure_ascii=False).encode("utf-8")
    cases["duplicate_json_key"] = raw.replace(b'"fate_id": 0', b'"fate_id": 0, "fate_id": 0', 1)
    cases["numeric_nan"] = raw.replace(b'"fate_id": 0', b'"fate_id": NaN', 1)
    cases["numeric_infinity"] = raw.replace(b'"fate_id": 0', b'"fate_id": Infinity', 1)
    cases["numeric_huge_exp"] = raw.replace(b'"fate_id": 0', b'"fate_id": 1e309', 1)
    cases["malformed_json"] = b'{"fate_names": ['
    cases["oversized"] = b" " * (LIMIT + 1)
    return cases


def self_test(oracle: dict[str, Any]) -> bool:
    baseline = oracle_projection(oracle)

    class Checks(unittest.TestCase):
        def test_frozen_fixture(self) -> None:
            normalized = normalize_projection(baseline, require_source_order=True)
            self.assertEqual(normalized, baseline)
            self.assertEqual([row["fate_id"] for row in baseline["fate_names"]], list(range(FATE_COUNT)))
            self.assertEqual([row["display_name"] for row in baseline["fate_names"]], list(EXPECTED_FATE_NAMES))

        def test_duplicate_display_names_allowed(self) -> None:
            self.assertEqual(baseline["fate_names"][5]["display_name"], baseline["fate_names"][6]["display_name"])
            self.assertEqual(normalize_projection(baseline), baseline)

        def test_reorder_normalizes_and_identity_is_id_based(self) -> None:
            reordered = copy.deepcopy(baseline)
            reordered["fate_names"].reverse()
            self.assertEqual(normalize_projection(reordered), baseline)
            with self.assertRaises(ValueError):
                normalize_projection(reordered, require_source_order=True)

        def test_single_field_edit_keeps_identity(self) -> None:
            edited = oracle_projection(oracle, edited=True)
            self.assertEqual(normalize_projection(edited), edited)
            projection(edited, oracle, edited=True)
            self.assertEqual(tuple(row["fate_id"] for row in baseline["fate_names"]),
                             tuple(row["fate_id"] for row in edited["fate_names"]))
            self.assertEqual(baseline["fate_names"][36]["display_name"], "違規入獄")
            with self.assertRaises(ValueError):
                projection(edited, oracle)

        def test_negative_corpus(self) -> None:
            for name, payload in negative_cases(baseline).items():
                with self.subTest(name=name), self.assertRaises((ValueError, json.JSONDecodeError)):
                    normalize_projection(decode(payload))

        def test_source_parser_shape(self) -> None:
            lines = ["const COUNT := 37", "const _NAMES := ["]
            lines.extend("\t%s," % json.dumps(name, ensure_ascii=False) for name in EXPECTED_FATE_NAMES)
            lines.append("]")
            source = ("\n".join(lines) + "\n").encode("utf-8")
            test_oracle = copy.deepcopy(oracle)
            test_oracle["source_blob"] = git_blob_sha(source)
            self.assertEqual(parse_source(source, test_oracle), baseline)

        def test_malformed_source_rejected(self) -> None:
            source = 'const COUNT := 37\nconst _NAMES := [\n\t"拆除房屋",\n\tbare_identifier,\n]\n'.encode("utf-8")
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
                "rows": [{"fate_id": i, "entity_id": f"fate-{i}"} for i in range(FATE_COUNT)],
            }
            reordered = copy.deepcopy(identity)
            reordered["rows"].reverse()
            compare_identity_maps([identity, reordered])

        def test_committed_oracle_shape(self) -> None:
            self.assertEqual(oracle["source_blob"], EXPECTED_SOURCE_BLOB)
            self.assertEqual(oracle["count"], FATE_COUNT)
            self.assertEqual([row["display_name"] for row in oracle["fate_names"]], list(EXPECTED_FATE_NAMES))
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
    parser.add_argument("--candidate-adapter", type=Path,
                        help="reserved after Ready; absence is PRECONDITION_UNMET")
    parser.add_argument("--tachiko-cli", type=Path,
                        help="reserved after Ready; absence is PRECONDITION_UNMET")
    args = parser.parse_args()
    if not any((args.self_test, args.source, args.godot_log, args.projection,
                args.edited_projection, args.identity_map, args.candidate_adapter,
                args.tachiko_cli)):
        parser.error("select at least one check")
    if bool(args.candidate_adapter) != bool(args.tachiko_cli):
        parser.error("--candidate-adapter and --tachiko-cli must be provided together")
    try:
        oracle = decode(read(ORACLE_PATH))
        exact_keys(oracle, {"source_blob", "count", "fate_names"}, "$oracle")
        require(oracle["source_blob"] == EXPECTED_SOURCE_BLOB, "$oracle: source blob drift")
        require(oracle["count"] == FATE_COUNT, "$oracle: count drift")
        projection({"fate_names": oracle["fate_names"]}, oracle, source_order=True)
        if args.self_test and not self_test(oracle):
            return 1
        if args.source:
            parse_source(read(args.source, SOURCE_LIMIT), oracle)
            print("SOURCE_STATIC_PASS: pinned blob, COUNT 37 and _NAMES only")
        if args.godot_log:
            godot_projection(read(args.godot_log), oracle)
            print("GODOT_FATE_EVENTS_DATA_PASS: check process exit separately")
        if args.projection:
            projection(decode(read(args.projection)), oracle)
            print("PROJECTION_DATA_PASS: producer/Rust provenance requires separate evidence")
        if args.edited_projection:
            projection(decode(read(args.edited_projection)), oracle, edited=True)
            print("EDIT_DATA_PASS: fate_id 36 label-only edit")
        if args.identity_map:
            compare_identity_maps([decode(read(path)) for path in args.identity_map])
            print("IDENTITY_STABILITY_PASS")
        if args.candidate_adapter and args.tachiko_cli:
            raise PreconditionError("M7 adapter/Tachiko CLI are not authorized before Ready")
        return 0
    except PreconditionError as error:
        print(f"PRECONDITION_UNMET: {error}", file=sys.stderr)
        return 2
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError,
            UnicodeDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
