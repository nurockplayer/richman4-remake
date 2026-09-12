#!/usr/bin/env python3
"""Steward-owned acceptance seed for Tachiko SCD M4 static god-definition mirror."""
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
PREFIX = "RICHMAN4_GODS_ORACLE="
HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "oracle.json"
EDITED_NAME = "小財神（M4驗證）"
ROW_KEYS = {"legacy_id", "display_name", "pair_legacy_id", "duration_days", "role_key"}
SOURCE_KEYS = {"name", "pair", "days", "role"}


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
    require(type(value) in (int, Decimal), f"{where}: expected Number")
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
    rows = copy.deepcopy(oracle["gods"])
    if edited:
        rows[0]["display_name"] = EDITED_NAME
    return {"gods": rows}


def normalize_projection(data: Any, require_source_order: bool = False) -> dict[str, Any]:
    exact_keys(data, {"gods"}, "$")
    rows = data["gods"]
    require(type(rows) is list and len(rows) == 15, "$.gods: expected exactly 15 rows")

    normalized: list[dict[str, Any]] = []
    ids: set[int] = set()
    for index, row in enumerate(rows):
        where = f"$.gods[{index}]"
        exact_keys(row, ROW_KEYS, where)
        legacy_id = integer(row["legacy_id"], 1, 15, where + ".legacy_id")
        require(legacy_id not in ids, f"{where}: duplicate legacy_id {legacy_id}")
        ids.add(legacy_id)
        normalized.append(
            {
                "legacy_id": legacy_id,
                "display_name": text(row["display_name"], where + ".display_name"),
                "pair_legacy_id": integer(row["pair_legacy_id"], 0, 15, where + ".pair_legacy_id"),
                "duration_days": integer(row["duration_days"], 0, MAX_SAFE_INTEGER, where + ".duration_days"),
                "role_key": text(row["role_key"], where + ".role_key"),
            }
        )

    require(ids == set(range(1, 16)), "$.gods: IDs must be exactly 1..15")
    by_id = {row["legacy_id"]: row for row in normalized}
    for row in normalized:
        pair = row["pair_legacy_id"]
        if pair == 0:
            continue
        require(pair != row["legacy_id"], f"god {row['legacy_id']}: self pair")
        require(pair in by_id, f"god {row['legacy_id']}: dangling pair {pair}")
        require(
            by_id[pair]["pair_legacy_id"] == row["legacy_id"],
            f"god {row['legacy_id']}: pair {pair} is not reciprocal",
        )

    canonical = sorted(normalized, key=lambda row: row["legacy_id"])
    if require_source_order:
        require(normalized == canonical, "$.gods: projection is not in frozen source-key order")
    return {"gods": canonical}


def projection(data: Any, oracle: dict[str, Any], edited: bool = False, source_order: bool = False) -> None:
    actual = normalize_projection(data, require_source_order=source_order)
    require(actual == oracle_projection(oracle, edited), "projection differs from frozen oracle")


