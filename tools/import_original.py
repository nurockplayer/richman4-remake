#!/usr/bin/env python3
"""Inventory and import owner-provided Richman 4 resources.

The original installation is intentionally kept outside the repository.  This
tool reads packed files from a local installation and writes a small,
deterministic JSON representation below ``.local/imported-original`` (or the
directory supplied with ``--output``).  It never copies an executable or a
packed asset into the checkout.

Only the map records that are stored uncompressed are decoded here.  The MKF
container's compressed records use the game's private codec; silently treating
those bytes as a generic archive would produce corrupt content, so such
records are inventoried and left available to a future codec implementation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import sys
from typing import Any, Iterator, Sequence


SCHEMA_VERSION = 1
TOOL_VERSION = "1"
MKF_HEADER_SIZE = 16
MKF_MIN_SIZE = 20
MAP_HEADER_SIZE = 40

# The resource tables in map.mkf contain one zero record before the numbered
# records.  These sizes are part of the original map format and are checked
# against section offsets before any record is read.
MAP_RECORD_SIZES = {
    "nodes": 40,
    "lands": 52,
    "facilities": 56,
    "companies": 52,
    "landscapes": 28,
}
MAP_HEADER_FIELDS = (
    "nodes_count",
    "nodes_offset",
    "lands_count",
    "lands_offset",
    "facilities_count",
    "facilities_offset",
    "companies_count",
    "companies_offset",
    "landscapes_count",
    "landscapes_offset",
)

# ``rich4.exe`` keeps a twelve-row template for each map.  The table is in the
# data section rather than in a PE resource, so the importer validates the
# image mapping before reading it.  The row layout is the original packed
# 0x24-byte structure (u32 name pointer, two u16 status/supply pairs, then
# five float values).
STOCK_ROW_COUNT = 12
STOCK_ROW_SIZE = 0x24
STOCK_TABLE_VA = {
    "Game": 0x47CE92,
    "MultiverseJourney": 0x47F072,
}


class ImportErrorBase(Exception):
    """Base class for input and format failures raised by this tool."""


class InputError(ImportErrorBase):
    """The requested source or output is not usable."""


class FormatError(ImportErrorBase):
    """A binary resource does not satisfy the validated format."""


class UnsupportedCompression(ImportErrorBase):
    """A caller requested decoded bytes for a private compressed record."""


@dataclass(frozen=True)
class MkfEntry:
    """One entry in an MKF archive's absolute-offset index table."""

    index: int
    offset: int
    uncompressed_size: int
    stored_size: int
    image_data_offset: int
    image_data_size: int
    payload_offset: int
    payload_end: int

    @property
    def is_stored(self) -> bool:
        return self.uncompressed_size == self.stored_size

    @property
    def compression(self) -> str:
        return "stored" if self.is_stored else "private"

    def as_dict(self) -> dict[str, Any]:
        return {
            "index": self.index,
            "offset": self.offset,
            "uncompressed_size": self.uncompressed_size,
            "stored_size": self.stored_size,
            "image_data_offset": self.image_data_offset,
            "image_data_size": self.image_data_size,
            "payload_offset": self.payload_offset,
            "payload_end": self.payload_end,
            "compression": self.compression,
        }


@dataclass(frozen=True)
class MkfArchive:
    path: Path
    data: bytes
    table_offset: int
    entries: tuple[MkfEntry, ...]

    def payload(self, entry: MkfEntry, *, decoded: bool = False) -> bytes:
        """Return stored bytes, or decoded bytes when the record is uncompressed.

        The private compressed codec is deliberately not guessed.  A future
        implementation can add it without changing the container validation or
        map schema.
        """

        raw = self.data[entry.payload_offset : entry.payload_end]
        if len(raw) != entry.stored_size:
            raise FormatError(f"{self.path}: entry {entry.index} payload is truncated")
        if decoded and not entry.is_stored:
            raise UnsupportedCompression(
                f"{self.path}: entry {entry.index} uses the private MKF codec"
            )
        return raw

    def as_dict(self) -> dict[str, Any]:
        return {
            "path": _relative_archive_path(self.path),
            "size": len(self.data),
            "index_table_offset": self.table_offset,
            "entry_count": len(self.entries),
            "entries": [entry.as_dict() for entry in self.entries],
        }


@dataclass(frozen=True)
class PeSection:
    """The PE fields needed to translate image VAs into file offsets."""

    name: str
    virtual_address: int
    virtual_size: int
    raw_offset: int
    raw_size: int

    @property
    def span(self) -> int:
        # A number of old Borland/Watcom images leave VirtualSize at zero.
        # RawSize is still the file-backed span in that case.
        return max(self.virtual_size, self.raw_size)


def _u32(data: bytes, offset: int, *, context: str) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise FormatError(f"{context}: expected a 32-bit value at offset {offset}")
    return struct.unpack_from("<I", data, offset)[0]


