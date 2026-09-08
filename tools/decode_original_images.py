#!/usr/bin/env python3
"""Decode owner-provided Richman 4 MKF image resources into local PNG files.

The original installation and every generated image stay outside Git.  This
module contains an independent implementation of the MKF container and its
bounded adaptive-Huffman payload codec.  It intentionally does not import the
research repository's GPL implementation; the compact initial tables below
are generated from the format's observed tree layout.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from typing import Any, Iterable, Sequence
import uuid
import zlib


SCHEMA_VERSION = 1
TOOL_VERSION = "1"
MKF_HEADER_SIZE = 16
MKF_MIN_SIZE = 20
DEFAULT_OUTPUT = Path(".local/original-images")
DEFAULT_MAX_RESOURCE_BYTES = 64 * 1024 * 1024
DEFAULT_MAX_DIMENSION = 4096
DEFAULT_MAX_CHUNKS = 4096
PUBLISH_LOCK_NAME = ".images-publish-lock"
SPR_SIGNATURE = b"SPR\0"
SMP_SIGNATURE = b"SMP\0"
GND_SIGNATURE = b"GND\0"


class DecodeError(Exception):
    """Base class for input, container, codec, and image failures."""


class InputError(DecodeError):
    """The requested source or output cannot be used."""


class FormatError(DecodeError):
    """A container or image does not satisfy its bounded format."""


class CodecError(FormatError):
    """A compressed payload is truncated or internally invalid."""


class ImageError(FormatError):
    """A SPR/SMP resource cannot be represented safely as images."""


@dataclass(frozen=True)
class MkfEntry:
    """One absolute-offset MKF resource entry."""

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

    def payload(self, entry: MkfEntry) -> bytes:
        raw = self.data[entry.payload_offset : entry.payload_end]
        if len(raw) != entry.stored_size:
            raise FormatError(f"{self.path}: entry {entry.index} payload is truncated")
        return raw

    def as_dict(self, source_root: Path | None = None) -> dict[str, Any]:
        path = self.path.as_posix()
        if source_root is not None:
            try:
                path = self.path.relative_to(source_root).as_posix()
            except ValueError as exc:
                raise InputError(f"archive escaped source root: {self.path}") from exc
        return {
            "path": path,
            "size": len(self.data),
            "sha256": hashlib.sha256(self.data).hexdigest(),
            "index_table_offset": self.table_offset,
            "entry_count": len(self.entries),
            "entries": [entry.as_dict() for entry in self.entries],
        }


def _u32(data: bytes, offset: int, *, context: str) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise FormatError(f"{context}: expected u32 at offset {offset}")
    return struct.unpack_from("<I", data, offset)[0]


def parse_mkf(
    path: Path,
    data: bytes | None = None,
    *,
    max_resource_bytes: int = DEFAULT_MAX_RESOURCE_BYTES,
) -> MkfArchive:
    """Read and validate an MKF index and every resource span.

    The stored size must consume exactly the span between this entry and the
    next index value.  This keeps a malicious compressed-size field from
    reading bytes belonging to a later record or the index table.
    """

    if max_resource_bytes <= 0:
        raise ValueError("max_resource_bytes must be positive")
    if data is None:
        try:
            data = path.read_bytes()
        except OSError as exc:
            raise InputError(f"cannot read {path}: {exc}") from exc
    if len(data) < MKF_MIN_SIZE:
        raise FormatError(f"{path}: MKF is too small ({len(data)} bytes)")
    table_offset = _u32(data, 0, context=str(path))
    if table_offset < 4 or table_offset > len(data) - 4:
        raise FormatError(f"{path}: index table offset {table_offset} is outside file")
    table_bytes = len(data) - table_offset
    if table_bytes % 4:
        raise FormatError(f"{path}: index table length is not divisible by four")
    starts = struct.unpack_from(f"<{table_bytes // 4}I", data, table_offset)
    if not starts or starts[0] != 4:
        raise FormatError(f"{path}: first resource must start at offset 4")

    entries: list[MkfEntry] = []
    previous = -1
    for index, start in enumerate(starts):
        if start <= previous:
            raise FormatError(f"{path}: resource starts are not strictly increasing")
        previous = start
        next_start = starts[index + 1] if index + 1 < len(starts) else table_offset
        if start < 4 or start >= table_offset or next_start > table_offset:
            raise FormatError(f"{path}: resource {index} lies outside data region")
        if start + MKF_HEADER_SIZE > next_start:
            raise FormatError(f"{path}: resource {index} has no complete header")
        uncompressed, stored, image_offset, image_size = struct.unpack_from(
            "<4I", data, start
        )
        if uncompressed > max_resource_bytes:
            raise FormatError(
                f"{path}: resource {index} decoded size {uncompressed} exceeds "
                f"limit {max_resource_bytes}"
            )
        payload_offset = start + MKF_HEADER_SIZE
        payload_end = payload_offset + stored
        if payload_end != next_start:
            raise FormatError(
                f"{path}: resource {index} stored size {stored} does not match "
                f"its table span {next_start - payload_offset}"
            )
        if image_offset > uncompressed or image_size > uncompressed - image_offset:
            raise FormatError(
                f"{path}: resource {index} image range exceeds decoded size"
            )
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
    return MkfArchive(
        path=path, data=data, table_offset=table_offset, entries=tuple(entries)
    )


class _BitReader:
    """LSB-first reader with no implicit reads past the compressed payload."""

    def __init__(self, data: bytes):
        self.data = data
        self.bitpos = 0

    def _require(self, count: int) -> None:
        if count < 0 or self.bitpos + count > len(self.data) * 8:
            raise CodecError(
                f"compressed payload ends at bit {len(self.data) * 8}, "
                f"needed bit {self.bitpos + count}"
            )

    def read_bit(self) -> int:
        self._require(1)
        value = (self.data[self.bitpos // 8] >> (self.bitpos % 8)) & 1
        self.bitpos += 1
        return value

    def peek(self, count: int) -> int:
        self._require(count)
        value = 0
        for shift in range(count):
            value |= (
                (self.data[(self.bitpos + shift) // 8] >> ((self.bitpos + shift) % 8))
                & 1
            ) << shift
        return value

    def skip(self, count: int) -> None:
        self._require(count)
        self.bitpos += count


def _initial_huffman_tables() -> tuple[list[int], list[int], list[int]]:
    """Construct the fixed 321-symbol tree without embedding GPL C tables."""

    # The source tree has 321 live symbols (0..320).  The final sentinel leaf
    # is retained by the tree's weight table, while tab2/tab3 are represented
    # in one contiguous word array because the original update routine uses
    # the tab3 -> tab4 tail as a single addressable region.
    weights = (
        [1] * 321
        + [2] * 160
        + [3]
        + [4] * 79
        + [5]
        + [8] * 39
        + [9]
        + [16] * 19
        + [17]
        + [32] * 9
        + [33]
        + [64] * 4
        + [65]
        + [128] * 2
        + [193, 321, 0xFFFF]
    )
    if len(weights) != 642:
        raise AssertionError("invalid initial weight table")

    # tab2 is the child-address table.  Entries 0..320 lead to the live leaf
    # range; entries 321..640 lead to the internal-node range.
    tab2 = [1282 + 2 * i for i in range(321)] + [4 * i for i in range(320)]
    # tab3 is the parent-address table for internal nodes, followed directly
    # by tab4's symbol-to-leaf-address map.  Keeping this contiguous is
    # necessary because valid swaps write through the tab3 tail into tab4.
    tab3 = [642 + 2 * (i // 2) for i in range(640)] + [0]
    tab4 = [2 * i for i in range(321)] + [0]
    tree = tab3 + tab4
    if len(tab2) != 641 or len(tree) != 963:
        raise AssertionError("invalid initial tree tables")
    return weights, tab2, tree


def _distance_tables() -> tuple[list[int], list[int]]:
    """Generate the fixed distance-prefix tables from their bit layout."""

    bit_count: list[int] = []
    high: list[int] = []
    for value in range(256):
        block, low = divmod(value, 16)
        if low == 0:
            bit_count.append(8)
            high.append(63 - block)
        elif low in (7, 15):
            bit_count.append(3)
            high.append(0)
        elif low in (3, 11, 13):
            bit_count.append(4)
            high.append(3 - {3: 0, 11: 1, 13: 2}[low])
        elif low in (1, 5, 9, 14):
            bit_count.append(5)
            high.append(11 - 4 * (block % 2) - {1: 0, 5: 1, 9: 2, 14: 3}[low])
        elif low in (2, 6, 10):
            bit_count.append(6)
            high.append(23 - 3 * (block % 4) - {2: 0, 6: 1, 10: 2}[low])
        elif low in (4, 8, 12):
            bit_count.append(7)
            high.append(47 - 3 * (block % 8) - {4: 0, 8: 1, 12: 2}[low])
        else:
            raise AssertionError(f"unhandled distance prefix {value:#x}")
    return bit_count, high


_DISTANCE_BITS, _DISTANCE_HIGH = _distance_tables()


def _update_huffman_symbol(
    symbol: int, weights: list[int], tab2: list[int], tree: list[int]
) -> None:
    if symbol < 0 or symbol > 320:
        raise CodecError(f"decoded symbol {symbol} is outside the 321-symbol alphabet")
    ebx = tree[641 + symbol]
    while True:
        pos = ebx // 2
        if not 0 <= pos < len(weights):
            raise CodecError(f"invalid Huffman node address {ebx}")
        weights[pos] += 1
        ax = weights[pos]
        if ax <= weights[pos + 1]:
            ebx = tree[pos]
            if not ebx:
                return
            continue

        destination = pos + 1
        target_weight = ax - 1
        while destination < len(weights) and weights[destination] == target_weight:
            destination += 1
        if destination >= len(weights):
            raise CodecError("Huffman weight table has no swap destination")
        destination -= 1

        old_ax = ax
        ax = weights[destination]
        weights[destination] = old_ax
        weights[pos] = ax

        ax = tab2[pos]
        cx = tab2[destination]
        if cx % 2 or cx // 2 >= len(tree):
            raise CodecError(f"invalid Huffman child address {cx}")
        tree[cx // 2] = ebx
        if cx < 0x502:
            tree[cx // 2 + 1] = ebx
        if ax % 2 or ax // 2 >= len(tree):
            raise CodecError(f"invalid Huffman child address {ax}")
        # ``destination`` is the index used by the original `_edi / 2`
        # expression: `_edi` is a byte offset from tab1[1].
        replacement = destination * 2
        tree[ax // 2] = replacement
        if ax < 0x502:
            tree[ax // 2 + 1] = replacement
        tab2[pos] = cx
        tab2[destination] = ax
        ebx = tree[destination]
        if not ebx:
            return


def _normalize_huffman_tables(
    weights: list[int], tab2: list[int], tree: list[int]
) -> None:
    """Apply the reference decoder's periodic adaptive-tree rescale."""

    # The original keeps the root below 0x8000.  Before halving all weights,
    # it replays one normal update for each odd-weight leaf; that preserves
    # the tree ordering while making every weight even.
    for symbol in range(321):
        leaf_address = tree[641 + symbol]
        if weights[leaf_address // 2] & 1:
            _update_huffman_symbol(symbol, weights, tab2, tree)
    for index in range(641):
        weights[index] >>= 1


def _decode_huffman_symbol(reader: _BitReader, tab2: list[int]) -> int:
    node = 640
    while True:
        if not 0 <= node < len(tab2):
            raise CodecError(f"invalid Huffman node {node}")
        child = tab2[node] // 2
        if child >= 641:
            symbol = child - 641
            if not 0 <= symbol <= 320:
                raise CodecError(f"decoded symbol {symbol} is outside alphabet")
            return symbol
        if child < 0 or child + 1 >= 641:
            raise CodecError(f"invalid Huffman child {child}")
        if reader.read_bit():
            child += 1
        node = child


def decompress_private(payload: bytes, decoded_size: int) -> bytes:
    """Decode one private payload into exactly ``decoded_size`` bytes.

    The game stops once the declared output size is filled; the private end
    marker is accepted when encountered before that point only if the output is
    already complete.  Every logical bit consumed still belongs to ``payload``
    even though the original C routine loads an over-reading 32-bit word.
    """

    if decoded_size < 0:
        raise CodecError("negative decoded size")
    if decoded_size == 0:
        return b""
    weights, tab2, tree = _initial_huffman_tables()
    reader = _BitReader(payload)
    output = bytearray()

    while len(output) < decoded_size:
        symbol = _decode_huffman_symbol(reader, tab2)
        if weights[640] == 0x8000:
            _normalize_huffman_tables(weights, tab2, tree)
        _update_huffman_symbol(symbol, weights, tab2, tree)
        if symbol & 0xFF00 == 0:
            output.append(symbol & 0xFF)
            continue

        # Distance coding consumes cl+6 bits.  ``peek`` is bounded, avoiding
        # the original decoder's unaligned 32-bit read past the resource.
        prefix = reader.peek(8)
        bit_count = _DISTANCE_BITS[prefix]
        distance_high = _DISTANCE_HIGH[prefix]
        distance_bits = reader.peek(bit_count + 6)
        low_byte = ((distance_bits >> bit_count) << 2) & 0xFF
        distance = ((distance_high << 8) | low_byte) >> 2
        reader.skip(bit_count + 6)
        if distance == 0xFFF:
            if len(output) != decoded_size:
                raise CodecError("end marker arrived before decoded size was filled")
            break

        length = symbol - 0xFD
        source_index = len(output) - 1 - distance
        if source_index < 0 or source_index >= len(output):
            raise CodecError(
                f"invalid back-reference distance {distance} at output offset {len(output)}"
            )
        emit = min(length, decoded_size - len(output))
        for index in range(emit):
            output.append(output[source_index + index])

    if len(output) != decoded_size:
        raise CodecError(
            f"decoded {len(output)} bytes, expected declared size {decoded_size}"
        )
    return bytes(output)


def decode_entry(archive: MkfArchive, entry: MkfEntry) -> bytes:
    payload = archive.payload(entry)
    if entry.is_stored:
        decoded = payload
    else:
        decoded = decompress_private(payload, entry.uncompressed_size)
    if len(decoded) != entry.uncompressed_size:
        raise CodecError(
            f"{archive.path}: entry {entry.index} decoded size {len(decoded)} "
            f"does not equal {entry.uncompressed_size}"
        )
    return decoded


@dataclass(frozen=True)
class VisualChunk:
    index: int
    width: int
    height: int
    x: int
    y: int
    pixels: bytes


@dataclass(frozen=True)
class VisualResource:
    signature: str
    chunk_count: int
    start_offset: int
    palette: bytes | None
    chunks: tuple[VisualChunk, ...]


def _checked_product(values: Iterable[int], *, context: str, limit: int) -> int:
    result = 1
    for value in values:
        if value < 0:
            raise ImageError(f"{context}: negative dimension or size")
        result *= value
        if result > limit:
            raise ImageError(f"{context}: decoded pixel data exceeds limit {limit}")
    return result


def parse_visual_resource(
    decoded: bytes,
    entry: MkfEntry,
    *,
    max_dimension: int = DEFAULT_MAX_DIMENSION,
    max_chunks: int = DEFAULT_MAX_CHUNKS,
) -> VisualResource | None:
    """Parse a SPR/SMP resource and validate all chunk graph bounds."""

    if len(decoded) < 4:
        return None
    signature = decoded[:4]
    if signature not in (SPR_SIGNATURE, SMP_SIGNATURE):
        return None
    if len(decoded) < 12:
        raise ImageError("visual header is truncated")
    if (
        entry.image_data_offset > len(decoded)
        or entry.image_data_size > len(decoded) - entry.image_data_offset
    ):
        raise ImageError("visual image metadata is outside decoded resource")
    chunk_count, start_offset = struct.unpack_from("<II", decoded, 4)
    if chunk_count == 0 or chunk_count > max_chunks:
        raise ImageError(f"visual chunk count {chunk_count} exceeds limit")
    table_end = 12 + chunk_count * 12
    if (
        table_end > len(decoded)
        or start_offset < table_end
        or start_offset > len(decoded)
    ):
        raise ImageError("visual chunk table or start offset is outside resource")

    raw_chunks: list[tuple[int, int, int, int, int]] = []
    total_graph = 0
    for index in range(chunk_count):
        width, height, x, y, graph_size = struct.unpack_from(
            "<hhhhI", decoded, 12 + index * 12
        )
        if width <= 0 or height <= 0 or width > max_dimension or height > max_dimension:
            raise ImageError(
                f"visual chunk {index} dimensions {width}x{height} exceed limit"
            )
        bytes_per_pixel = 1 if signature == SPR_SIGNATURE else 2
        expected = _checked_product(
            (width, height, bytes_per_pixel),
            context=f"visual chunk {index}",
            limit=len(decoded),
        )
        if graph_size != expected:
            raise ImageError(
                f"visual chunk {index} graph size {graph_size} does not equal {expected}"
            )
        total_graph += graph_size
        if total_graph > len(decoded):
            raise ImageError("visual graph data exceeds decoded resource")
        raw_chunks.append((width, height, x, y, graph_size))

    palette: bytes | None
    if signature == SPR_SIGNATURE:
        if start_offset + 512 > len(decoded):
            raise ImageError("SPR palette is outside decoded resource")
        if entry.image_data_offset != start_offset or entry.image_data_size != 512:
            raise ImageError("SPR image metadata does not describe its palette")
        graph_start = start_offset + 512
        palette = decoded[start_offset : start_offset + 512]
    else:
        if (
            entry.image_data_offset != start_offset
            or entry.image_data_size != total_graph
        ):
            raise ImageError("SMP image metadata does not describe its graph data")
        graph_start = start_offset
        palette = None
    graph_end = graph_start + total_graph
    if graph_end != len(decoded):
        raise ImageError(
            f"visual graph end {graph_end} does not equal decoded size {len(decoded)}"
        )

    chunks: list[VisualChunk] = []
    cursor = graph_start
    for index, (width, height, x, y, graph_size) in enumerate(raw_chunks):
        pixels = decoded[cursor : cursor + graph_size]
        if len(pixels) != graph_size:
            raise ImageError(f"visual chunk {index} pixel data is truncated")
        chunks.append(VisualChunk(index, width, height, x, y, pixels))
        cursor += graph_size
    return VisualResource(
        signature=signature[:3].decode("ascii"),
        chunk_count=chunk_count,
        start_offset=start_offset,
        palette=palette,
        chunks=tuple(chunks),
    )


def _expand5(value: int) -> int:
    return (value << 3) | (value >> 2)


def _word_to_rgb(word: int, pixel_format: str) -> tuple[int, int, int]:
    if pixel_format == "rgb555":
        red, green, blue = (word >> 10) & 0x1F, (word >> 5) & 0x1F, word & 0x1F
        return _expand5(red), _expand5(green), _expand5(blue)
    if pixel_format == "rgb565":
        red, green, blue = (word >> 11) & 0x1F, (word >> 5) & 0x3F, word & 0x1F
        return _expand5(red), (green << 2) | (green >> 4), _expand5(blue)
    if pixel_format == "swapped":
        red, green, blue = word & 0x1F, (word >> 5) & 0x1F, (word >> 10) & 0x1F
        return _expand5(red), _expand5(green), _expand5(blue)
    if pixel_format == "rgb444":
        red, green, blue = (word >> 8) & 0xF, (word >> 4) & 0xF, word & 0xF
        return red * 17, green * 17, blue * 17
    raise ValueError(f"unknown pixel format {pixel_format}")


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(
    path: Path,
    chunk: VisualChunk,
    resource: VisualResource,
    *,
    pixel_format: str,
    transparent_index_zero: bool = True,
    transparent_word_zero: bool = False,
) -> None:
    """Write one chunk as a deterministic RGBA PNG using only zlib."""

    rows = bytearray()
    if resource.signature == "SPR":
        assert resource.palette is not None
        palette = [
            _word_to_rgb(
                struct.unpack_from("<H", resource.palette, offset)[0], pixel_format
            )
            for offset in range(0, 512, 2)
        ]
        for row in range(chunk.height):
            rows.append(0)
            start = row * chunk.width
            for index in chunk.pixels[start : start + chunk.width]:
                red, green, blue = palette[index]
                alpha = 0 if transparent_index_zero and index == 0 else 255
                rows.extend((red, green, blue, alpha))
    else:
        for row in range(chunk.height):
            rows.append(0)
            start = row * chunk.width * 2
            for offset in range(start, start + chunk.width * 2, 2):
                word = struct.unpack_from("<H", chunk.pixels, offset)[0]
                red, green, blue = _word_to_rgb(word, pixel_format)
                alpha = 0 if transparent_word_zero and word == 0 else 255
                rows.extend((red, green, blue, alpha))
    payload = bytearray(b"\x89PNG\r\n\x1a\n")
    payload.extend(
        _png_chunk(
            b"IHDR", struct.pack(">IIBBBBB", chunk.width, chunk.height, 8, 6, 0, 0, 0)
        )
    )
    payload.extend(_png_chunk(b"IDAT", zlib.compress(bytes(rows), level=9)))
    payload.extend(_png_chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(bytes(payload))
        os.replace(temporary, path)
    except OSError as exc:
        try:
            temporary.unlink()
        except OSError:
            pass
        raise InputError(f"cannot write {path}: {exc}") from exc


def _safe_component(value: str) -> str:
    cleaned = "".join(
        char if char.isalnum() or char in "._-" else "_" for char in value
    )
    return cleaned.strip("._") or "source"


def _find_casefolded(directory: Path, filename: str) -> Path | None:
    wanted = filename.casefold()
    try:
        for child in directory.iterdir():
            if (
                child.is_file()
                and not child.is_symlink()
                and child.name.casefold() == wanted
            ):
                return child
    except OSError as exc:
        raise InputError(f"cannot inspect {directory}: {exc}") from exc
    return None


def discover_editions(source: Path) -> list[tuple[str, Path]]:
    source = source.expanduser().resolve()
    if not source.is_dir():
        raise InputError(f"source is not a directory: {source}")
    direct_map = _find_casefolded(source, "map.mkf")
    if direct_map is not None:
        return [(source.name, source)]
    editions: list[tuple[str, Path]] = []
    try:
        children = sorted(source.iterdir(), key=lambda path: path.name.casefold())
    except OSError as exc:
        raise InputError(f"cannot inspect source {source}: {exc}") from exc
    for child in children:
        if (
            not child.is_dir()
            or child.is_symlink()
            or child.name.casefold() in {".git", "dxwnd", "media"}
        ):
            continue
        if _find_casefolded(child, "map.mkf") is not None:
            editions.append((child.name, child))
    if not editions:
        raise InputError(f"no installation folder containing map.mkf below {source}")
    return editions


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


def _archive_files(edition_path: Path) -> list[Path]:
    try:
        return sorted(
            (
                child
                for child in edition_path.iterdir()
                if child.is_file()
                and not child.is_symlink()
                and child.suffix.casefold() == ".mkf"
            ),
            key=lambda path: path.name.casefold(),
        )
    except OSError as exc:
        raise InputError(f"cannot inspect {edition_path}: {exc}") from exc


def _preflight_output_keys(
    discovered: Sequence[tuple[str, Path]], source: Path
) -> list[tuple[str, Path]]:
    """Return the archive snapshot whose sanitized destinations were checked."""

    seen: dict[tuple[str, str], str] = {}
    snapshot: list[tuple[str, Path]] = []
    for edition_name, edition_path in discovered:
        edition_component = _safe_component(edition_name)
        archives = _archive_files(edition_path)
        if not any(path.name.casefold() == "map.mkf" for path in archives):
            raise InputError(f"edition no longer contains map.mkf: {edition_path}")
        for archive_path in archives:
            archive_component = _safe_component(archive_path.stem)
            key = (edition_component.casefold(), archive_component.casefold())
            try:
                display_path = archive_path.relative_to(source).as_posix()
            except ValueError as exc:
                raise InputError(f"archive escaped source root: {archive_path}") from exc
            previous = seen.get(key)
            if previous is not None:
                raise InputError(
                    "sanitized image output collision: "
                    f"{previous} and {display_path}"
                )
            seen[key] = display_path
            snapshot.append((edition_name, archive_path))
    return snapshot


def _path_present(path: Path) -> bool:
    return path.exists() or path.is_symlink()


def _delete_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def _cleanup_path(path: Path) -> None:
    try:
        _delete_path(path)
    except OSError:
        pass


def _nearest_existing_parent(path: Path) -> Path:
    candidate = path
    while not _path_present(candidate):
        parent = candidate.parent
        if parent == candidate:
            break
        candidate = parent
    if candidate.is_dir() and not candidate.is_symlink():
        return candidate
    return candidate.parent


def _git_marker(path: Path) -> Path | None:
    for ancestor in (path, *path.parents):
        marker = ancestor / ".git"
        try:
            if _path_present(marker):
                return marker
        except OSError:
            continue
    return None


def _git_error_detail(result: subprocess.CompletedProcess[str]) -> str:
    detail = result.stderr.strip() or result.stdout.strip()
    return detail or f"git exited with status {result.returncode}"


def _git_worktree_root(output: Path) -> Path | None:
    existing_parent = _nearest_existing_parent(output)
    marker = _git_marker(existing_parent)
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(existing_parent),
                "rev-parse",
                "--show-toplevel",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        if marker is None:
            return None
        raise InputError(
            "cannot protect private image output: Git is unavailable while "
            f"a worktree was detected at {marker.parent}"
        ) from exc
    except OSError as exc:
        if marker is None:
            return None
        raise InputError(
            "cannot inspect private image output Git worktree at "
            f"{marker.parent}: {exc}"
        ) from exc
    if result.returncode != 0:
        if marker is None:
            return None
        raise InputError(
            "cannot inspect private image output Git worktree at "
            f"{marker.parent}: {_git_error_detail(result)}"
        )
    root_text = result.stdout.strip()
    if not root_text:
        if marker is None:
            return None
        raise InputError(
            "cannot inspect private image output Git worktree at "
            f"{marker.parent}: git returned no worktree root"
        )
    root = Path(root_text).expanduser().resolve()
    try:
        output.relative_to(root)
    except ValueError:
        return None
    return root


def _git_check_ignored(root: Path, path: Path, *, directory: bool = False) -> None:
    relative = path.relative_to(root).as_posix()
    if directory:
        relative += "/"
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(root),
                "check-ignore",
                "--quiet",
                "--no-index",
                "--",
                relative,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        raise InputError(
            f"cannot verify ignored private image output path {path}: {exc}"
        ) from exc
    if result.returncode == 0:
        return
    if result.returncode == 1:
        raise InputError(f"private image output inside a Git worktree must be ignored: {path}")
    raise InputError(
        f"cannot verify ignored private image output path {path}: "
        f"{_git_error_detail(result)}"
    )


def _git_tracked_managed_paths(root: Path, output: Path) -> list[str]:
    managed = [output / "images", output / "manifest.json"]
    relative = [path.relative_to(root).as_posix() for path in managed]
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--cached", "-z", "--", *relative],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        raise InputError(
            f"cannot inspect tracked private image output paths under {output}: {exc}"
        ) from exc
    if result.returncode != 0:
        raise InputError(
            f"cannot inspect tracked private image output paths under {output}: "
            f"{_git_error_detail(result)}"
        )
    return [path for path in result.stdout.split("\0") if path]


def assert_private_output(output: Path) -> None:
    """Reject unignored or already tracked managed paths inside Git worktrees."""
    output = output.expanduser().resolve()
    root = _git_worktree_root(output)
    if root is None:
        return
    # Staging and preserved rollback backups also contain private source data.
    _git_check_ignored(root, output, directory=True)
    _git_check_ignored(root, output / "images")
    _git_check_ignored(root, output / "manifest.json")
    tracked = _git_tracked_managed_paths(root, output)
    if tracked:
        raise InputError(
            "private image output contains already tracked managed content: "
            + ", ".join(tracked)
        )


def _publish_staged_images(
    staged_images: Path, staged_manifest: Path, output: Path
) -> None:
    """Replace tool-owned images and manifest together, restoring on failure."""

    images = output / "images"
    manifest = output / "manifest.json"
    publish_lock = output / PUBLISH_LOCK_NAME
    try:
        publish_lock.mkdir(mode=0o700)
    except FileExistsError as exc:
        raise InputError(
            f"cannot publish decoded images: publish lock already exists: {publish_lock}"
        ) from exc
    except OSError as exc:
        raise InputError(f"cannot create publish lock {publish_lock}: {exc}") from exc
    image_backup = output / f".images-backup-{uuid.uuid4().hex}"
    manifest_backup = output / f".manifest-backup-{uuid.uuid4().hex}"
    old_images_moved = False
    old_manifest_moved = False
    images_installed = False
    manifest_installed = False
    try:
        if _path_present(manifest):
            os.replace(manifest, manifest_backup)
            old_manifest_moved = True
        if _path_present(images):
            os.replace(images, image_backup)
            old_images_moved = True
        os.replace(staged_images, images)
        images_installed = True
        os.replace(staged_manifest, manifest)
        manifest_installed = True
    except OSError as exc:
        rollback_errors: list[str] = []
        manifest_clear = not _path_present(manifest)
        if manifest_installed:
            try:
                _delete_path(manifest)
                manifest_clear = not _path_present(manifest)
            except OSError as rollback_exc:
                rollback_errors.append(f"new manifest cleanup failed: {rollback_exc}")

        image_rollback_ok = manifest_clear
        if images_installed:
            try:
                _delete_path(images)
            except OSError as rollback_exc:
                rollback_errors.append(f"new image cleanup failed: {rollback_exc}")
                image_rollback_ok = False
        if old_images_moved and image_rollback_ok:
            if _path_present(images):
                image_rollback_ok = False
                rollback_errors.append("new image remains during rollback")
            else:
                try:
                    os.replace(image_backup, images)
                except OSError as rollback_exc:
                    image_rollback_ok = False
                    rollback_errors.append(f"image restore failed: {rollback_exc}")
        if old_manifest_moved and image_rollback_ok and not _path_present(manifest):
            try:
                os.replace(manifest_backup, manifest)
            except OSError as rollback_exc:
                rollback_errors.append(f"manifest restore failed: {rollback_exc}")
        detail = f"cannot publish decoded images: {exc}"
        if rollback_errors:
            detail += "; " + "; ".join(rollback_errors)
        raise InputError(detail) from exc
    else:
        if old_images_moved:
            _cleanup_path(image_backup)
        if old_manifest_moved:
            _cleanup_path(manifest_backup)
    finally:
        active_error = sys.exc_info()[1]
        try:
            publish_lock.rmdir()
        except OSError as lock_exc:
            if active_error is None:
                raise InputError(
                    f"cannot release publish lock {publish_lock}: {lock_exc}"
                ) from lock_exc
            raise InputError(
                f"{active_error}; cannot release publish lock {publish_lock}: {lock_exc}"
            ) from active_error


def assert_disjoint_paths(source: Path, output: Path) -> None:
    """Reject lexical and filesystem-identity ancestry before creating output."""
    if source == output or source in output.parents or output in source.parents:
        raise InputError("image output and original source must not overlap")
    # resolve() retains case aliases on default macOS APFS. Compare the actual
    # directory identities, including existing ancestors of a new output path.
    for anchor, descendant in [(source, output), (output, source)]:
        try:
            identity = anchor.stat()
        except FileNotFoundError:
            continue
        for candidate in [descendant, *descendant.parents]:
            try:
                other = candidate.stat()
            except FileNotFoundError:
                continue
            if (identity.st_dev, identity.st_ino) == (other.st_dev, other.st_ino):
                raise InputError("image output and original source must not overlap")


def decode_source(
    source: Path,
    output: Path,
    *,
    editions: set[str] | None = None,
    max_resource_bytes: int = DEFAULT_MAX_RESOURCE_BYTES,
    max_dimension: int = DEFAULT_MAX_DIMENSION,
    max_chunks: int = DEFAULT_MAX_CHUNKS,
    pixel_format: str = "rgb555",
    transparent_index_zero: bool = True,
    transparent_word_zero: bool = False,
) -> dict[str, Any]:
    """Decode all bounded SPR/SMP chunks from an owner installation."""

    source = source.expanduser().resolve()
    output = output.expanduser().resolve()
    assert_disjoint_paths(source, output)
    discovered = discover_editions(source)
    if editions:
        wanted = {value.casefold() for value in editions}
        missing = wanted - {name.casefold() for name, _ in discovered}
        if missing:
            raise InputError("requested editions were not found: " + ", ".join(sorted(missing)))
        discovered = [
            (name, path) for name, path in discovered if name.casefold() in wanted
        ]

    archive_snapshot = _preflight_output_keys(discovered, source)
    assert_private_output(output)
    try:
        output.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise InputError(f"cannot create output directory {output}: {exc}") from exc
    try:
        staging_images = Path(
            tempfile.mkdtemp(prefix=".images-staging-", dir=output)
        )
    except OSError as exc:
        raise InputError(f"cannot create image staging directory {output}: {exc}") from exc
    staged_manifest = output / f".manifest-staging-{uuid.uuid4().hex}.json"
    try:
        archive_records: list[dict[str, Any]] = []
        visual_records: list[dict[str, Any]] = []
        for edition_name, archive_path in archive_snapshot:
            edition_dir = _safe_component(edition_name)
            archive = parse_mkf(archive_path, max_resource_bytes=max_resource_bytes)
            archive_records.append(archive.as_dict(source))
            archive_name = _safe_component(archive_path.stem)
            for entry in archive.entries:
                decoded = decode_entry(archive, entry)
                visual = parse_visual_resource(
                    decoded,
                    entry,
                    max_dimension=max_dimension,
                    max_chunks=max_chunks,
                )
                if visual is None:
                    continue
                resource_dir = (
                    staging_images
                    / edition_dir
                    / archive_name
                    / f"resource-{entry.index:04d}"
                )
                image_records: list[dict[str, Any]] = []
                for chunk in visual.chunks:
                    png_path = resource_dir / f"chunk-{chunk.index:04d}.png"
                    write_png(
                        png_path,
                        chunk,
                        visual,
                        pixel_format=pixel_format,
                        transparent_index_zero=transparent_index_zero,
                        transparent_word_zero=transparent_word_zero,
                    )
                    image_records.append(
                        {
                            "chunk_index": chunk.index,
                            "path": (
                                Path("images")
                                / png_path.relative_to(staging_images)
                            ).as_posix(),
                            "width": chunk.width,
                            "height": chunk.height,
                            "x": chunk.x,
                            "y": chunk.y,
                            "sha256": hashlib.sha256(png_path.read_bytes()).hexdigest(),
                        }
                    )
                visual_records.append(
                    {
                        "edition": edition_name,
                        "archive": archive_path.relative_to(source).as_posix(),
                        "archive_sha256": hashlib.sha256(archive.data).hexdigest(),
                        "resource_index": entry.index,
                        "signature": visual.signature,
                        "uncompressed_size": entry.uncompressed_size,
                        "stored_size": entry.stored_size,
                        "compression": entry.compression,
                        "image_data_offset": entry.image_data_offset,
                        "image_data_size": entry.image_data_size,
                        "chunk_count": visual.chunk_count,
                        "start_offset": visual.start_offset,
                        "pixel_format": pixel_format,
                        "transparent_index_zero": transparent_index_zero
                        if visual.signature == "SPR"
                        else None,
                        "transparent_word_zero": transparent_word_zero
                        if visual.signature == "SMP"
                        else None,
                        "images": image_records,
                    }
                )

        manifest = {
            "schema": "richman4.original-images/v1",
            "version": SCHEMA_VERSION,
            "tool_version": TOOL_VERSION,
            "source_name": source.name,
            "limits": {
                "max_resource_bytes": max_resource_bytes,
                "max_dimension": max_dimension,
                "max_chunks": max_chunks,
            },
            "pixel_format": pixel_format,
            "transparent_index_zero": transparent_index_zero,
            "transparent_word_zero": transparent_word_zero,
            "archives": archive_records,
            "visual_resources": visual_records,
            "gnd_resources_skipped": True,
        }
        _write_json(staged_manifest, manifest)
        _publish_staged_images(staging_images, staged_manifest, output)
        return manifest
    finally:
        _cleanup_path(staging_images)
        _cleanup_path(staged_manifest)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Decode owner-provided Richman 4 MKF SPR/SMP resources into local PNG files."
    )
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="owner-provided installation root or edition folder",
    )
    parser.add_argument(
        "--output",
        "--out",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="local output directory (default: .local/original-images)",
    )
    parser.add_argument(
        "--edition",
        action="append",
        metavar="NAME",
        help="limit decoding to an edition; may be repeated",
    )
    parser.add_argument(
        "--max-resource-bytes",
        type=int,
        default=DEFAULT_MAX_RESOURCE_BYTES,
        help="maximum declared decoded resource size",
    )
    parser.add_argument(
        "--max-dimension",
        type=int,
        default=DEFAULT_MAX_DIMENSION,
        help="maximum SPR/SMP chunk width or height",
    )
    parser.add_argument(
        "--max-chunks",
        type=int,
        default=DEFAULT_MAX_CHUNKS,
        help="maximum chunks in one SPR/SMP resource",
    )
    parser.add_argument(
        "--pixel-format",
        choices=("rgb555", "rgb565", "swapped", "rgb444"),
        default="rgb555",
        help="16-bit source interpretation for palettes and SMP pixels",
    )
    parser.add_argument(
        "--opaque-index-zero",
        action="store_true",
        help="keep SPR palette index 0 opaque",
    )
    parser.add_argument(
        "--transparent-word-zero",
        action="store_true",
        help="treat SMP source word 0 as transparent",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if (
            args.max_resource_bytes <= 0
            or args.max_dimension <= 0
            or args.max_chunks <= 0
        ):
            raise InputError("size and chunk limits must be positive")
        manifest = decode_source(
            args.source,
            args.output,
            editions=set(args.edition) if args.edition else None,
            max_resource_bytes=args.max_resource_bytes,
            max_dimension=args.max_dimension,
            max_chunks=args.max_chunks,
            pixel_format=args.pixel_format,
            transparent_index_zero=not args.opaque_index_zero,
            transparent_word_zero=args.transparent_word_zero,
        )
        count = len(manifest["visual_resources"])
        chunks = sum(item["chunk_count"] for item in manifest["visual_resources"])
        print(f"Decoded {count} SPR/SMP resource(s), {chunks} chunk(s).")
        print(f"Generated local images at {args.output.expanduser().resolve()}")
        return 0
    except DecodeError as exc:
        print(f"decode_original_images.py: error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
