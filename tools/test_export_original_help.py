#!/usr/bin/env python3
"""Focused acceptance tests for the private source-help exporter.

Fixtures are synthetic only: no original body text, archives or decoded
resources are committed here.  The two pinned editions are represented by
little MKF archives whose text resources are generated in this file.
"""

from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

_IMPORT_ERROR = ""
try:
    import export_original_help as exporter
    from decode_original_images import DecodeError, FormatError, InputError
except ImportError as exc:  # pragma: no cover - availability RED only
    exporter = None
    _IMPORT_ERROR = str(exc)

    class DecodeError(Exception):
        """Placeholder so the availability RED still collects."""

    class FormatError(DecodeError):
        pass

    class InputError(DecodeError):
        pass


SCHEMA_INDEX = "richman4.help/v1"
SCHEMA_EDITION = "richman4.help-edition/v1"
SECTION_TOPIC_COUNTS = [1, 6, 12, 3, 16, 18, 30, 13]
SECTION_LABELS = ["操作說明", "遊戲畫面", "遊戲指令", "房 地 產", "特殊地點", "特殊人物", "卡  片", "道  具"]
FIRST_TOPIC_TITLES = [section[0] for section in [
    ["遊戲操作"],
    ["日、月曆", "地產資料", "其他資料", "物價指數", "股票資料", "資金資料"],
    ["LOAD", "SAVE", "卡片", "交易", "地圖", "系統", "股市", "前進", "查詢", "託管", "道具", "說明"],
    ["公司企業", "住宅用地", "商業用地"],
]]
FRAME_PAYLOAD = b"FRAME-ART-NOT-TEXT"
TRAIL_40_LINE = b"\xa7\x40\xa4\xe8"  # CP950: 0x40 is a trail byte, not a separator
MALFORMED_LINE = b"\xff\xfe"

# Resource index -> text resource payload builder.
def _payload(lines: list[bytes]) -> bytes:
    return b"\x00".join(lines) + b"\x00"


def _default_lines(index: int, prefix: bytes = b"topic") -> list[bytes]:
    return [prefix + b"-%03d" % index, b"detail-%03d" % index]


def game_payloads() -> dict[int, bytes]:
    lines: dict[int, list[bytes]] = {index: _default_lines(index) for index in range(1, 100)}
    lines[1] = [b"L%02d" % row for row in range(17)]  # implicit 14-line paging
    lines[2] = [b"a", b"@", b"b", b"c"]  # explicit standalone @ separator
    lines[3] = [b"x", b"", b"y"]  # deliberate blank source line
    lines[4] = [TRAIL_40_LINE]  # 0x40 inside a multibyte character
    lines[5] = [b"M%02d" % row for row in range(14)]  # exact page boundary
    lines[6] = [b"N%02d" % row for row in range(15)]  # one line past the boundary
    return {index: _payload(value) for index, value in lines.items()}


def mj_payloads() -> dict[int, bytes]:
    lines: dict[int, list[bytes]] = {
        index: _default_lines(index, b"mj") for index in range(1, 100)
    }
    lines[1] = [b"short"]  # editions differ
    return {index: _payload(value) for index, value in lines.items()}


def build_mkf(payloads: list[bytes]) -> bytes:
    """Stored (uncompressed) MKF container matching parse_mkf's bounds."""

    body = bytearray(struct.pack("<I", 0))
    starts: list[int] = []
    for payload in payloads:
        starts.append(len(body))
        body.extend(struct.pack("<4I", len(payload), len(payload), 0, 0))
        body.extend(payload)
    table_offset = len(body)
    body[0:4] = struct.pack("<I", table_offset)
    body.extend(struct.pack("<%dI" % len(starts), *starts))
    return bytes(body)


def edition_payloads(texts: dict[int, bytes], *, drop: int | None = None, extra: bool = False) -> list[bytes]:
    payloads = [FRAME_PAYLOAD]
    for index in range(1, 100):
        if index == drop:
            continue
        payloads.append(texts[index])
    if extra:
        payloads.append(b"extra\x00")
    return payloads


