#!/usr/bin/env python3
"""Export the bounded, private Richman 4 source-help text bundle.

Only ``help.mkf`` resources 1..99 are decoded.  Resource 0 is the 400x400 frame
art handled by the scene image exporter and is never decoded here.  Section
labels and topic titles are short structural metadata from the frozen help
table; the original body text stays in the private output bundle and must not
be committed to public source.

Bundle schema::

    index   {"schema": "richman4.help/v1",
             "editions": {<edition>: {"path", "sha256", "archive_sha256",
                                      "entry_count"}}}
    edition {"schema": "richman4.help-edition/v1", "edition", "archive_sha256",
             "sections": [{"id", "label", "topics": [...]}]}
    topic   {"resource_index", "title", "payload_sha256",
             "source_payload_sha256", "pages": [[<line>, ...], ...]}

Source text rules: each resource is NUL separated and NUL terminated.  The
final terminator is not an extra blank line; interior empty lines are real
blank source lines.  A whole line equal to ASCII ``@`` is an explicit page
separator (splitting raw bytes on 0x40 would corrupt CP950 trail bytes), and
each explicit group is then split into pages of at most 14 lines.

``payload_sha256`` is the sha256 of the UTF-8 bytes of
``json.dumps(pages, ensure_ascii=False, separators=(",", ":"))``.

``source_payload_sha256`` is the sha256 of the exact decoded original resource
bytes, taken before NUL splitting, CP950 decoding or page grouping.  It proves
raw-byte provenance independently of the canonical page digest; the loader
enforces it structurally and ``validate(source_root=...)`` recomputes it from
the original ``help.mkf`` so a bundle can be shown to reproduce the source
exactly.

Output is written into a new, disjoint, private destination only.  A failed
export removes the destination it created and never touches the source or a
pre-existing destination.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import sys
from pathlib import Path, PurePosixPath
from typing import Any

from decode_original_images import (
    FormatError,
    InputError,
    assert_disjoint_paths,
    assert_private_output,
    decode_entry,
    parse_mkf,
)

SCHEMA_INDEX = "richman4.help/v1"
SCHEMA_EDITION = "richman4.help-edition/v1"
DEFAULT_OUTPUT = Path(".local/original-help")
MAX_INDEX_BYTES = 64 * 1024
MAX_EDITION_BYTES = 2 * 1024 * 1024
MIN_PAGE_LINES = 1
MAX_PAGE_LINES = 14
EXPECTED_ENTRY_COUNT = 100
EDITIONS = ("Game", "MultiverseJourney")
PAGE_SEPARATOR = b"@"
TERMINATOR = b"\x00"
_HELP_ARCHIVE = "help.mkf"
_HEX64 = re.compile(r"^[0-9a-f]{64}$")

# Section labels and topic titles are the admitted short UI metadata from the
# frozen S35 help table.  Topic order defines the contiguous 1..99 resource
# mapping.  Long original body text is never listed here.
HELP_SECTIONS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("操作說明", ("遊戲操作",)),
    ("遊戲畫面", ("日、月曆", "地產資料", "其他資料", "物價指數", "股票資料", "資金資料")),
    (
        "遊戲指令",
        (
            "LOAD",
            "SAVE",
            "卡片",
            "交易",
            "地圖",
            "系統",
            "股市",
            "前進",
            "查詢",
            "託管",
            "道具",
            "說明",
        ),
    ),
    ("房 地 產", ("公司企業", "住宅用地", "商業用地")),
    (
        "特殊地點",
        (
            "七彩氣球",
            "公園",
            "卡片",
            "企鵝挖寶",
            "百貨公司",
            "命運",
            "得十點",
            "得三十點",
            "得五十點",
            "喜從天降",
            "新聞",
            "監獄",
            "銀行",
            "樂透",
            "醫院",
            "魔法屋",
        ),
    ),
    (
        "特殊人物",
        (
            "乞丐",
            "土地公",
            "大衰神",
            "大財神",
            "大福神",
            "大窮神",
            "小衰神",
            "小財神",
            "小偷",
            "小福神",
            "小窮神",
            "天使",
            "死神",
            "流氓",
            "強盜",
            "惡犬",
            "惡魔",
            "間諜",
        ),
    ),
    (
        "卡  片",
        (
            "天使卡",
            "冬眠卡",
            "同盟卡",
            "免費卡",
            "免罪卡",
            "均貧卡",
            "均富卡",
            "改建卡",
            "怪獸卡",
            "拍賣卡",
            "拆除卡",
            "查封卡",
            "查稅卡",
            "紅卡",
            "烏龜卡",
            "送神符",
            "停留卡",
            "陷害卡",
            "復仇卡",
            "惡魔卡",
            "換地卡",
            "換屋卡",
            "黑卡",
            "嫁禍卡",
            "搶奪卡",
            "夢遊卡",
            "漲價卡",
            "請神符",
            "購地卡",
            "轉向卡",
        ),
    ),
    (
        "道  具",
        (
            "工程車",
            "地雷",
            "汽車",
            "定時炸彈",
            "飛彈",
            "時光機",
            "核子飛彈",
            "傳送機",
            "路障",
            "遙控骰子",
            "機車",
            "機器工人",
            "機器娃娃",
        ),
    ),
)

EXPECTED_TOPIC_COUNT = sum(len(titles) for _, titles in HELP_SECTIONS)


def _serialize(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n").encode(
        "utf-8"
    )


def _write_json(path: Path, value: Any) -> None:
    data = _serialize(value)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    except OSError as exc:
        raise InputError(f"cannot write {path}: {exc}") from exc


def _read_bounded(path: Path, limit: int, *, context: str) -> bytes:
    if path.is_symlink():
        raise InputError(f"{context}: symlinked files are not accepted: {path}")
    try:
        if path.stat().st_size > limit:
            raise FormatError(f"{context}: {path} exceeds the {limit} byte bound")
        return path.read_bytes()
    except FileNotFoundError as exc:
        raise InputError(f"{context}: missing file {path}") from exc
    except OSError as exc:
        raise InputError(f"{context}: cannot read {path}: {exc}") from exc


def _hex64(value: Any, *, context: str) -> str:
    if not isinstance(value, str) or not _HEX64.match(value):
        raise FormatError(f"{context}: expected 64 lowercase hex characters")
    return value


def _int_field(value: Any, *, context: str, low: int = 0, high: int = 1_000_000) -> int:
    if isinstance(value, bool):
        raise FormatError(f"{context}: boolean is not an integer field")
    if isinstance(value, int):
        number = value
    elif isinstance(value, float):
        if not math.isfinite(value) or not value.is_integer():
            raise FormatError(f"{context}: expected a finite integral number")
        number = int(value)
    else:
        raise FormatError(f"{context}: expected a finite integral number")
    if not low <= number <= high:
        raise FormatError(f"{context}: value {number} is outside {low}..{high}")
    return number


def _safe_relative_path(value: Any, *, context: str) -> Path:
    if not isinstance(value, str) or not value:
        raise FormatError(f"{context}: path must be a non-empty string")
    if "\x00" in value or "\\" in value:
        raise FormatError(f"{context}: path contains an unsupported character: {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or value.startswith("/"):
        raise FormatError(f"{context}: path must be relative: {value!r}")
    if any(part in ("", "..") for part in pure.parts) or pure.suffix != ".json":
        raise FormatError(f"{context}: path escapes the bundle or is not JSON: {value!r}")
    return Path(*pure.parts)


def payload_sha256(pages: list[list[str]]) -> str:
    """Digest of the canonical page payload used by the bundle schema."""

    canonical = json.dumps(pages, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def split_help_pages(decoded: bytes, *, edition: str, resource_index: int) -> list[list[str]]:
    """Split one decoded help resource into ``1..14`` line pages.

    NUL is split first, so a standalone ``@`` line is the only page separator
    and 0x40 bytes inside CP950 lead/trail pairs stay part of their line.
    """

    context = f"{edition} help resource {resource_index}"
    if not isinstance(decoded, (bytes, bytearray)) or not decoded:
        raise FormatError(f"{context}: text resource is empty")
    body = bytes(decoded)
    if not body.endswith(TERMINATOR):
        raise FormatError(f"{context}: text resource is missing its NUL terminator")
    raw_lines = body[: -len(TERMINATOR)].split(TERMINATOR)
    groups: list[list[str]] = []
    group: list[str] = []
    for raw in raw_lines:
        if raw == PAGE_SEPARATOR:
            groups.append(group)
            group = []
            continue
        try:
            group.append(raw.decode("cp950"))
        except UnicodeDecodeError as exc:
            raise FormatError(f"{context}: text is not valid CP950 ({exc})") from exc
    groups.append(group)
    pages: list[list[str]] = []
    for group_index, lines in enumerate(groups):
        if not lines:
            raise FormatError(
                f"{context}: standalone @ separator produced an empty page ({group_index})"
            )
        for start in range(0, len(lines), MAX_PAGE_LINES):
            pages.append(lines[start : start + MAX_PAGE_LINES])
    if not pages:
        raise FormatError(f"{context}: text resource has no pages")
    return pages


def _find_help_archive(directory: Path) -> Path:
    try:
        matches = sorted(
            (
                child
                for child in directory.iterdir()
                if child.is_file()
                and not child.is_symlink()
                and child.name.casefold() == _HELP_ARCHIVE
            ),
            key=lambda path: path.name,
        )
    except OSError as exc:
        raise InputError(f"cannot inspect edition directory {directory}: {exc}") from exc
    if len(matches) != 1:
        raise InputError(f"expected exactly one {_HELP_ARCHIVE} in {directory}")
    return matches[0]


def _edition_directory_map(source: Path) -> dict[str, Path]:
    mapping: dict[str, Path] = {}
    if not source.is_dir():
        raise InputError(f"source is not a directory: {source}")
    # This bounded exporter needs only help.mkf. Map discovery would require
    # unrelated map.mkf files even when both complete help archives exist.
    try:
        discovered = [
            (child.name, child)
            for child in sorted(source.iterdir(), key=lambda path: path.name.casefold())
            if child.is_dir() and not child.is_symlink()
        ]
    except OSError as exc:
        raise InputError(f"cannot inspect source {source}: {exc}") from exc
    for name, path in discovered:
        key = name.casefold()
        if key == "game":
            canonical = "Game"
        elif key == "multiversejourney":
            canonical = "MultiverseJourney"
        else:
            continue
        if canonical in mapping:
            raise InputError(f"duplicate {canonical} edition directory under {source}")
        mapping[canonical] = path
    missing = [edition for edition in EDITIONS if edition not in mapping]
    if missing:
        found = ", ".join(sorted(name for name, _ in discovered)) or "none"
        raise InputError(
            "help export requires both editions; missing "
            + ", ".join(missing)
            + f" (found: {found})"
        )
    return mapping


def _build_edition(edition: str, archive: Any, archive_sha: str) -> dict[str, Any]:
    if len(archive.entries) != EXPECTED_ENTRY_COUNT:
        raise FormatError(
            f"{archive.path}: expected {EXPECTED_ENTRY_COUNT} help resources, "
            f"found {len(archive.entries)}"
        )
    sections: list[dict[str, Any]] = []
    resource_index = 1
    for section_id, (label, titles) in enumerate(HELP_SECTIONS):
        topics: list[dict[str, Any]] = []
        for title in titles:
            decoded = decode_entry(archive, archive.entries[resource_index])
            pages = split_help_pages(
                decoded, edition=edition, resource_index=resource_index
            )
            topics.append(
                {
                    "resource_index": resource_index,
                    "title": title,
                    "payload_sha256": payload_sha256(pages),
                    "source_payload_sha256": hashlib.sha256(decoded).hexdigest(),
                    "pages": pages,
                }
            )
            resource_index += 1
        sections.append({"id": section_id, "label": label, "topics": topics})
    if resource_index - 1 != EXPECTED_TOPIC_COUNT:
        raise FormatError(
            f"{archive.path}: exported {resource_index - 1} topics, "
            f"expected {EXPECTED_TOPIC_COUNT}"
        )
    return {
        "schema": SCHEMA_EDITION,
        "edition": edition,
        "archive_sha256": archive_sha,
        "sections": sections,
    }


def export_help_bundle(asset_root: str | Path, output: str | Path) -> dict[str, Any]:
    """Export both editions into a new private destination and return the index."""

    source = Path(asset_root).expanduser().resolve()
    destination = Path(output).expanduser().resolve()
    if not source.is_dir():
        raise InputError(f"source is not a directory: {source}")
    assert_disjoint_paths(source, destination)
    if destination.exists():
        raise InputError(
            f"help output already exists; refusing to modify it: {destination}"
        )
    assert_private_output(destination)

    directories = _edition_directory_map(source)
    documents: dict[str, dict[str, Any]] = {}
    records: dict[str, dict[str, Any]] = {}
    for edition in EDITIONS:
        archive_path = _find_help_archive(directories[edition])
        archive_bytes = _read_bounded(
            archive_path, 64 * 1024 * 1024, context=f"{edition} help archive"
        )
        archive = parse_mkf(archive_path, archive_bytes)
        archive_sha = hashlib.sha256(bytes(archive.data)).hexdigest()
        document = _build_edition(edition, archive, archive_sha)
        serialized = _serialize(document)
        if len(serialized) > MAX_EDITION_BYTES:
            raise FormatError(
                f"{archive_path}: exported edition exceeds {MAX_EDITION_BYTES} bytes"
            )
        documents[edition] = document
        records[edition] = {
            "path": f"content/{edition}.json",
            "sha256": hashlib.sha256(serialized).hexdigest(),
            "archive_sha256": archive_sha,
            "entry_count": len(archive.entries),
        }
    manifest = {"schema": SCHEMA_INDEX, "editions": records}
    if len(_serialize(manifest)) > MAX_INDEX_BYTES:
        raise FormatError(f"help index exceeds {MAX_INDEX_BYTES} bytes")

    created = False
    try:
        destination.mkdir(parents=True, exist_ok=False)
        created = True
        for edition in EDITIONS:
            _write_json(destination / "content" / f"{edition}.json", documents[edition])
        _write_json(destination / "manifest.json", manifest)
    except BaseException:
        if created:
            shutil.rmtree(destination, ignore_errors=True)
        raise
    return manifest


def _validate_pages(value: Any, *, context: str) -> list[list[str]]:
    if not isinstance(value, list) or not value:
        raise FormatError(f"{context}: topic must have at least one page")
    pages: list[list[str]] = []
    for page_index, page in enumerate(value):
        if not isinstance(page, list) or not (
            MIN_PAGE_LINES <= len(page) <= MAX_PAGE_LINES
        ):
            raise FormatError(
                f"{context}: page {page_index} must have "
                f"{MIN_PAGE_LINES}..{MAX_PAGE_LINES} lines"
            )
        lines: list[str] = []
        for line in page:
            if not isinstance(line, str) or "\x00" in line:
                raise FormatError(f"{context}: page {page_index} has a non-text line")
            lines.append(line)
        pages.append(lines)
    return pages


def _validate_edition_document(
    document: Any, *, edition: str, archive_sha: str
) -> dict[str, Any]:
    if not isinstance(document, dict) or document.get("schema") != SCHEMA_EDITION:
        raise FormatError(f"help edition {edition}: unsupported schema")
    if document.get("edition") != edition:
        raise FormatError(f"help edition {edition}: content is bound to another edition")
    if document.get("archive_sha256") != archive_sha:
        raise FormatError(f"help edition {edition}: archive provenance does not match")
    sections = document.get("sections")
    if not isinstance(sections, list) or len(sections) != len(HELP_SECTIONS):
        raise FormatError(f"help edition {edition}: expected {len(HELP_SECTIONS)} sections")
    expected_resource = 1
    for section_index, (label, titles) in enumerate(HELP_SECTIONS):
        section = sections[section_index]
        if not isinstance(section, dict):
            raise FormatError(f"help edition {edition}: section {section_index} is not an object")
        if _int_field(section.get("id"), context=f"section {section_index} id") != section_index:
            raise FormatError(f"help edition {edition}: section {section_index} id mismatch")
        if section.get("label") != label:
            raise FormatError(f"help edition {edition}: section {section_index} label mismatch")
        topics = section.get("topics")
        if not isinstance(topics, list) or len(topics) != len(titles):
            raise FormatError(
                f"help edition {edition}: section {section_index} topic count mismatch"
            )
        for topic_index, title in enumerate(titles):
            topic = topics[topic_index]
            context = f"help edition {edition} resource {expected_resource}"
            if not isinstance(topic, dict):
                raise FormatError(f"{context}: topic is not an object")
            if (
                _int_field(topic.get("resource_index"), context=f"{context} index", low=1)
                != expected_resource
            ):
                raise FormatError(f"{context}: resource index is not contiguous")
            if topic.get("title") != title:
                raise FormatError(f"{context}: topic title mismatch")
            digest = _hex64(
                topic.get("payload_sha256"), context=f"{context} payload_sha256"
            )
            _hex64(
                topic.get("source_payload_sha256"),
                context=f"{context} source_payload_sha256",
            )
            pages = _validate_pages(topic.get("pages"), context=context)
            if payload_sha256(pages) != digest:
                raise FormatError(f"{context}: payload digest mismatch")
            expected_resource += 1
    if expected_resource - 1 != EXPECTED_TOPIC_COUNT:
        raise FormatError(f"help edition {edition}: topic count mismatch")
    return document


def _validate_source_equality(document: dict[str, Any], archive: Any, *, edition: str) -> None:
    """Prove the exported topics reproduce the exact decoded source resources."""

    resource_index = 1
    for section in document["sections"]:
        for topic in section["topics"]:
            if resource_index >= len(archive.entries):
                raise FormatError(
                    f"help edition {edition} resource {resource_index}: missing source resource"
                )
            decoded = decode_entry(archive, archive.entries[resource_index])
            if hashlib.sha256(decoded).hexdigest() != topic["source_payload_sha256"]:
                raise FormatError(
                    f"help edition {edition} resource {resource_index}: "
                    "source payload digest does not match the original"
                )
            if split_help_pages(decoded, edition=edition, resource_index=resource_index) != topic["pages"]:
                raise FormatError(
                    f"help edition {edition} resource {resource_index}: "
                    "pages do not match the decoded original"
                )
            resource_index += 1
    if resource_index - 1 != EXPECTED_TOPIC_COUNT:
        raise FormatError(f"help edition {edition}: unexpected topic count")


def validate(
    manifest_path: str | Path, *, source_root: str | Path | None = None
) -> tuple[dict[str, Any], list[Path]]:
    """Validate an exported bundle.

    Returns ``(index_document, referenced_paths)`` where every referenced path
    is relative to the manifest directory (the edition content files the
    packager must copy next to the index).  When ``source_root`` is provided
    the ``help.mkf`` archive digests are re-checked against the original
    installation.
    """

    manifest_file = Path(manifest_path).expanduser()
    if not manifest_file.is_file() or manifest_file.is_symlink():
        raise InputError(f"help manifest is not a readable file: {manifest_file}")
    data = _read_bounded(manifest_file, MAX_INDEX_BYTES, context="help index")
    try:
        manifest = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise FormatError(f"help index {manifest_file}: invalid JSON ({exc})") from exc
    if not isinstance(manifest, dict) or manifest.get("schema") != SCHEMA_INDEX:
        raise FormatError(f"help index {manifest_file}: unsupported schema")
    editions = manifest.get("editions")
    if not isinstance(editions, dict) or set(editions) != set(EDITIONS):
        raise FormatError(f"help index {manifest_file}: both editions are required")
    base = manifest_file.parent
    source_directories: dict[str, Path] | None = None
    if source_root is not None:
        source_directories = _edition_directory_map(
            Path(source_root).expanduser().resolve()
        )
    referenced: list[Path] = []
    for edition in EDITIONS:
        record = editions[edition]
        if not isinstance(record, dict):
            raise FormatError(f"help index {edition}: entry is not an object")
        relative = _safe_relative_path(
            record.get("path"), context=f"help index {edition} path"
        )
        expected_sha = _hex64(record.get("sha256"), context=f"help index {edition} sha256")
        archive_sha = _hex64(
            record.get("archive_sha256"), context=f"help index {edition} archive_sha256"
        )
        count = _int_field(
            record.get("entry_count"), context=f"help index {edition} entry_count"
        )
        if count != EXPECTED_ENTRY_COUNT:
            raise FormatError(
                f"help index {edition}: expected {EXPECTED_ENTRY_COUNT} entries, found {count}"
            )
        content_path = base / relative
        content = _read_bounded(
            content_path, MAX_EDITION_BYTES, context=f"help edition {edition}"
        )
        if hashlib.sha256(content).hexdigest() != expected_sha:
            raise FormatError(f"help edition {edition}: file digest mismatch")
        try:
            document = json.loads(content.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise FormatError(f"help edition {edition}: invalid JSON ({exc})") from exc
        _validate_edition_document(document, edition=edition, archive_sha=archive_sha)
        if source_directories is not None:
            archive_path = _find_help_archive(source_directories[edition])
            archive_bytes = _read_bounded(
                archive_path, 64 * 1024 * 1024, context=f"{edition} help archive"
            )
            actual = hashlib.sha256(archive_bytes).hexdigest()
            if actual != archive_sha:
                raise FormatError(
                    f"help edition {edition}: archive digest does not match the source"
                )
            _validate_source_equality(
                document,
                parse_mkf(archive_path, archive_bytes),
                edition=edition,
            )
        referenced.append(relative)
    return manifest, referenced


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--asset-root",
        type=Path,
        help="installation root containing the Game and MultiverseJourney folders",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="new private destination directory (export mode)",
    )
    parser.add_argument(
        "--validate", type=Path, metavar="MANIFEST", help="validate an exported bundle"
    )
    args = parser.parse_args(argv)
    try:
        if args.validate is not None:
            manifest, referenced = validate(args.validate, source_root=args.asset_root)
            print(
                json.dumps(
                    {
                        "schema": manifest["schema"],
                        "files": [path.as_posix() for path in referenced],
                    },
                    ensure_ascii=False,
                )
            )
            return 0
        if args.asset_root is None:
            parser.error("--asset-root is required for export")
        manifest = export_help_bundle(args.asset_root, args.output)
        print(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except (InputError, FormatError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