def parse_mkf(path: Path, data: bytes | None = None) -> MkfArchive:
    """Parse and validate an MKF file without attempting private decompression.

    The first dword points to a table at EOF.  Table values are absolute record
    starts, including the first resource at offset 4.  Each record's payload is
    bounded by the next table value (or by the table itself for the last entry),
    so a malformed compressed-size field cannot make the parser read outside an
    entry.
    """

    if data is None:
        try:
            data = path.read_bytes()
        except OSError as exc:
            raise InputError(f"cannot read {path}: {exc}") from exc
    if len(data) < MKF_MIN_SIZE:
        raise FormatError(f"{path}: MKF is too small ({len(data)} bytes)")

    table_offset = _u32(data, 0, context=str(path))
    if table_offset < 4 or table_offset > len(data) - 4:
        raise FormatError(
            f"{path}: index table offset {table_offset} is outside the file"
        )
    table_bytes = len(data) - table_offset
    if table_bytes % 4:
        raise FormatError(f"{path}: index table length is not divisible by four")
    starts = struct.unpack_from(f"<{table_bytes // 4}I", data, table_offset)
    if not starts:
        raise FormatError(f"{path}: index table is empty")
    if starts[0] != 4:
        raise FormatError(f"{path}: first resource starts at {starts[0]}, expected 4")

    entries: list[MkfEntry] = []
    previous = -1
    for index, start in enumerate(starts):
        if start <= previous:
            raise FormatError(f"{path}: resource starts are not strictly increasing")
        previous = start
        next_start = starts[index + 1] if index + 1 < len(starts) else table_offset
        if start < 4 or start >= table_offset or next_start > table_offset:
            raise FormatError(f"{path}: resource {index} lies outside the data region")
        if start + MKF_HEADER_SIZE > next_start:
            raise FormatError(f"{path}: resource {index} has no complete header")
        uncompressed, stored, image_offset, image_size = struct.unpack_from(
            "<4I", data, start
        )
        payload_offset = start + MKF_HEADER_SIZE
        payload_end = payload_offset + stored
        if payload_end != next_start:
            raise FormatError(
                f"{path}: resource {index} stored size {stored} does not match "
                f"its table span {next_start - payload_offset}"
            )
        if image_offset > uncompressed or image_size > uncompressed - image_offset:
            raise FormatError(f"{path}: resource {index} image range exceeds decoded size")
        entries.append(
            MkfEntry(
                index=index,
                offset=start,
                uncompressed_size=uncompressed,
                stored_size=stored,
                image_data_offset=image_offset,
                image_data_size=image_size,
                payload_offset=payload_offset,
                payload_end=payload_end,
            )
        )
    return MkfArchive(path=path, data=data, table_offset=table_offset, entries=tuple(entries))


def classify_node_type(type_and_idx: int) -> str:
    """Return the conservative category encoded in a map node."""

    if 2000 <= type_and_idx < 4000:
        return "land"
    if 4000 <= type_and_idx < 6000:
        return "facility"
    if 6000 <= type_and_idx < 8000:
        return "company"
    return "other"


def _name_fields(raw: bytes) -> dict[str, Any]:
    # Names in this archive are not declared UTF-8.  Keep the exact bytes and
    # expose a display value only after a strict Big5-family round trip.  CP950
    # is the Windows Big5 extension used by the source data (it covers the
    # otherwise invalid-in-strict-Big5 bytes found in the China map).
    result: dict[str, Any] = {"name_bytes_hex": raw.hex()}
    trimmed = raw.split(b"\0", 1)[0]
    if trimmed and all(byte < 0x80 for byte in trimmed):
        display_name = trimmed.decode("ascii")
        result.update(
            {
                "name_ascii": display_name,
                "display_name": display_name,
                "display_name_encoding": "ascii",
                "display_name_confidence": "inferred-roundtrip",
            }
        )
        return result
    if trimmed:
        try:
            display_name = trimmed.decode("cp950")
            if display_name.encode("cp950") == trimmed:
                result.update(
                    {
                        "display_name": display_name,
                        "display_name_encoding": "cp950",
                        "display_name_confidence": "inferred-roundtrip",
                    }
                )
        except UnicodeError:
            pass
    return result


