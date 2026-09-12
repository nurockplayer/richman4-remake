#!/usr/bin/env python3
"""Steward-owned #176 acceptance; no importer, evaluator or runtime cutover."""
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

KINDS = ("initial_fund", "day_limit", "wealth_multiplier")
TABLES = ((300000, 200000, 100000, 50000, 30000, 10000),
          (0, 730, 365, 182, 91, 30), (0, 100, 50, 10, 5, 3))
SYMBOLS = ("SETUP_INITIAL_FUNDS", "SETUP_DAY_LIMITS", "SETUP_WEALTH_MULTIPLIERS")
SOURCE_BLOB = "18b69b0ffe167085329f3363b958b0b561e70902"
RESEARCH_BLOB = "0f8aa4666aefec90aed8caefeca591e86b742b46"
LIMIT = 128 * 1024
SOURCE_LIMIT = 2 * 1024 * 1024  # MainUI is source, not a tiny evidence JSON.
MAX_INTEGER = 9007199254740991
MARKER = "RICHMAN4_SETUP_ORACLE="
HERE = Path(__file__).resolve().parent


class PreconditionError(Exception):
    """An absent input/tool is not a reproduced product rejection."""


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


def unique_object(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant: {value}")


def loads(raw: bytes | str):
    require(len(raw if isinstance(raw, bytes) else raw.encode("utf-8")) <= LIMIT, "JSON input too large")
    # Decimal preserves the original token before any possible binary64 rounding.
    return json.loads(raw, object_pairs_hook=unique_object, parse_float=Decimal,
                      parse_constant=reject_constant)


def keys(value, expected: set[str]) -> None:
    require(type(value) is dict and set(value) == expected, "unexpected object keys/type")


def integer(value, maximum: int = MAX_INTEGER) -> int:
    require(type(value) in (int, Decimal), "expected a Number, not Text/Boolean/null")
    if isinstance(value, Decimal):
        require(value.is_finite(), "non-finite Number")
    require(0 <= value <= maximum and value == int(value), "out-of-range/fractional Number")
    return int(value)


def oracle(edited: bool = False) -> dict:
    rows = [{"kind": kind, "legacy_index": index, "value": value}
            for kind, table in zip(KINDS, TABLES) for index, value in enumerate(table)]
    if edited:
        rows[11]["value"] = 31
    return {"setup_options": rows}


def shape(data: dict, ordered: bool = False) -> dict:
    keys(data, {"setup_options"})
    rows = data["setup_options"]
    require(type(rows) is list and len(rows) == 18, "expected exactly 18 records")
    normalized, seen = [], set()
    for row in rows:
        keys(row, {"kind", "legacy_index", "value"})
        kind = row["kind"]
        require(type(kind) is str and kind in KINDS, "unknown kind")
        index = integer(row["legacy_index"], 5)
        require((kind, index) not in seen, "duplicate kind/index")
        seen.add((kind, index))
        normalized.append({"kind": kind, "legacy_index": index, "value": integer(row["value"])})
    canonical = sorted(normalized, key=lambda row: (KINDS.index(row["kind"]), row["legacy_index"]))
    if ordered:
        require(normalized == canonical, "projection is not in frozen source-key order")
    return {"setup_options": canonical}


def projection(data: dict, edited: bool = False) -> None:
    require(shape(data, ordered=True) == oracle(edited), "projection differs from independent oracle")


def parse_source(text: str) -> dict:
    rows = []
    for kind, symbol in zip(KINDS, SYMBOLS):
        matches = re.findall(r"^const " + symbol + r" := (\[[^\n]*\])\s*$", text, re.M)
        require(len(matches) == 1, f"missing/ambiguous source declaration: {symbol}")
        table = loads(matches[0])
        require(type(table) is list and len(table) == 6, "source table length")
        rows.extend({"kind": kind, "legacy_index": i, "value": v} for i, v in enumerate(table))
    return {"setup_options": rows}


def pinned(path: Path, blob: str, limit: int) -> str:
    raw = read(path, limit)
    actual = hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
    require(actual == blob, f"source drift: {path}: {actual} != {blob}")
    return raw.decode("utf-8")


def witness(raw: bytes, exit_code: int) -> None:
    require(exit_code == 0, "Godot did not exit successfully")
    lines = raw.decode("utf-8").splitlines()
    require(not any(re.match(r"^\s*(SCRIPT ERROR|ERROR):", line) for line in lines), "Godot error in log")
    payloads = [line[len(MARKER):] for line in lines if line.startswith(MARKER)]
    require(len(payloads) == 1, "expected exactly one Godot witness marker")
    projection(loads(payloads[0]))


def identities(data: dict) -> dict:
    keys(data, {"document_id", "schema_id", "field_ids", "rows"})
    for name in ("document_id", "schema_id"):
        require(type(data[name]) is str and bool(data[name].strip()), f"missing {name}")
    keys(data["field_ids"], {"kind", "legacy_index", "value"})
    fields = list(data["field_ids"].values())
    require(all(type(x) is str and bool(x.strip()) for x in fields), "invalid field identity")
    require(len(set(fields)) == 3, "duplicate field identity")
    require(type(data["rows"]) is list and len(data["rows"]) == 18, "missing persisted rows")
    rows, entity_ids = [], set()
    for row in data["rows"]:
        keys(row, {"kind", "legacy_index", "entity_id"})
        entity_id = row["entity_id"]
        require(type(entity_id) is str and bool(entity_id.strip()), "invalid entity identity")
        require(entity_id not in entity_ids, "duplicate entity identity")
        entity_ids.add(entity_id)
        rows.append({"kind": row["kind"], "legacy_index": row["legacy_index"], "value": 0})
    shape({"setup_options": rows})
    return {**data, "rows": sorted(data["rows"], key=lambda r: (KINDS.index(r["kind"]), int(r["legacy_index"])))}


def compare_identities(maps: list[dict]) -> None:
    require(len(maps) == 6, "need both import maps and four persisted maps")
    checked = [identities(data) for data in maps]
    require(all(data == checked[0] for data in checked[1:]), "persisted/import identity mismatch")


def negative_cases() -> dict[str, str]:
    cases = {}
    for name, field, value in (
        ("unknown_kind", "kind", "cash_ratio"), ("index_high", "legacy_index", 6),
        ("index_negative", "legacy_index", -1), ("index_fraction", "legacy_index", 0.5),
        ("index_boolean", "legacy_index", True), ("index_text", "legacy_index", "0"),
        ("value_text", "value", "300000"), ("value_boolean", "value", True),
        ("value_null", "value", None), ("value_fraction", "value", 0.5),
        ("value_negative", "value", -1), ("unsafe_integer", "value", 9007199254740993),
        ("unknown_field", "extra", 1), ("gameplay_leak", "init_cash_ratio", 50),
    ):
        data = oracle()
        data["setup_options"][0][field] = value
        cases[name] = json.dumps(data)
    missing = oracle()
    missing["setup_options"].pop()
    cases["missing_record"] = json.dumps(missing)
    duplicate = oracle()
    duplicate["setup_options"][-1] = copy.deepcopy(duplicate["setup_options"][0])
    cases["duplicate_identity"] = json.dumps(duplicate)
    for field in ("kind", "legacy_index", "value"):
        data = oracle()
        del data["setup_options"][0][field]
        cases["missing_" + field] = json.dumps(data)
    cases["unknown_root"] = json.dumps({**oracle(), "default_selection": 1})
    raw = json.dumps(oracle())
    cases["duplicate_json_key"] = raw.replace('"value": 300000', '"value": 300000, "value": 300000', 1)
    for token in ("NaN", "Infinity", "-Infinity", "1e309", "9007199254740993.0", "300000.0000000000000001"):
        cases["numeric_" + token] = raw.replace('"value": 300000', '"value": ' + token, 1)
    cases["oversized"] = " " * LIMIT + raw
    return cases


def candidate_acceptance(adapter: Path, cli: Path) -> None:
    adapter, cli = adapter.resolve(), cli.resolve()
    if not adapter.is_file() or not cli.is_file():
        raise PreconditionError("M3 adapter or real Tachiko CLI is absent; not behavioral RED")
    with tempfile.TemporaryDirectory(prefix="richman4-m3-candidate-") as folder:
        root = Path(folder)
        source, output = root / "candidate.json", root / "candidate.ro"
        def invoke(raw: str):
            source.write_text(raw, encoding="utf-8")
            before = source.read_bytes()
            try:
                result = subprocess.run([str(adapter), "candidate", str(source), str(output)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            except (OSError, subprocess.TimeoutExpired) as exc:
                raise PreconditionError(f"candidate invocation unavailable: {exc}") from exc
            require(source.read_bytes() == before, "candidate mutated its input")
            return result.returncode
        require(invoke(json.dumps(oracle())) == 0 and output.is_file() and output.stat().st_size > 0,
                "valid candidate positive control failed; do not classify later rejects")
        def native(*args: str):
            try:
                return subprocess.run([str(cli), *args], stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL, timeout=30).returncode
            except (OSError, subprocess.TimeoutExpired) as exc:
                raise PreconditionError(f"Tachiko invocation unavailable: {exc}") from exc
        require(not output.is_symlink(), "positive output must not be a symlink")
        require(native("validate", str(output)) == 0, "real Rust admission positive control failed")
        project = root / "base.roproj"
        require(native("roproj", "materialize", str(output), str(project)) == 0,
                "real .roproj materialization positive control failed")
        require(project.is_dir() and not project.is_symlink(), "missing real .roproj directory")
        require(native("roproj", "validate", str(project)) == 0, "real .roproj validation failed")
        def snapshot():
            result = {}
            for path in sorted(project.rglob("*")):
                require(not path.is_symlink(), "unexpected symlink in materialized project")
                if path.is_file():
                    result[path.relative_to(project).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
            require(bool(result), "empty materialized project")
            return result
        before = snapshot()
        ro_before = output.read_bytes()
        require(native("roproj", "materialize", str(output), str(project)) == 1,
                "existing .roproj must deliberately reject, not crash")
        require(snapshot() == before and output.read_bytes() == ro_before, ".roproj collision changed data")
        output.unlink()  # Only our successful positive-control scratch output.
        for name, raw in negative_cases().items():
            require(invoke(raw) == 1, f"{name}: expected deliberate rejection exit 1, not crash/setup error")
            require(not output.exists() and not output.is_symlink(), f"{name}: partial output")
        output.write_bytes(b"M3 existing destination sentinel\n")
        require(invoke(json.dumps(oracle())) == 1, "existing .ro must reject")
        require(output.read_bytes() == b"M3 existing destination sentinel\n", "destination changed")
    print(f"CANDIDATE_BOUNDARY_PASS: {len(negative_cases())} negatives + .ro/.roproj collisions + native admission; not full M3 PASS")


class SelfTests(unittest.TestCase):
    def test_original_and_edit(self):
        projection(oracle())
        projection(oracle(True), True)
        with self.assertRaises(ValueError):
            projection(oracle(True))

    def test_committed_oracle(self):
        projection(loads(read(HERE / "oracle.json")))

    def test_invalid_cases(self):
        for name, raw in negative_cases().items():
            with self.subTest(name=name), self.assertRaises(ValueError):
                shape(loads(raw))

    def test_order_is_presentation_not_identity(self):
        data = oracle()
        data["setup_options"].reverse()
        self.assertEqual(shape(data), oracle())
        with self.assertRaises(ValueError):
            projection(data)

    def test_integral_decimal_tokens_and_zero(self):
        projection(loads(json.dumps(oracle()).replace("300000", "300000.0", 1)))
        self.assertEqual(integer(0), 0)
        self.assertEqual(integer(MAX_INTEGER), MAX_INTEGER)
        with self.assertRaises(ValueError):
            integer(MAX_INTEGER + 1)

    def test_source_parser(self):
        text = "\n".join(f"const {s} := {json.dumps(t)}" for s, t in zip(SYMBOLS, TABLES))
        projection(parse_source(text))
        for bad in (text + "\n" + text, text.replace("300000", "300001"), text.replace("SETUP_DAY_LIMITS", "OTHER")):
            with self.assertRaises(ValueError):
                projection(parse_source(bad))

    def test_witness_failures(self):
        raw = (MARKER + json.dumps(oracle()) + "\n").encode()
        witness(raw, 0)
        for log, code in ((b"", 0), (raw + raw, 0), (raw, 1), (raw + b"SCRIPT ERROR: failure\n", 0)):
            with self.assertRaises(ValueError):
                witness(log, code)

    def test_reader_and_pin(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "large-source.gd"
            raw = b"#" * (LIMIT + 1)
            path.write_bytes(raw)
            self.assertEqual(read(path, SOURCE_LIMIT), raw)
            with self.assertRaises(ValueError):
                read(path)
            blob = hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
            self.assertEqual(pinned(path, blob, SOURCE_LIMIT), raw.decode())
            with self.assertRaises(ValueError):
                pinned(path, "0" * 40, SOURCE_LIMIT)
            path.write_bytes(b"x" * (SOURCE_LIMIT + 1))
            with self.assertRaises(ValueError):
                read(path, SOURCE_LIMIT)

    def test_persisted_identities(self):
        base = {"document_id": "doc", "schema_id": "schema", "field_ids": {x: "field-" + x for x in ("kind", "legacy_index", "value")},
                "rows": [{"kind": r["kind"], "legacy_index": r["legacy_index"], "entity_id": f"opaque-{i}"}
                         for i, r in enumerate(oracle()["setup_options"])]}
        maps = [copy.deepcopy(base) for _ in range(6)]
        maps[3]["rows"].reverse()
        compare_identities(maps)
        maps[3]["rows"][0]["entity_id"] = "changed-persisted-id"
        with self.assertRaises(ValueError):
            compare_identities(maps)
        duplicate = copy.deepcopy(base)
        duplicate["rows"][1]["entity_id"] = duplicate["rows"][0]["entity_id"]
        with self.assertRaises(ValueError):
            identities(duplicate)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    for name in ("runtime-source", "research-source", "godot-log", "projection", "repeat", "edited-projection", "adapter", "tachiko-cli"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--godot-exit-code", type=int)
    parser.add_argument("--identity-maps", type=Path, nargs=6)
    args = parser.parse_args()
    if bool(args.runtime_source) != bool(args.research_source):
        parser.error("supply both --runtime-source and --research-source")
    if bool(args.godot_log) != (args.godot_exit_code is not None):
        parser.error("supply both --godot-log and --godot-exit-code")
    if bool(args.adapter) != bool(args.tachiko_cli):
        parser.error("supply both --adapter and --tachiko-cli")
    if args.repeat and not args.projection:
        parser.error("--repeat requires --projection")
    if not any(vars(args).values()):
        parser.error("choose a check; no empty success")
    try:
        if args.self_test:
            result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SelfTests))
            if not result.wasSuccessful():
                return 1
        if args.runtime_source:
            projection(parse_source(pinned(args.runtime_source, SOURCE_BLOB, SOURCE_LIMIT)))
            pinned(args.research_source, RESEARCH_BLOB, LIMIT)
            print("SOURCE_PIN_PASS: both full source blobs; not runtime execution")
        if args.godot_log:
            witness(read(args.godot_log), args.godot_exit_code)
            print("SOURCE_WITNESS_PASS: static constants only; not UI/gameplay proof")
        if args.projection:
            raw = read(args.projection)
            projection(loads(raw))
            if args.repeat:
                repeated = read(args.repeat)
                projection(loads(repeated))
                require(raw == repeated, "fresh normalized outputs differ byte-for-byte")
        if args.edited_projection:
            projection(loads(read(args.edited_projection)), True)
        if args.identity_maps:
            compare_identities([loads(read(path)) for path in args.identity_maps])
            print("IDENTITY_MAPS_PASS: provenance still requires real storage-path review")
        if args.adapter:
            candidate_acceptance(args.adapter, args.tachiko_cli)
    except PreconditionError as exc:
        print(f"PRECONDITION_UNMET: {exc}", file=sys.stderr)
        return 2
    except (ValueError, UnicodeError, OSError, RecursionError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
