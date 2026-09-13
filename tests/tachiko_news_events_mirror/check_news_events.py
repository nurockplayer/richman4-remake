#!/usr/bin/env python3
"""Steward-owned #186 preparation seed for the SCD M6 static common-news name mirror.

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
MAX_TEXT_BYTES = 4096
MIN_NEWS_ID = 0
MAX_NEWS_ID = 35
NEWS_COUNT = 36
PREFIX = "RICHMAN4_NEWS_EVENTS_ORACLE="
EXPECTED_SOURCE_BLOB = "d452a6b8f82668e7c4d0e8c732ca3e099bc31c90"
EXPECTED_NEWS_NAMES = (
    "監獄釋放", "監獄加刑", "醫院釋放", "醫院加護", "範圍災害", "土地查封",
    "房價上漲", "土地拍賣", "不動產獎勵", "不動產補助", "股票獎勵", "所得稅",
    "房產稅", "股票稅", "房價下跌", "住宅損壞", "行人停留", "交通停留",
    "建物降級", "土地查封", "多屋災害", "設施損壞", "銀行拒貸", "存款利息",
    "股市下跌", "股市上漲", "股市休市", "股票停牌", "解除停牌", "特殊事件",
    "企業虧損", "企業獲利", "企業大跌", "企業虧損", "企業小跌", "企業翻倍",
)
HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "oracle.json"
ROW_KEYS = {"news_id", "display_name"}
EDITED_NAME = "企業翻倍（M6驗證）"
COUNT_RE = re.compile(r"^const COUNT := ([0-9]+)\s*$", re.MULTILINE)
NAMES_BLOCK_RE = re.compile(r"^const _NAMES := \[\n(.*?)^\]\s*$", re.MULTILINE | re.DOTALL)
NAME_RE = re.compile(r'("(?:\\.|[^"\\])*")')
# Enumerated engine/environment noise that is unrelated to the frozen source read.
# Every other ERROR/SCRIPT ERROR line in the witness log is fatal.
BENIGN_LOG_ERRORS = (
    re.compile(r'^\s*ERROR: Condition "ret != noErr" is true\. Returning: ""\s*$'),
)


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
    require(len(value.encode("utf-8")) <= MAX_TEXT_BYTES, f"{where}: Text exceeds {MAX_TEXT_BYTES} bytes")
    return value


def oracle_projection(oracle: dict[str, Any], edited: bool = False) -> dict[str, Any]:
    rows = copy.deepcopy(oracle["news_names"])
    if edited:
        for row in rows:
            if row["news_id"] == MAX_NEWS_ID:
                row["display_name"] = EDITED_NAME
    return {"news_names": rows}


def normalize_projection(data: Any, require_source_order: bool = False) -> dict[str, Any]:
    exact_keys(data, {"news_names"}, "$")
    rows = data["news_names"]
    require(
        type(rows) is list and len(rows) == NEWS_COUNT,
        f"$.news_names: expected exactly {NEWS_COUNT} rows",
    )

    normalized: list[dict[str, Any]] = []
    ids: set[int] = set()
    for index, row in enumerate(rows):
        where = f"$.news_names[{index}]"
        exact_keys(row, ROW_KEYS, where)
        news_id = integer(row["news_id"], MIN_NEWS_ID, MAX_NEWS_ID, where + ".news_id")
        require(news_id not in ids, f"{where}: duplicate news_id {news_id}")
        ids.add(news_id)
        normalized.append(
            {
                "news_id": news_id,
                "display_name": text(row["display_name"], where + ".display_name"),
            }
        )

    require(ids == set(range(MIN_NEWS_ID, MAX_NEWS_ID + 1)), "$.news_names: ids must be exactly 0..35")
    canonical = sorted(normalized, key=lambda row: row["news_id"])
    if require_source_order:
        require(normalized == canonical, "$.news_names: projection is not in frozen source-key order")
    return {"news_names": canonical}


def projection(data: Any, oracle: dict[str, Any], edited: bool = False, source_order: bool = False) -> None:
    actual = normalize_projection(data, require_source_order=source_order)
    require(actual == oracle_projection(oracle, edited), "projection differs from frozen oracle")


def parse_news_names(body: str, where: str) -> list[str]:
    entries = list(NAME_RE.finditer(body))
    require(len(entries) == NEWS_COUNT, f"{where}: expected exactly {NEWS_COUNT} entries")
    remainder = NAME_RE.sub("", body)
    require(re.sub(r"[\s,]", "", remainder) == "", f"{where}: unrecognized tokens in name table")
    names: list[str] = []
    for entry in entries:
        display_name = decode(entry.group(1))
        require(type(display_name) is str, f"{where}: display name must be Text")
        names.append(display_name)
    return names


def parse_source(data: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    require(git_blob_sha(data) == oracle["source_blob"], "source blob drift; Steward reconciliation required")
    source = data.decode("utf-8")
    count_match = COUNT_RE.search(source)
    require(count_match is not None, "news COUNT constant not found")
    count = int(count_match.group(1))
    require(count == NEWS_COUNT, f"news COUNT must be {NEWS_COUNT}")
    names_match = NAMES_BLOCK_RE.search(source)
    require(names_match is not None, "_NAMES source table not found")
    names = parse_news_names(names_match.group(1), "_NAMES")
    require(len(names) == count, "news COUNT disagrees with _NAMES length")
    result = {"news_names": [{"news_id": index, "display_name": name} for index, name in enumerate(names)]}
    projection(result, oracle, source_order=True)
    return result


def godot_projection(raw: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    lines = raw.decode("utf-8").splitlines()
    for line in lines:
        if re.match(r"^\s*(SCRIPT ERROR|ERROR):", line) and not any(p.match(line) for p in BENIGN_LOG_ERRORS):
            raise ValueError(f"Godot error in log: {line.strip()}")
    payloads = [line[len(PREFIX):] for line in lines if line.startswith(PREFIX)]
    require(len(payloads) == 1, "expected exactly one Godot M6 oracle marker")
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
    require(
        type(rows) is list and len(rows) == NEWS_COUNT,
        f"$identity.rows: expected {NEWS_COUNT} rows",
    )
    normalized: list[dict[str, Any]] = []
    entity_ids: set[str] = set()
    ids: set[int] = set()
    for index, row in enumerate(rows):
        where = f"$identity.rows[{index}]"
        exact_keys(row, {"news_id", "entity_id"}, where)
        news_id = integer(row["news_id"], MIN_NEWS_ID, MAX_NEWS_ID, where + ".news_id")
        entity_id = text(row["entity_id"], where + ".entity_id")
        require(news_id not in ids, f"{where}: duplicate news id")
        require(entity_id not in entity_ids, f"{where}: duplicate entity identity")
        ids.add(news_id)
        entity_ids.add(entity_id)
        normalized.append({"news_id": news_id, "entity_id": entity_id})
    require(ids == set(range(MIN_NEWS_ID, MAX_NEWS_ID + 1)), "$identity.rows: ids must be exactly 0..35")
    return {
        "document_id": data["document_id"],
        "schema_id": data["schema_id"],
        "field_ids": data["field_ids"],
        "rows": sorted(normalized, key=lambda row: row["news_id"]),
    }


def compare_identity_maps(maps: list[Any]) -> None:
    require(len(maps) >= 2, "need at least two identity maps")
    normalized = [identity_map(data) for data in maps]
    require(all(data == normalized[0] for data in normalized[1:]), "identity drift across journey/reorder/edit")


def identity_inputs(data: Any) -> tuple[int, ...]:
    """Return the only identity inputs in the static projection."""
    return tuple(row["news_id"] for row in normalize_projection(data)["news_names"])


def negative_cases(baseline: dict[str, Any]) -> dict[str, bytes]:
    cases: dict[str, bytes] = {}

    def add(name: str, mutator) -> None:
        data = copy.deepcopy(baseline)
        mutator(data)
        cases[name] = json.dumps(data, ensure_ascii=False).encode("utf-8")

    add("missing_row", lambda x: x["news_names"].pop())
    add("duplicate_id", lambda x: x["news_names"][-1].__setitem__("news_id", 0))
    add("gap_and_duplicate", lambda x: x["news_names"][5].__setitem__("news_id", 6))
    add("id_negative", lambda x: x["news_names"][0].__setitem__("news_id", -1))
    add("id_high", lambda x: x["news_names"][0].__setitem__("news_id", 36))
    add("id_fraction", lambda x: x["news_names"][0].__setitem__("news_id", 0.5))
    add("id_boolean", lambda x: x["news_names"][0].__setitem__("news_id", True))
    add("id_text", lambda x: x["news_names"][0].__setitem__("news_id", "0"))
    add("id_unsafe", lambda x: x["news_names"][0].__setitem__("news_id", MAX_SAFE_INTEGER + 1))
    add("empty_name", lambda x: x["news_names"][0].__setitem__("display_name", ""))
    add("whitespace_name", lambda x: x["news_names"][0].__setitem__("display_name", "   "))
    add("name_oversized", lambda x: x["news_names"][0].__setitem__("display_name", "x" * (MAX_TEXT_BYTES + 1)))
    add("name_boolean", lambda x: x["news_names"][0].__setitem__("display_name", True))
    add("name_number", lambda x: x["news_names"][0].__setitem__("display_name", 0))
    add("name_null", lambda x: x["news_names"][0].__setitem__("display_name", None))
    add("unknown_field", lambda x: x["news_names"][0].__setitem__("kind", "common"))
    add("row_runtime_leak_adapter_status", lambda x: x["news_names"][0].__setitem__("adapter_status", "supported"))
    add("row_runtime_leak_id", lambda x: x["news_names"][0].__setitem__("id", 0))
    add("row_runtime_leak_name", lambda x: x["news_names"][0].__setitem__("name", "監獄釋放"))
    add("row_runtime_leak_unsupported", lambda x: x["news_names"][0].__setitem__("unsupported", False))
    add("row_gameplay_leak_order", lambda x: x["news_names"][0].__setitem__("order", []))
    add("row_gameplay_leak_cursor", lambda x: x["news_names"][0].__setitem__("cursor", 0))
    add("row_gameplay_leak_draw_count", lambda x: x["news_names"][0].__setitem__("draw_count", 0))
    add("row_gameplay_leak_last", lambda x: x["news_names"][0].__setitem__("last", {}))
    add("root_runtime_leak_catalog", lambda x: x.__setitem__("catalog", []))
    add("root_runtime_leak_news", lambda x: x.__setitem__("news", {}))
    add("root_gameplay_leak_state", lambda x: x.__setitem__("state", "richman4.runtime-news/v1"))
    add("root_gameplay_leak_count", lambda x: x.__setitem__("count", 36))
    add("unknown_root", lambda x: x.__setitem__("news_names_extra", {}))
    cases["root_not_object"] = b"[]"
    cases["rows_not_array"] = json.dumps({"news_names": {}}, ensure_ascii=False).encode("utf-8")
    for field in ROW_KEYS:
        add("missing_" + field, lambda x, field=field: x["news_names"][0].pop(field))

    raw = json.dumps(baseline, ensure_ascii=False).encode("utf-8")
    cases["duplicate_json_key"] = raw.replace(b'"news_id": 0', b'"news_id": 0, "news_id": 0', 1)
    cases["numeric_nan"] = raw.replace(b'"news_id": 0', b'"news_id": NaN', 1)
    cases["numeric_infinity"] = raw.replace(b'"news_id": 0', b'"news_id": Infinity', 1)
    cases["numeric_huge_exp"] = raw.replace(b'"news_id": 0', b'"news_id": 1e309', 1)
    cases["malformed_json"] = b'{"news_names": ['
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
        raise PreconditionError("M6 adapter or real Tachiko CLI is absent; not behavioral RED")
    baseline = oracle_projection(oracle)
    with tempfile.TemporaryDirectory(prefix="richman4-m6-candidate-") as folder:
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

    print(f"CANDIDATE_BOUNDARY_PASS: {len(negative_cases(baseline))} negatives; not full M6 PASS")


def self_test(oracle: dict[str, Any]) -> bool:
    baseline = oracle_projection(oracle)

    class Checks(unittest.TestCase):
        def test_frozen_fixture(self) -> None:
            normalized = normalize_projection(baseline, require_source_order=True)
            self.assertEqual(normalized, baseline)
            self.assertEqual([row["news_id"] for row in baseline["news_names"]], list(range(NEWS_COUNT)))
            self.assertEqual(
                [row["display_name"] for row in baseline["news_names"]],
                list(EXPECTED_NEWS_NAMES),
            )

        def test_duplicate_display_names_allowed(self) -> None:
            self.assertEqual(baseline["news_names"][5]["display_name"], baseline["news_names"][19]["display_name"])
            self.assertEqual(baseline["news_names"][30]["display_name"], baseline["news_names"][33]["display_name"])
            self.assertEqual(normalize_projection(baseline), baseline)

        def test_gap_rejected(self) -> None:
            gapped = copy.deepcopy(baseline)
            for row in gapped["news_names"]:
                row["news_id"] += 1
            with self.assertRaises(ValueError):
                normalize_projection(gapped)

        def test_reorder_is_not_identity(self) -> None:
            reordered = copy.deepcopy(baseline)
            reordered["news_names"].reverse()
            self.assertEqual(normalize_projection(reordered), baseline)
            with self.assertRaises(ValueError):
                normalize_projection(reordered, require_source_order=True)

        def test_single_field_edit_keeps_identity(self) -> None:
            edited = oracle_projection(oracle, edited=True)
            self.assertEqual(normalize_projection(edited), edited)
            projection(edited, oracle, edited=True)
            self.assertEqual(identity_inputs(baseline), identity_inputs(edited))
            self.assertEqual(oracle_projection(oracle)["news_names"][35]["display_name"], "企業翻倍")
            with self.assertRaises(ValueError):
                projection(edited, oracle)

            identity = {
                "document_id": "doc",
                "schema_id": "schema",
                "field_ids": {field: "field-" + field for field in sorted(ROW_KEYS)},
                "rows": [{"news_id": i, "entity_id": f"news-{i}"} for i in range(NEWS_COUNT)],
            }
            self.assertEqual(identity_map(identity), identity_map(copy.deepcopy(identity)))
            self.assertEqual(identity_inputs(baseline), identity_inputs(edited))

        def test_negative_corpus(self) -> None:
            for name, payload in negative_cases(baseline).items():
                with self.subTest(name=name), self.assertRaises((ValueError, json.JSONDecodeError)):
                    normalize_projection(decode(payload))

        def test_source_parser_shape(self) -> None:
            lines = ["const COUNT := 36", "const _NAMES := ["]
            for row in baseline["news_names"]:
                lines.append("\t%s," % json.dumps(row["display_name"], ensure_ascii=False))
            lines.append("]")
            source = ("\n".join(lines) + "\n").encode("utf-8")
            test_oracle = copy.deepcopy(oracle)
            test_oracle["source_blob"] = git_blob_sha(source)
            self.assertEqual(parse_source(source, test_oracle), baseline)

        def test_count_mismatch_rejected(self) -> None:
            lines = ["const COUNT := 35", "const _NAMES := ["]
            for row in baseline["news_names"]:
                lines.append("\t%s," % json.dumps(row["display_name"], ensure_ascii=False))
            lines.append("]")
            source = ("\n".join(lines) + "\n").encode("utf-8")
            test_oracle = copy.deepcopy(oracle)
            test_oracle["source_blob"] = git_blob_sha(source)
            with self.assertRaises(ValueError):
                parse_source(source, test_oracle)

        def test_malformed_source_rejected(self) -> None:
            source = 'const COUNT := 36\nconst _NAMES := [\n\t"監獄釋放",\n\tbare_identifier,\n]\n'.encode("utf-8")
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
                "rows": [{"news_id": i, "entity_id": f"news-{i}"} for i in range(36)],
            }
            reordered = copy.deepcopy(identity)
            reordered["rows"].reverse()
            edited = copy.deepcopy(identity)
            compare_identity_maps([identity, reordered, edited])

        def test_committed_oracle_shape(self) -> None:
            self.assertEqual(oracle["source_blob"], EXPECTED_SOURCE_BLOB)
            self.assertEqual(
                [row["display_name"] for row in oracle["news_names"]],
                list(EXPECTED_NEWS_NAMES),
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
        exact_keys(oracle, {"source_blob", "news_names"}, "$oracle")
        text(oracle["source_blob"], "$oracle.source_blob")
        require(oracle["source_blob"] == EXPECTED_SOURCE_BLOB, "$oracle: source blob drift")
        require(
            [row.get("display_name") for row in oracle["news_names"]] == list(EXPECTED_NEWS_NAMES),
            "$oracle: news-name values drift",
        )
        projection({"news_names": oracle["news_names"]}, oracle, source_order=True)

        if args.self_test and not self_test(oracle):
            return 1
        if args.source:
            parse_source(read(args.source, SOURCE_LIMIT), oracle)
            print("SOURCE_STATIC_PASS")
        if args.godot_log:
            godot_projection(read(args.godot_log), oracle)
            print("GODOT_NEWS_EVENTS_DATA_PASS")
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