def _parse_pe_sections(path: Path, data: bytes) -> tuple[int, tuple[PeSection, ...]]:
    """Read the small PE32 header needed by the source stock table parser."""

    if len(data) < 0x40 or data[:2] != b"MZ":
        raise FormatError(f"{path}: executable is not a DOS/PE image")
    pe_offset = _u32(data, 0x3C, context=str(path))
    if pe_offset < 0x40 or pe_offset + 24 > len(data):
        raise FormatError(f"{path}: PE header offset is outside the file")
    if data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise FormatError(f"{path}: PE signature is invalid")
    section_count = struct.unpack_from("<H", data, pe_offset + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe_offset + 20)[0]
    if section_count == 0 or section_count > 96:
        raise FormatError(f"{path}: unreasonable PE section count {section_count}")
    optional_offset = pe_offset + 24
    optional_end = optional_offset + optional_size
    if optional_end > len(data) or optional_size < 32:
        raise FormatError(f"{path}: PE optional header is truncated")
    optional_magic = struct.unpack_from("<H", data, optional_offset)[0]
    if optional_magic != 0x10B:
        raise FormatError(f"{path}: expected a PE32 optional header")
    image_base = struct.unpack_from("<I", data, optional_offset + 28)[0]
    if image_base == 0:
        raise FormatError(f"{path}: PE image base is zero")
    sections_offset = optional_end
    sections_end = sections_offset + section_count * 40
    if sections_end > len(data):
        raise FormatError(f"{path}: PE section table is truncated")
    sections: list[PeSection] = []
    for index in range(section_count):
        start = sections_offset + index * 40
        raw_name = data[start : start + 8].split(b"\0", 1)[0]
        name = raw_name.decode("ascii", errors="replace") or f"section-{index}"
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
            "<4I", data, start + 8
        )
        raw_end = raw_offset + raw_size
        if raw_size and raw_offset and (raw_offset < sections_end or raw_end > len(data)):
            raise FormatError(f"{path}: PE section {name} raw span is invalid")
        if virtual_address + max(virtual_size, raw_size) > 0x100000000:
            raise FormatError(f"{path}: PE section {name} virtual span overflows")
        if raw_offset == 0:
            # The source's old linker records the uninitialised .bss span in
            # SizeOfRawData while leaving PointerToRawData at zero.  Preserve
            # that virtual span, but mark the section as having no file bytes.
            virtual_size = max(virtual_size, raw_size)
            raw_size = 0
        sections.append(
            PeSection(
                name=name,
                virtual_address=virtual_address,
                virtual_size=virtual_size,
                raw_offset=raw_offset,
                raw_size=raw_size,
            )
        )
    return image_base, tuple(sections)


def _pe_va_to_file_offset(
    path: Path,
    data: bytes,
    image_base: int,
    sections: tuple[PeSection, ...],
    virtual_address: int,
    *,
    context: str,
) -> tuple[int, PeSection]:
    """Translate one image VA while rejecting virtual-only section tails."""

    if virtual_address < image_base:
        raise FormatError(f"{path}: {context} VA {virtual_address:#x} precedes image base")
    rva = virtual_address - image_base
    matches = [
        section
        for section in sections
        if section.span and section.virtual_address <= rva < section.virtual_address + section.span
    ]
    if len(matches) != 1:
        raise FormatError(f"{path}: {context} VA {virtual_address:#x} is not uniquely mapped")
    section = matches[0]
    delta = rva - section.virtual_address
    if delta >= section.raw_size:
        raise FormatError(f"{path}: {context} VA {virtual_address:#x} is not file-backed")
    file_offset = section.raw_offset + delta
    if file_offset >= len(data):
        raise FormatError(f"{path}: {context} file offset is outside the image")
    return file_offset, section


def _read_pe_c_string(
    path: Path, data: bytes, offset: int, section: PeSection, *, context: str
) -> bytes:
    """Read a NUL-terminated source string within its file-backed section."""

    section_end = section.raw_offset + section.raw_size
    if offset < section.raw_offset or offset >= section_end:
        raise FormatError(f"{path}: {context} name pointer is outside its section")
    end = data.find(b"\0", offset, section_end)
    if end < 0:
        raise FormatError(f"{path}: {context} name is not NUL-terminated")
    raw = data[offset:end]
    if not raw or len(raw) > 128:
        raise FormatError(f"{path}: {context} name length is invalid")
    return raw