def parse_source(data: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    require(git_blob_sha(data) == oracle["source_blob"], "source blob drift; Steward reconciliation required")
    source = data.decode("utf-8")
    match = re.search(
        r"^const GOD_ROWS: Dictionary = \{\n(.*?)^\}\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    require(match is not None, "GOD_ROWS source dictionary not found")
    rows: list[dict[str, Any]] = []
    seen: set[int] = set()
    for line in match.group(1).splitlines():
        if not line.strip():
            continue
        row_match = re.match(r'^\s*([0-9]+):\s*(\{.*\}),\s*$', line)
        require(row_match is not None, f"unrecognized GOD_ROWS source line: {line!r}")
        legacy_id = int(row_match.group(1))
        require(legacy_id not in seen, f"duplicate source id {legacy_id}")
        seen.add(legacy_id)
        source_row = decode(row_match.group(2))
        exact_keys(source_row, SOURCE_KEYS, f"source god {legacy_id}")
        rows.append(
            {
                "legacy_id": legacy_id,
                "display_name": source_row["name"],
                "pair_legacy_id": source_row["pair"],
                "duration_days": source_row["days"],
                "role_key": source_row["role"],
            }
        )
    result = {"gods": rows}
    projection(result, oracle, source_order=True)
    return result


def godot_projection(raw: bytes, oracle: dict[str, Any]) -> dict[str, Any]:
    lines = raw.decode("utf-8").splitlines()
    require(not any(re.match(r"^\s*(SCRIPT ERROR|ERROR):", line) for line in lines), "Godot error in log")
    payloads = [line[len(PREFIX):] for line in lines if line.startswith(PREFIX)]
    require(len(payloads) == 1, "expected exactly one Godot M4 oracle marker")
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
    require(type(rows) is list and len(rows) == 15, "$identity.rows: expected 15 rows")
    normalized: list[dict[str, Any]] = []
    entity_ids: set[str] = set()
    legacy_ids: set[int] = set()
    for index, row in enumerate(rows):
        where = f"$identity.rows[{index}]"
        exact_keys(row, {"legacy_id", "entity_id"}, where)
        legacy_id = integer(row["legacy_id"], 1, 15, where + ".legacy_id")
        entity_id = text(row["entity_id"], where + ".entity_id")
        require(legacy_id not in legacy_ids, f"{where}: duplicate legacy id")
        require(entity_id not in entity_ids, f"{where}: duplicate entity identity")
        legacy_ids.add(legacy_id)
        entity_ids.add(entity_id)
        normalized.append({"legacy_id": legacy_id, "entity_id": entity_id})
    require(legacy_ids == set(range(1, 16)), "$identity.rows: IDs must be exactly 1..15")
    return {
        "document_id": data["document_id"],
        "schema_id": data["schema_id"],
        "field_ids": data["field_ids"],
        "rows": sorted(normalized, key=lambda row: row["legacy_id"]),
    }


def compare_identity_maps(maps: list[Any]) -> None:
    require(len(maps) >= 2, "need at least two identity maps")
    normalized = [identity_map(data) for data in maps]
    require(all(data == normalized[0] for data in normalized[1:]), "identity drift across journey/reorder")


def negative_cases(baseline: dict[str, Any]) -> dict[str, bytes]:
    cases: dict[str, bytes] = {}

    def add(name: str, mutator) -> None:
        data = copy.deepcopy(baseline)
        mutator(data)
        cases[name] = json.dumps(data, ensure_ascii=False).encode("utf-8")

    add("missing_row", lambda x: x["gods"].pop())
    add("duplicate_id", lambda x: x["gods"][-1].__setitem__("legacy_id", 1))
    add("id_zero", lambda x: x["gods"][0].__setitem__("legacy_id", 0))
    add("id_high", lambda x: x["gods"][0].__setitem__("legacy_id", 16))
    add("id_fraction", lambda x: x["gods"][0].__setitem__("legacy_id", 1.5))
    add("id_boolean", lambda x: x["gods"][0].__setitem__("legacy_id", True))
    add("id_text", lambda x: x["gods"][0].__setitem__("legacy_id", "1"))
    add("self_pair", lambda x: x["gods"][0].__setitem__("pair_legacy_id", 1))
    add("pair_high", lambda x: x["gods"][0].__setitem__("pair_legacy_id", 16))
    add("pair_negative", lambda x: x["gods"][0].__setitem__("pair_legacy_id", -1))
    add("pair_fraction", lambda x: x["gods"][0].__setitem__("pair_legacy_id", 2.5))
    add("pair_boolean", lambda x: x["gods"][0].__setitem__("pair_legacy_id", True))
    add("pair_text", lambda x: x["gods"][0].__setitem__("pair_legacy_id", "2"))
    add("pair_not_reciprocal", lambda x: x["gods"][0].__setitem__("pair_legacy_id", 4))
    add("days_negative", lambda x: x["gods"][0].__setitem__("duration_days", -1))
    add("days_fraction", lambda x: x["gods"][0].__setitem__("duration_days", 7.5))
    add("days_boolean", lambda x: x["gods"][0].__setitem__("duration_days", True))
    add("days_text", lambda x: x["gods"][0].__setitem__("duration_days", "7"))
    add("days_unsafe", lambda x: x["gods"][0].__setitem__("duration_days", MAX_SAFE_INTEGER + 1))
    add("empty_name", lambda x: x["gods"][0].__setitem__("display_name", ""))
    add("name_boolean", lambda x: x["gods"][0].__setitem__("display_name", True))
    add("empty_role", lambda x: x["gods"][0].__setitem__("role_key", ""))
    add("role_null", lambda x: x["gods"][0].__setitem__("role_key", None))
    add("unknown_field", lambda x: x["gods"][0].__setitem__("portrait", "x"))
    add("runtime_leak", lambda x: x["gods"][0].__setitem__("spawnable", True))
    add("unknown_root", lambda x: x.__setitem__("initial_ids", [1, 3, 5, 7, 9, 11]))
    for field in ROW_KEYS:
        add("missing_" + field, lambda x, field=field: x["gods"][0].pop(field))

    raw = json.dumps(baseline, ensure_ascii=False).encode("utf-8")
    cases["duplicate_json_key"] = raw.replace(b'"legacy_id": 1', b'"legacy_id": 1, "legacy_id": 1', 1)
    cases["numeric_nan"] = raw.replace(b'"duration_days": 7', b'"duration_days": NaN', 1)
    cases["numeric_infinity"] = raw.replace(b'"duration_days": 7', b'"duration_days": Infinity', 1)
    cases["numeric_huge_exp"] = raw.replace(b'"duration_days": 7', b'"duration_days": 1e309', 1)
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


def candidate_acceptance(adapter: Path, cli: Path, oracle: dict[str, Any]) -> None:
    adapter, cli = adapter.resolve(), cli.resolve()
    if not adapter.is_file() or not cli.is_file():
        raise PreconditionError("M4 adapter or real Tachiko CLI is absent; not behavioral RED")
    baseline = oracle_projection(oracle)
    with tempfile.TemporaryDirectory(prefix="richman4-m4-candidate-") as folder:
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
        require(not output.is_symlink(), "positive .ro output must not be a symlink")
        require(native(cli, "validate", str(output)) == 0, "real Rust admission failed")
        project = root / "base.roproj"
        require(native(cli, "roproj", "materialize", str(output), str(project)) == 0, "materialize failed")
        require(project.is_dir() and not project.is_symlink(), "missing real .roproj")
        require(native(cli, "roproj", "validate", str(project)) == 0, ".roproj validation failed")

        def snapshot() -> dict[str, str]:
            files: dict[str, str] = {}
            for path in sorted(project.rglob("*")):
                require(not path.is_symlink(), "unexpected symlink in .roproj")
                if path.is_file():
                    files[path.relative_to(project).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
            require(bool(files), "empty .roproj")
            return files

        project_before = snapshot()
        ro_before = output.read_bytes()
        require(native(cli, "roproj", "materialize", str(output), str(project)) == 1, "existing .roproj must reject")
        require(snapshot() == project_before and output.read_bytes() == ro_before, ".roproj collision changed data")

        output.unlink()
        for name, payload in negative_cases(baseline).items():
            require(run(payload) == 1, f"{name}: expected deliberate exit 1")
            require(not output.exists() and not output.is_symlink(), f"{name}: partial output")

        output.write_bytes(b"M4 existing destination sentinel\n")
        require(run(baseline_raw) == 1, "existing .ro must reject")
        require(output.read_bytes() == b"M4 existing destination sentinel\n", "existing .ro changed")

        output.unlink()
        edited = oracle_projection(oracle, edited=True)
        require(run(json.dumps(edited, ensure_ascii=False).encode("utf-8")) == 0, "single-field edited candidate failed")
        require(native(cli, "validate", str(output)) == 0, "edited .ro failed real Rust admission")

        output.unlink()
        reordered = copy.deepcopy(baseline)
        reordered["gods"].reverse()
        require(run(json.dumps(reordered, ensure_ascii=False).encode("utf-8")) == 0, "reordered valid candidate failed")
        require(native(cli, "validate", str(output)) == 0, "reordered .ro failed real Rust admission")

    print(f"CANDIDATE_BOUNDARY_PASS: {len(negative_cases(baseline))} negatives + collisions + edited/reordered admission; not full M4 PASS")


def self_test(oracle: dict[str, Any]) -> bool:
    baseline = oracle_projection(oracle)

    class Checks(unittest.TestCase):
        def test_frozen_fixture(self) -> None:
            normalized = normalize_projection(baseline, require_source_order=True)
            self.assertEqual(normalized, baseline)
            self.assertEqual([row["legacy_id"] for row in baseline["gods"]], list(range(1, 16)))
            self.assertEqual(baseline["gods"][0]["display_name"], "小財神")
            self.assertEqual(baseline["gods"][-1]["display_name"], "死神")
            self.assertEqual(baseline["gods"][10]["duration_days"], 0)
            self.assertEqual(baseline["gods"][-1]["duration_days"], 13)

        def test_pairs(self) -> None:
            by_id = {row["legacy_id"]: row for row in baseline["gods"]}
            for legacy_id in range(1, 13):
                pair = by_id[legacy_id]["pair_legacy_id"]
                self.assertNotEqual(pair, 0)
                self.assertEqual(by_id[pair]["pair_legacy_id"], legacy_id)
            self.assertEqual([by_id[i]["pair_legacy_id"] for i in (13, 14, 15)], [0, 0, 0])

        def test_reorder_is_not_identity(self) -> None:
            reordered = copy.deepcopy(baseline)
            reordered["gods"].reverse()
            self.assertEqual(normalize_projection(reordered), baseline)
            with self.assertRaises(ValueError):
                normalize_projection(reordered, require_source_order=True)

        def test_single_field_edit_is_valid_shape(self) -> None:
            edited = oracle_projection(oracle, edited=True)
            self.assertEqual(normalize_projection(edited), edited)
            projection(edited, oracle, edited=True)

        def test_negative_corpus(self) -> None:
            for name, payload in negative_cases(baseline).items():
                with self.subTest(name=name), self.assertRaises((ValueError, json.JSONDecodeError)):
                    normalize_projection(decode(payload))

        def test_source_parser_shape(self) -> None:
            lines = ["const GOD_ROWS: Dictionary = {"]
            for row in baseline["gods"]:
                inner = {
                    "name": row["display_name"],
                    "pair": row["pair_legacy_id"],
                    "days": row["duration_days"],
                    "role": row["role_key"],
                }
                lines.append(f'\t{row["legacy_id"]}: ' + json.dumps(inner, ensure_ascii=False) + ",")
            lines.append("}")
            source = ("\n".join(lines) + "\n").encode("utf-8")
            test_oracle = copy.deepcopy(oracle)
            test_oracle["source_blob"] = git_blob_sha(source)
            self.assertEqual(parse_source(source, test_oracle), baseline)

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
                "rows": [{"legacy_id": i, "entity_id": f"god-{i}"} for i in range(1, 16)],
            }
            reordered = copy.deepcopy(identity)
            reordered["rows"].reverse()
            compare_identity_maps([identity, reordered])

        def test_committed_oracle_shape(self) -> None:
            self.assertEqual(oracle["source_blob"], "77fff4152210fae9f33d991e6653372398996948")
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
        exact_keys(oracle, {"source_blob", "gods"}, "$oracle")
        text(oracle["source_blob"], "$oracle.source_blob")
        projection({"gods": oracle["gods"]}, oracle, source_order=True)

        if args.self_test and not self_test(oracle):
            return 1
        if args.source:
            parse_source(read(args.source, SOURCE_LIMIT), oracle)
            print("SOURCE_STATIC_PASS")
        if args.godot_log:
            godot_projection(read(args.godot_log), oracle)
            print("GODOT_GODS_DATA_PASS")
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
            candidate_acceptance(args.candidate_adapter, args.tachiko_cli, oracle)
        return 0
    except PreconditionError as error:
        print(f"PRECONDITION: {error}", file=sys.stderr)
        return 2
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