def write_edition(root: Path, name: str, texts: dict[int, bytes], **kwargs) -> Path:
    directory = root / name
    directory.mkdir(parents=True)
    (directory / "map.mkf").write_bytes(b"")
    (directory / "help.mkf").write_bytes(build_mkf(edition_payloads(texts, **kwargs)))
    return directory


def make_root(base: Path, **kwargs) -> Path:
    root = base / "source"
    write_edition(root, "Game", game_payloads(), **kwargs)
    write_edition(root, "MultiverseJourney", mj_payloads())
    return root


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sync_sha(index_path: Path, edition: str) -> None:
    index = read_json(index_path)
    record = index["editions"][edition]
    content = (index_path.parent / record["path"]).read_bytes()
    record["sha256"] = hashlib.sha256(content).hexdigest()
    write_json(index_path, index)


def canonical_payload(pages: list) -> str:
    return hashlib.sha256(
        json.dumps(pages, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


class HelpBundleTestCase(unittest.TestCase):
    def setUp(self) -> None:
        if exporter is None:
            self.fail(
                "availability RED: tools/export_original_help.py is not implemented "
                "(%s)" % _IMPORT_ERROR
            )
        self._temporary = tempfile.TemporaryDirectory(prefix="help-exporter-")
        self.addCleanup(self._temporary.cleanup)
        self.base = Path(self._temporary.name)
        self.root = make_root(self.base)
        self.output = self.base / "bundle"

    def export(self, **kwargs) -> dict:
        return exporter.export_help_bundle(kwargs.pop("root", self.root), kwargs.pop("output", self.output), **kwargs)

    def edition(self, name: str = "Game") -> dict:
        return read_json(self.output / "content" / ("%s.json" % name))

    def topics(self, name: str = "Game") -> list[dict]:
        return [topic for section in self.edition(name)["sections"] for topic in section["topics"]]

    def pages(self, resource_index: int, name: str = "Game") -> list:
        return self.topics(name)[resource_index - 1]["pages"]


class ExportContentTests(HelpBundleTestCase):
    def test_export_writes_index_and_both_edition_files(self) -> None:
        manifest = self.export()
        self.assertEqual(manifest["schema"], SCHEMA_INDEX)
        self.assertEqual(sorted(manifest["editions"]), ["Game", "MultiverseJourney"])
        self.assertEqual(read_json(self.output / "manifest.json"), manifest)
        for name in ("Game", "MultiverseJourney"):
            record = manifest["editions"][name]
            content = (self.output / record["path"]).read_bytes()
            self.assertEqual(record["sha256"], hashlib.sha256(content).hexdigest())
            self.assertEqual(record["entry_count"], 100)
            source = hashlib.sha256((self.root / name / "help.mkf").read_bytes()).hexdigest()
            self.assertEqual(record["archive_sha256"], source)
            edition = self.edition(name)
            self.assertEqual(edition["schema"], SCHEMA_EDITION)
            self.assertEqual(edition["edition"], name)
            self.assertEqual(edition["archive_sha256"], source)

    def test_validate_returns_manifest_and_relative_paths(self) -> None:
        self.export()
        manifest, referenced = exporter.validate(self.output / "manifest.json")
        self.assertEqual(manifest["schema"], SCHEMA_INDEX)
        self.assertEqual(
            {path.as_posix() for path in referenced},
            {"content/Game.json", "content/MultiverseJourney.json"},
        )
        for path in referenced:
            self.assertFalse(path.is_absolute())
            self.assertTrue((self.output / path).is_file())

    def test_validate_cross_checks_source_provenance(self) -> None:
        self.export()
        exporter.validate(self.output / "manifest.json", source_root=self.root)
        other = self.base / "other-source"
        write_edition(other, "Game", mj_payloads())
        write_edition(other, "MultiverseJourney", mj_payloads())
        with self.assertRaises(DecodeError):
            exporter.validate(self.output / "manifest.json", source_root=other)

    def test_sections_and_topic_indices_follow_the_frozen_metadata(self) -> None:
        self.export()
        sections = self.edition()["sections"]
        self.assertEqual([len(section["topics"]) for section in sections], SECTION_TOPIC_COUNTS)
        self.assertEqual([section["id"] for section in sections], list(range(8)))
        self.assertEqual([section["label"] for section in sections], SECTION_LABELS)
        self.assertEqual(
            [section["topics"][0]["title"] for section in sections[:4]], FIRST_TOPIC_TITLES
        )
        self.assertEqual(
            [topic["resource_index"] for topic in self.topics()], list(range(1, 100))
        )
        for topic in self.topics():
            self.assertRegex(topic["payload_sha256"], r"^[0-9a-f]{64}$")
            self.assertEqual(topic["payload_sha256"], canonical_payload(topic["pages"]))

    def test_explicit_separator_and_implicit_page_boundaries(self) -> None:
        self.export()
        self.assertEqual(
            self.pages(1), [["L%02d" % row for row in range(14)], ["L14", "L15", "L16"]]
        )
        self.assertEqual(self.pages(2), [["a"], ["b", "c"]])
        self.assertEqual(self.pages(5), [["M%02d" % row for row in range(14)]])
        self.assertEqual(
            self.pages(6), [["N%02d" % row for row in range(14)], ["N14"]]
        )

    def test_blank_source_lines_are_preserved(self) -> None:
        self.export()
        self.assertEqual(self.pages(3), [["x", "", "y"]])

    def test_cp950_trail_0x40_stays_inside_its_line(self) -> None:
        self.export()
        self.assertEqual(self.pages(4), [[TRAIL_40_LINE.decode("cp950")]])

    def test_editions_keep_independent_content(self) -> None:
        self.export()
        self.assertEqual(self.pages(1, "Game")[0][0], "L00")
        self.assertEqual(self.pages(1, "MultiverseJourney"), [["short"]])

    def test_frame_resource_is_not_exported(self) -> None:
        self.export()
        for name in ("Game", "MultiverseJourney"):
            text = (self.output / "content" / ("%s.json" % name)).read_text(encoding="utf-8")
            self.assertNotIn("FRAME-ART-NOT-TEXT", text)


class ExportRejectionTests(HelpBundleTestCase):
    def test_missing_terminator_is_rejected(self) -> None:
        root = self.base / "no-terminator"
        write_edition(root, "Game", game_payloads())
        (root / "Game" / "help.mkf").write_bytes(
            build_mkf(edition_payloads(game_payloads(), drop=99) + [b"unterminated"])
        )
        write_edition(root, "MultiverseJourney", mj_payloads())
        with self.assertRaises(DecodeError):
            exporter.export_help_bundle(root, self.output)

    def test_malformed_cp950_is_rejected(self) -> None:
        root = self.base / "malformed"
        texts = game_payloads()
        texts[2] = MALFORMED_LINE + b"\x00"
        write_edition(root, "Game", texts)
        write_edition(root, "MultiverseJourney", mj_payloads())
        with self.assertRaises(DecodeError):
            exporter.export_help_bundle(root, self.output)

    def test_missing_and_extra_entries_are_rejected(self) -> None:
        for label, keyword in (("missing", {"drop": 50}), ("extra", {"extra": True})):
            root = self.base / ("entries-%s" % label)
            write_edition(root, "Game", game_payloads(), **keyword)
            write_edition(root, "MultiverseJourney", mj_payloads())
            with self.assertRaises(DecodeError):
                exporter.export_help_bundle(root, self.output)

    def test_both_editions_are_required(self) -> None:
        root = self.base / "single"
        write_edition(root, "Game", game_payloads())
        with self.assertRaises(DecodeError):
            exporter.export_help_bundle(root, self.output)

    def test_existing_destination_is_never_modified(self) -> None:
        sentinel = self.output / "keep.txt"
        self.output.mkdir(parents=True)
        sentinel.write_text("keep", encoding="utf-8")
        with self.assertRaises(DecodeError):
            self.export()
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")
        self.assertFalse((self.output / "manifest.json").exists())

    def test_failed_export_removes_only_the_created_destination(self) -> None:
        with mock.patch.object(exporter, "_write_json", side_effect=InputError("injected")):
            with self.assertRaises(DecodeError):
                self.export()
        self.assertFalse(self.output.exists())

    def test_output_must_not_overlap_the_source(self) -> None:
        with self.assertRaises(DecodeError):
            exporter.export_help_bundle(self.root, self.root / "Game" / "help-out")


class ValidateRejectionTests(HelpBundleTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.export()
        self.index_path = self.output / "manifest.json"
        self.index = read_json(self.index_path)

    def test_missing_manifest_is_rejected(self) -> None:
        with self.assertRaises(DecodeError):
            exporter.validate(self.output / "absent.json")

    def test_unsafe_index_paths_are_rejected(self) -> None:
        for bad in ("../Game.json", "content/../../Game.json", "/tmp/Game.json", "content\\Game.json"):
            with self.subTest(path=bad):
                index = read_json(self.index_path)
                index["editions"]["Game"]["path"] = bad
                write_json(self.index_path, index)
                with self.assertRaises(DecodeError):
                    exporter.validate(self.index_path)
                self.index["editions"]["Game"]["path"] = "content/Game.json"
                write_json(self.index_path, self.index)

    def test_index_digest_mismatch_is_rejected(self) -> None:
        self.index["editions"]["Game"]["sha256"] = "0" * 64
        write_json(self.index_path, self.index)
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)

    def test_corrupted_edition_file_is_rejected(self) -> None:
        content = self.output / "content" / "Game.json"
        edition = read_json(content)
        edition["sections"][0]["topics"][0]["pages"] = [["corrupted"]]
        write_json(content, edition)
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)

    def test_payload_digest_mismatch_is_rejected(self) -> None:
        content = self.output / "content" / "Game.json"
        edition = read_json(content)
        edition["sections"][0]["topics"][0]["payload_sha256"] = "0" * 64
        write_json(content, edition)
        sync_sha(self.index_path, "Game")
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)

    def test_wrong_edition_binding_is_rejected(self) -> None:
        self.index["editions"]["Game"]["path"] = "content/MultiverseJourney.json"
        write_json(self.index_path, self.index)
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)

    def test_wrong_schema_is_rejected(self) -> None:
        self.index["schema"] = "richman4.help/v2"
        write_json(self.index_path, self.index)
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)

    def test_missing_edition_entry_is_rejected(self) -> None:
        del self.index["editions"]["MultiverseJourney"]
        write_json(self.index_path, self.index)
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)

    def test_missing_edition_file_is_rejected(self) -> None:
        (self.output / "content" / "Game.json").unlink()
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)

    def test_page_line_rules_are_enforced(self) -> None:
        content = self.output / "content" / "Game.json"
        for pages in ([[], ["ok"]], [["x"] * 15], [[1]]):
            with self.subTest(pages=pages):
                edition = read_json(content)
                topic = edition["sections"][0]["topics"][0]
                topic["pages"] = pages
                topic["payload_sha256"] = canonical_payload(pages)
                write_json(content, edition)
                sync_sha(self.index_path, "Game")
                with self.assertRaises(DecodeError):
                    exporter.validate(self.index_path)

    def test_topic_count_mismatch_is_rejected(self) -> None:
        content = self.output / "content" / "Game.json"
        edition = read_json(content)
        removed = edition["sections"][0]["topics"].pop()
        self.assertTrue(removed)
        write_json(content, edition)
        sync_sha(self.index_path, "Game")
        with self.assertRaises(DecodeError):
            exporter.validate(self.index_path)


class CommandLineTests(HelpBundleTestCase):
    def test_cli_export_then_validate(self) -> None:
        script = Path(exporter.__file__)
        export = subprocess.run(
            [sys.executable, str(script), "--asset-root", str(self.root), "--output", str(self.output)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(export.returncode, 0, export.stderr)
        check = subprocess.run(
            [sys.executable, str(script), "--validate", str(self.output / "manifest.json"), "--asset-root", str(self.root)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(check.returncode, 0, check.stderr)
        broken = subprocess.run(
            [sys.executable, str(script), "--validate", str(self.output / "absent.json")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(broken.returncode, 1)


if __name__ == "__main__":
    unittest.main()