def parse_stock_groups(path: Path, *, edition: str) -> list[list[dict[str, Any]]]:
    """Decode the edition's static twelve-stock templates from ``rich4.exe``.

    The executable is owner-provided input and never copied to generated data.
    ``company_id`` initially reflects the source +0x04 word.  ``import_source``
    replaces it with the run-time map-company link established by the original
    ``rich4_init_stock_commercial`` routine while preserving that raw word as
    ``source_initial_link``.
    """

    try:
        data = path.read_bytes()
    except OSError as exc:
        raise InputError(f"cannot read {path}: {exc}") from exc
    table_va = STOCK_TABLE_VA.get(edition)
    group_count = {"Game": 4, "MultiverseJourney": 8}.get(edition)
    if table_va is None or group_count is None:
        raise FormatError(f"{path}: no stock table is defined for edition {edition}")
    image_base, sections = _parse_pe_sections(path, data)
    table_offset, _ = _pe_va_to_file_offset(
        path,
        data,
        image_base,
        sections,
        table_va,
        context="stock table",
    )
    table_size = group_count * STOCK_ROW_COUNT * STOCK_ROW_SIZE
    if table_offset + table_size > len(data):
        raise FormatError(f"{path}: stock table is truncated")

    groups: list[list[dict[str, Any]]] = []
    for group_index in range(group_count):
        rows: list[dict[str, Any]] = []
        for row_index in range(STOCK_ROW_COUNT):
            start = table_offset + (group_index * STOCK_ROW_COUNT + row_index) * STOCK_ROW_SIZE
            name_pointer = _u32(data, start, context=f"stock row {group_index}:{row_index}")
            name_offset, name_section = _pe_va_to_file_offset(
                path,
                data,
                image_base,
                sections,
                name_pointer,
                context=f"stock row {group_index}:{row_index} name",
            )
            name_bytes = _read_pe_c_string(
                path,
                data,
                name_offset,
                name_section,
                context=f"stock row {group_index}:{row_index}",
            )
            name_fields = _name_fields(name_bytes)
            display_name = name_fields.get("display_name")
            if not isinstance(display_name, str) or not display_name:
                raise FormatError(
                    f"{path}: stock row {group_index}:{row_index} name is not valid CP950"
                )
            source_initial_link = struct.unpack_from("<H", data, start + 4)[0]
            suspension = data[start + 6]
            event = data[start + 7]
            market_supply, turn_supply = struct.unpack_from("<2H", data, start + 8)
            base_price, previous_price, price, volatility, momentum, shock = struct.unpack_from(
                "<6f", data, start + 0x0C
            )
            if market_supply > 10000 or turn_supply > market_supply:
                raise FormatError(f"{path}: stock row {group_index}:{row_index} supply is invalid")
            if not all(math.isfinite(value) for value in (base_price, previous_price, price, volatility, momentum, shock)):
                raise FormatError(f"{path}: stock row {group_index}:{row_index} has a non-finite value")
            if not all(1.0 <= value <= 9999.0 for value in (base_price, previous_price, price)):
                raise FormatError(f"{path}: stock row {group_index}:{row_index} price is invalid")
            if not 0.0 <= volatility <= 1000.0 or not -10.0 <= momentum <= 10.0 or not -100.0 <= shock <= 100.0:
                raise FormatError(f"{path}: stock row {group_index}:{row_index} dynamics are invalid")
            rows.append(
                {
                    "index": row_index,
                    "name": display_name,
                    "company_id": source_initial_link,
                    "market_supply": market_supply,
                    "turn_supply": turn_supply,
                    "base_price": base_price,
                    "previous_price": previous_price,
                    "price": price,
                    "volatility": volatility,
                    "momentum": momentum,
                    "shock": shock,
                    "suspension": suspension,
                    "event": event,
                    "source_initial_link": source_initial_link,
                }
            )
        groups.append(rows)
    return groups


def _map_section_bounds(
    payload_size: int, header: dict[str, int]
) -> dict[str, tuple[int, int]]:
    sections: dict[str, tuple[int, int]] = {}
    previous_end = MAP_HEADER_SIZE
    previous_name = "header"
    for name, count_key, offset_key in (
        ("nodes", "nodes_count", "nodes_offset"),
        ("lands", "lands_count", "lands_offset"),
        ("facilities", "facilities_count", "facilities_offset"),
        ("companies", "companies_count", "companies_offset"),
        ("landscapes", "landscapes_count", "landscapes_offset"),
    ):
        count = header[count_key]
        offset = header[offset_key]
        if count > 1_000_000:
            raise FormatError(f"map: {name} count {count} is unreasonable")
        if offset < MAP_HEADER_SIZE or offset > payload_size:
            raise FormatError(f"map: {name} offset {offset} is outside the payload")
        record_count = count + 1  # resource tables contain a dummy record at ID 0
        size = MAP_RECORD_SIZES[name]
        span = record_count * size
        end = offset + span
        if end > payload_size:
            raise FormatError(f"map: {name} section ends at {end}, beyond {payload_size}")
        if offset < previous_end:
            raise FormatError(
                f"map: {name} section overlaps {previous_name} ({offset} < {previous_end})"
            )
        sections[name] = (offset, end)
        previous_end = end
        previous_name = name
    return sections


def _parse_map_nodes(
    payload: bytes, offset: int, count: int
) -> tuple[list[dict[str, Any]], list[int]]:
    nodes: list[dict[str, Any]] = []
    invalid_edges: list[int] = []
    for node_id in range(1, count + 1):
        start = offset + node_id * MAP_RECORD_SIZES["nodes"]
        x, y = struct.unpack_from("<hh", payload, start)
        adjacent_slots = list(struct.unpack_from("<4H", payload, start + 24))
        type_and_idx, field = struct.unpack_from("<2H", payload, start + 32)
        status = struct.unpack_from("<I", payload, start + 36)[0]
        invalid_edges.extend(
            edge for edge in adjacent_slots if edge != 0 and not 1 <= edge <= count
        )
        category = classify_node_type(type_and_idx)
        record: dict[str, Any] = {
            "id": node_id,
            "x": x,
            "y": y,
            "adjacent": [edge for edge in adjacent_slots if edge != 0],
            "adjacent_slots": adjacent_slots,
            "type_and_idx": type_and_idx,
            "category": category,
            "field_0x22": field,
            "visual_index": field,
            "status_bits": status,
            "event_code": status & 0xFF,
            "reserved_hex": payload[start + 4 : start + 24].hex(),
        }
        if category != "other":
            record["object_index"] = type_and_idx % 2000
        nodes.append(record)
    return nodes, invalid_edges


def _parse_map_lands(payload: bytes, offset: int, count: int) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    size = MAP_RECORD_SIZES["lands"]
    for record_id in range(1, count + 1):
        start = offset + record_id * size
        x, y = struct.unpack_from("<HH", payload, start)
        record: dict[str, Any] = {"id": record_id, "x": x, "y": y}
        record.update(_name_fields(payload[start + 4 : start + 20]))
        record.update(
            {
                "tmp_state": payload[start + 23],
                "is_chain_store": payload[start + 24],
                "owner": payload[start + 25],
                "level": payload[start + 26],
                "field_0x1b": payload[start + 27],
                # The on-disk housing_land layout is land_price at +0x1c
                # followed by house_price at +0x1e.  Keep the historical
                # price_per_level key as an alias for house_price for callers
                # of schema v1.
                "land_price": struct.unpack_from("<H", payload, start + 28)[0],
                "house_price": struct.unpack_from("<H", payload, start + 30)[0],
                "price_per_level": struct.unpack_from("<H", payload, start + 30)[0],
                "rent_by_level": list(struct.unpack_from("<6H", payload, start + 32)),
                "reserved_hex": payload[start + 32 : start + 44].hex(),
                "field_0x2c": struct.unpack_from("<I", payload, start + 44)[0],
                "expired_date": struct.unpack_from("<I", payload, start + 48)[0],
            }
        )
        records.append(record)
    return records


def _parse_map_facilities(payload: bytes, offset: int, count: int) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    size = MAP_RECORD_SIZES["facilities"]
    for record_id in range(1, count + 1):
        start = offset + record_id * size
        x, y = struct.unpack_from("<HH", payload, start)
        facility_prices = list(struct.unpack_from("<6H", payload, start + 36))
        record: dict[str, Any] = {"id": record_id, "x": x, "y": y}
        record.update(_name_fields(payload[start + 4 : start + 20]))
        record.update(
            {
                "facility_type": payload[start + 24],
                "owner": payload[start + 25],
                "level": payload[start + 26],
                "field_0x1b": payload[start + 27],
                "tmp_state": payload[start + 28],
                "land_price": struct.unpack_from("<H", payload, start + 34)[0],
                # The six u16 values at +0x24 are shared by the original
                # upgrade/fee table: index 0 is the level-zero upgrade cost,
                # while indexes 1..5 are the corresponding service fees.
                # Keep price_per_level as the schema-v1 compatibility alias.
                "house_price": facility_prices[0],
                "price_per_level": facility_prices[0],
                "upgrade_cost": facility_prices[0],
                "fee_by_level": facility_prices,
                "reserved_hex": payload[start + 38 : start + 48].hex(),
                "field_0x30": struct.unpack_from("<I", payload, start + 48)[0],
                "expired_date": struct.unpack_from("<I", payload, start + 52)[0],
            }
        )
        records.append(record)
    return records


def _parse_map_companies(payload: bytes, offset: int, count: int) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    size = MAP_RECORD_SIZES["companies"]
    for record_id in range(1, count + 1):
        start = offset + record_id * size
        x, y = struct.unpack_from("<HH", payload, start)
        record: dict[str, Any] = {"id": record_id, "x": x, "y": y}
        record.update(_name_fields(payload[start + 4 : start + 20]))
        source_owner = payload[start + 24]
        company_type = payload[start + 26]
        record.update(
            {
                "owner": source_owner,
                "source_owner": source_owner,
                "stock_index": payload[start + 25],
                "company_type": company_type,
                # Keep the importer-v1 key used by existing map consumers.
                "commerce_type": company_type,
                "field_0x1b": payload[start + 27],
                "toll_fee": struct.unpack_from("<H", payload, start + 34)[0],
                "stock_value": struct.unpack_from("<I", payload, start + 36)[0],
                "monthly_profit": struct.unpack_from("<I", payload, start + 40)[0],
                "cumulative_profit": struct.unpack_from("<I", payload, start + 44)[0],
                "treasury": struct.unpack_from("<I", payload, start + 48)[0],
                "reserved_hex": (
                    payload[start + 4 : start + 24] + payload[start + 27 : start + 34]
                    + payload[start + 36 : start + 52]
                ).hex(),
            }
        )
        records.append(record)
    return records


def _link_stock_rows(
    rows: Sequence[dict[str, Any]], companies: Sequence[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Apply the run-time stock-index-to-company mapping used by the game."""

    by_stock_index: dict[int, int | None] = {}
    for company in companies:
        stock_index = company.get("stock_index")
        company_id = company.get("id")
        if not isinstance(stock_index, int) or not 0 <= stock_index < STOCK_ROW_COUNT:
            continue
        if not isinstance(company_id, int) or not 1 <= company_id <= 1999:
            continue
        if stock_index in by_stock_index:
            # A duplicate index cannot be resolved without inventing an
            # identity.  Leave both affected stock links explicitly unlinked.
            by_stock_index[stock_index] = None
        else:
            by_stock_index[stock_index] = company_id
    linked: list[dict[str, Any]] = []
    for row in rows:
        normalized = dict(row)
        index = row.get("index")
        company_id = by_stock_index.get(index, 0) if isinstance(index, int) else 0
        normalized["company_id"] = company_id if isinstance(company_id, int) else 0
        linked.append(normalized)
    return linked


def _parse_map_landscapes(payload: bytes, offset: int, count: int) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    size = MAP_RECORD_SIZES["landscapes"]
    for record_id in range(1, count + 1):
        start = offset + record_id * size
        x, y = struct.unpack_from("<HH", payload, start)
        record: dict[str, Any] = {"id": record_id, "x": x, "y": y}
        record.update(_name_fields(payload[start + 4 : start + 28]))
        records.append(record)
    return records


def parse_map_payload(
    payload: bytes,
    *,
    edition: str = "",
    archive_path: str = "",
    entry_index: int = -1,
    payload_sha256: str | None = None,
) -> dict[str, Any]:
    """Decode one uncompressed ``map.mkf`` resource into JSON-compatible data."""

    if len(payload) < MAP_HEADER_SIZE:
        raise FormatError("map: payload is shorter than its ten-word header")
    values = struct.unpack_from("<10I", payload, 0)
    header = dict(zip(MAP_HEADER_FIELDS, values))
    sections = _map_section_bounds(len(payload), header)
    nodes, invalid_edges = _parse_map_nodes(
        payload, sections["nodes"][0], header["nodes_count"]
    )
    if invalid_edges:
        raise FormatError(
            "map: adjacency references unknown node IDs "
            + ", ".join(str(value) for value in sorted(set(invalid_edges)))
        )
    result: dict[str, Any] = {
        "schema": "richman4.map/v1",
        "version": SCHEMA_VERSION,
        "edition": edition,
        "archive": archive_path,
        "entry_index": entry_index,
        "payload_size": len(payload),
        "payload_sha256": payload_sha256 or hashlib.sha256(payload).hexdigest(),
        "header": header,
        "sections": {
            name: {"offset": start, "end": end, "record_size": MAP_RECORD_SIZES[name]}
            for name, (start, end) in sections.items()
        },
        "counts": {
            name: header[f"{name}_count"]
            for name in MAP_RECORD_SIZES
        },
        "nodes": nodes,
        "lands": _parse_map_lands(
            payload, sections["lands"][0], header["lands_count"]
        ),
        "facilities": _parse_map_facilities(
            payload, sections["facilities"][0], header["facilities_count"]
        ),
        "companies": _parse_map_companies(
            payload, sections["companies"][0], header["companies_count"]
        ),
        "landscapes": _parse_map_landscapes(
            payload, sections["landscapes"][0], header["landscapes_count"]
        ),
    }
    # Unknown trailing bytes are retained as a validation fact.  Current
    # source maps have no trailing bytes; future variants can still be read.
    final_end = sections["landscapes"][1]
    result["trailing_bytes"] = len(payload) - final_end
    return result


def _safe_component(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("._")
    return cleaned or "source"


def _relative_archive_path(path: Path) -> str:
    # MkfArchive paths are normalized to an edition-relative display path by
    # the caller.  This fallback keeps direct parse_mkf() output useful too.
    return path.as_posix()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise InputError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _file_kind(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".mkf":
        return "packed-resource"
    if suffix in {".exe", ".dll", ".bin"}:
        return "binary"
    if suffix in {".wav", ".ogg", ".avi", ".mp4", ".mid", ".midi"}:
        return "media"
    if suffix in {".txt", ".xml", ".vdf", ".ini"}:
        return "metadata"
    return "other"


def _path_for_json(path: Path, source_root: Path) -> str:
    try:
        return path.relative_to(source_root).as_posix()
    except ValueError as exc:
        raise InputError(f"source file escaped source root: {path}") from exc


def _find_casefolded(directory: Path, filename: str) -> Path | None:
    wanted = filename.casefold()
    try:
        for child in directory.iterdir():
            if child.is_file() and not child.is_symlink() and child.name.casefold() == wanted:
                return child
    except OSError as exc:
        raise InputError(f"cannot inspect {directory}: {exc}") from exc
    return None


def discover_editions(source_root: Path) -> list[tuple[str, Path]]:
    """Find installation folders containing map.mkf without entering DxWnd."""

    source_root = source_root.expanduser().resolve()
    if not source_root.is_dir():
        raise InputError(f"source is not a directory: {source_root}")
    direct_map = _find_casefolded(source_root, "map.mkf")
    if direct_map is not None:
        return [(source_root.name, source_root)]

    editions: list[tuple[str, Path]] = []
    try:
        children = sorted(source_root.iterdir(), key=lambda p: p.name.casefold())
    except OSError as exc:
        raise InputError(f"cannot inspect source {source_root}: {exc}") from exc
    for child in children:
        if not child.is_dir() or child.is_symlink() or child.name.casefold() in {
            ".git",
            "dxwnd",
            "media",
        }:
            continue
        if _find_casefolded(child, "map.mkf") is not None:
            editions.append((child.name, child))
    if not editions:
        raise InputError(
            f"no installation folder containing map.mkf was found below {source_root}"
        )
    return editions


def _iter_regular_files(directory: Path) -> Iterator[Path]:
    """Yield files from an edition while refusing symlinked content."""

    try:
        children = sorted(directory.iterdir(), key=lambda p: p.name.casefold())
    except OSError as exc:
        raise InputError(f"cannot inspect {directory}: {exc}") from exc
    for child in children:
        if child.is_symlink():
            continue
        if child.is_file():
            yield child


def _inventory_file(path: Path, source_root: Path) -> dict[str, Any]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise InputError(f"cannot stat {path}: {exc}") from exc
    return {
        "path": _path_for_json(path, source_root),
        "size": size,
        "sha256": _sha256(path),
        "kind": _file_kind(path),
    }


def _archive_json(archive: MkfArchive, source_root: Path) -> dict[str, Any]:
    result = archive.as_dict()
    result["path"] = _path_for_json(archive.path, source_root)
    return result


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as output:
            json.dump(value, output, ensure_ascii=False, indent=2, sort_keys=True)
            output.write("\n")
        os.replace(temporary, path)
    except OSError as exc:
        try:
            temporary.unlink()
        except OSError:
            pass
        raise InputError(f"cannot write {path}: {exc}") from exc


def import_source(
    source_root: Path,
    output_root: Path,
    *,
    edition_filter: set[str] | None = None,
    extract_map_payloads: bool = False,
) -> dict[str, Any]:
    """Build the local inventory and map catalog, returning the manifest."""

    source_root = source_root.expanduser().resolve()
    output_root = output_root.expanduser().resolve()
    discovered = discover_editions(source_root)
    if edition_filter:
        requested = {value.casefold() for value in edition_filter}
        discovered = [
            (name, path) for name, path in discovered if name.casefold() in requested
        ]
        if not discovered:
            raise InputError(
                "requested edition was not found; available editions: "
                + ", ".join(name for name, _ in discover_editions(source_root))
            )

    editions: list[dict[str, Any]] = []
    map_catalog: list[dict[str, Any]] = []
    for edition_name, edition_path in discovered:
        edition_map_number = 0
        files = [_inventory_file(path, source_root) for path in _iter_regular_files(edition_path)]
        archives: list[dict[str, Any]] = []
        stock_groups: list[list[dict[str, Any]]] | None = None
        stock_status: dict[str, Any] | None = None
        executable_path = _find_casefolded(edition_path, "rich4.exe")
        if executable_path is not None and edition_name in STOCK_TABLE_VA:
            executable_record = next(
                record
                for record in files
                if record["path"] == _path_for_json(executable_path, source_root)
            )
            try:
                stock_groups = parse_stock_groups(executable_path, edition=edition_name)
                stock_status = {
                    "status": "available",
                    "source_file": executable_record["path"],
                    "source_file_sha256": executable_record["sha256"],
                    "group_count": len(stock_groups),
                    "row_count": len(stock_groups) * STOCK_ROW_COUNT,
                }
            except FormatError as exc:
                # Map extraction remains useful when a local executable is a
                # different build.  Preserve the failure as inventory
                # metadata instead of fabricating stock rows.
                stock_status = {
                    "status": "invalid",
                    "source_file": executable_record["path"],
                    "source_file_sha256": executable_record["sha256"],
                    "error": str(exc),
                }
        elif executable_path is not None:
            stock_status = {
                "status": "unsupported_edition",
                "source_file": _path_for_json(executable_path, source_root),
            }
        map_path = _find_casefolded(edition_path, "map.mkf")
        if map_path is None:
            raise InputError(f"edition {edition_name} lost its map.mkf during import")
        for file_record in files:
            file_path = source_root / file_record["path"]
            if file_path.suffix.lower() != ".mkf":
                continue
            archive = parse_mkf(file_path)
            archives.append(_archive_json(archive, source_root))
            if file_path.resolve() != map_path.resolve():
                continue
            for entry in archive.entries:
                if not entry.is_stored:
                    continue
                payload = archive.payload(entry, decoded=True)
                try:
                    parsed = parse_map_payload(
                        payload,
                        edition=edition_name,
                        archive_path=_path_for_json(file_path, source_root),
                        entry_index=entry.index,
                    )
                except FormatError:
                    # Most map.mkf records are image/audio resources.  A valid
                    # map candidate is recognized by its complete table spans.
                    continue
                edition_map_number += 1
                parsed["map_number"] = edition_map_number
                parsed["source_file_sha256"] = file_record["sha256"]
                if stock_groups is not None and edition_map_number <= len(stock_groups):
                    parsed["stock_rows"] = _link_stock_rows(
                        stock_groups[edition_map_number - 1], parsed["companies"]
                    )
                if extract_map_payloads:
                    filename = f"map-{edition_map_number:02d}.bin"
                    relative = Path("raw") / _safe_component(edition_name) / filename
                    target = output_root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    temporary = target.with_name(target.name + ".tmp")
                    try:
                        temporary.write_bytes(payload)
                        os.replace(temporary, target)
                    except OSError as exc:
                        try:
                            temporary.unlink()
                        except OSError:
                            pass
                        raise InputError(f"cannot write extracted map {target}: {exc}") from exc
                    parsed["payload_file"] = relative.as_posix()
                map_catalog.append(parsed)
        edition_record: dict[str, Any] = {
            "name": edition_name,
            "path": _path_for_json(edition_path, source_root),
            "files": files,
            "archives": archives,
        }
        if stock_status is not None:
            edition_record["stock"] = stock_status
        editions.append(edition_record)

    manifest: dict[str, Any] = {
        "schema": "richman4.original-assets/v1",
        "version": SCHEMA_VERSION,
        "tool_version": TOOL_VERSION,
        "source_name": source_root.name,
        "editions": editions,
        "maps": {
            "count": len(map_catalog),
            "catalog_file": "maps/catalog.json",
            "extracted_payloads": extract_map_payloads,
        },
    }
    output_root.mkdir(parents=True, exist_ok=True)
    _write_json(output_root / "manifest.json", manifest)
    _write_json(
        output_root / "maps/catalog.json",
        {
            "schema": "richman4.map-catalog/v1",
            "version": SCHEMA_VERSION,
            "count": len(map_catalog),
            "maps": map_catalog,
        },
    )
    return manifest


def _format_summary(manifest: dict[str, Any]) -> str:
    editions = manifest["editions"]
    files = sum(len(edition["files"]) for edition in editions)
    archives = sum(len(edition["archives"]) for edition in editions)
    maps = manifest["maps"]["count"]
    edition_names = ", ".join(edition["name"] for edition in editions)
    return f"Imported {maps} map(s) from {edition_names}; inventoried {files} file(s) and {archives} MKF archive(s)."


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Inventory a local Richman 4 installation and decode uncompressed map resources."
    )
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="owner-provided installation root, or one folder containing map.mkf",
    )
    parser.add_argument(
        "--output",
        "--out",
        type=Path,
        default=Path(".local/imported-original"),
        help="local generated output directory (default: .local/imported-original)",
    )
    parser.add_argument(
        "--edition",
        action="append",
        metavar="NAME",
        help="limit import to an edition folder; may be repeated",
    )
    parser.add_argument(
        "--extract-map-payloads",
        "--extract",
        action="store_true",
        help="also write raw uncompressed map payloads below output/raw",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and inventory input without writing generated output",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.dry_run:
            # Use a temporary output path only for argument validation; no
            # files are written because import_source is not called below.
            source_root = args.source.expanduser().resolve()
            editions = discover_editions(source_root)
            if args.edition:
                requested = {value.casefold() for value in args.edition}
                editions = [
                    pair for pair in editions if pair[0].casefold() in requested
                ]
                if not editions:
                    raise InputError("no requested edition was found")
            maps = 0
            files = 0
            archives = 0
            for _, edition_path in editions:
                edition_files = list(_iter_regular_files(edition_path))
                files += len(edition_files)
                for path in edition_files:
                    if path.suffix.lower() != ".mkf":
                        continue
                    archive = parse_mkf(path)
                    archives += 1
                    if path.name.casefold() != "map.mkf":
                        continue
                    for entry in archive.entries:
                        if entry.is_stored:
                            try:
                                parse_map_payload(archive.payload(entry, decoded=True))
                            except FormatError:
                                continue
                            maps += 1
            print(f"Validated {maps} map(s); inventoried {files} file(s) and {archives} MKF archive(s).")
            return 0
        manifest = import_source(
            args.source,
            args.output,
            edition_filter=set(args.edition) if args.edition else None,
            extract_map_payloads=args.extract_map_payloads,
        )
        print(_format_summary(manifest))
        print(f"Generated local data at {args.output.expanduser().resolve()}")
        return 0
    except ImportErrorBase as exc:
        print(f"import_original.py: error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
