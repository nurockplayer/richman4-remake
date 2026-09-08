#!/usr/bin/env python3
"""Regression tests for the bounded original-image decoder."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import zlib


sys.path.insert(0, str(Path(__file__).resolve().parent))
import decode_original_images as decoder  # noqa: E402
from decode_original_images import (  # noqa: E402
    CodecError,
    FormatError,
    ImageError,
    InputError,
    MkfEntry,
    _preflight_output_keys,
    assert_private_output,
    decode_source,
    decompress_private,
    parse_mkf,
    parse_visual_resource,
    write_png,
)


def make_mkf(resources: list[tuple[bytes, int, int, int]]) -> bytes:
    """Build an MKF fixture from (payload, decoded size, image offset, size)."""

    body = bytearray(struct.pack("<I", 0))
    starts: list[int] = []
    for payload, decoded_size, image_offset, image_size in resources:
        starts.append(len(body))
        body.extend(
            struct.pack("<4I", decoded_size, len(payload), image_offset, image_size)
        )
        body.extend(payload)
    table_offset = len(body)
    body[0:4] = struct.pack("<I", table_offset)
    body.extend(struct.pack(f"<{len(starts)}I", *starts))
    return bytes(body)


def make_spr() -> bytes:
    start_offset = 12 + 12
    chunks = struct.pack("<hhhhI", 2, 1, 3, 4, 2)
    palette = bytearray(512)
    struct.pack_into("<H", palette, 2, 0x7C00)  # red in RGB555
    return (
        b"SPR\0"
        + struct.pack("<II", 1, start_offset)
        + chunks
        + bytes(palette)
        + bytes((0, 1))
    )


def make_smp() -> bytes:
    start_offset = 12 + 12
    chunks = struct.pack("<hhhhI", 1, 1, -2, 5, 2)
    return (
        b"SMP\0"
        + struct.pack("<II", 1, start_offset)
        + chunks
        + struct.pack("<H", 0x03E0)  # green in RGB555
    )


def initial_code(symbol: int) -> tuple[int, int]:
    """Find one symbol's initial-tree code as (LSB-first value, bit count)."""

    from decode_original_images import _initial_huffman_tables

    _weights, tab2, _tree = _initial_huffman_tables()

    def search(node: int, code: int, width: int) -> tuple[int, int] | None:
        child = tab2[node] // 2
        if child >= 641:
            return (code, width) if child - 641 == symbol else None
        found = search(child, code, width + 1)
        if found is not None:
            return found
        return search(child + 1, code | (1 << width), width + 1)

    result = search(640, 0, 0)
    if result is None:
        raise AssertionError(f"symbol {symbol} is absent from initial tree")
    return result


def pack_bits(*codes: tuple[int, int]) -> bytes:
    bits: list[int] = []
    for value, width in codes:
        bits.extend((value >> shift) & 1 for shift in range(width))
    result = bytearray((len(bits) + 7) // 8)
    for index, bit in enumerate(bits):
        result[index // 8] |= bit << (index % 8)
    return bytes(result)


def init_git_repo(path: Path, ignore: str = ".local/\n") -> None:
    path.mkdir(parents=True)
    subprocess.run(
        ["git", "init", "--quiet", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    (path / ".gitignore").write_text(ignore, encoding="utf-8")


def read_png_rgba(data: bytes) -> tuple[int, int, bytes]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise AssertionError("fixture is not a PNG")
    offset = 8
    width = height = None
    compressed = bytearray()
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + size]
        offset += 12 + size
        if kind == b"IHDR":
            width, height, depth, color_type, *_ = struct.unpack(">IIBBBBB", payload)
            if (depth, color_type) != (8, 6):
                raise AssertionError("fixture is not RGBA8")
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    if width is None or height is None:
        raise AssertionError("PNG has no IHDR")
    filtered = zlib.decompress(bytes(compressed))
    rows = bytearray()
    stride = width * 4
    for row in range(height):
        filter_type = filtered[row * (stride + 1)]
        if filter_type != 0:
            raise AssertionError("fixture used an unexpected PNG filter")
        start = row * (stride + 1) + 1
        rows.extend(filtered[start : start + stride])
    return width, height, bytes(rows)


class DecodeOriginalImagesTests(unittest.TestCase):
    def test_disappearing_edition_marker_preserves_previous_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            game = source / "Game"
            game.mkdir(parents=True)
            spr = make_spr()
            for name in ["map.mkf", "Panel.mkf"]:
                (game / name).write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            output = Path(temporary) / "output"
            decode_source(source, output)
            before = (output / "manifest.json").read_bytes()
            enumerate_original = decoder._archive_files

            def remove_marker(directory):
                (game / "map.mkf").unlink()
                return enumerate_original(directory)

            with patch.object(decoder, "_archive_files", side_effect=remove_marker):
                with self.assertRaisesRegex(InputError, "map.mkf"):
                    decode_source(source, output)
            self.assertEqual((output / "manifest.json").read_bytes(), before)

    def test_publish_uses_preflight_archive_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            game = source / "Game"
            game.mkdir(parents=True)
            spr = make_spr()
            (game / "map.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            original = game / "a b.mkf"
            original.write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            output = Path(temporary) / "output"
            enumerate_original = decoder._archive_files

            def changing_directory(directory):
                snapshot = enumerate_original(directory)
                (game / "a_b.mkf").write_bytes(original.read_bytes())
                return snapshot

            with patch.object(decoder, "_archive_files", side_effect=changing_directory):
                manifest = decode_source(source, output)
            self.assertEqual(len(manifest["archives"]), 2)
            for resource in manifest["visual_resources"]:
                for chunk in resource["images"]:
                    image = output / chunk["path"]
                    self.assertEqual(hashlib.sha256(image.read_bytes()).hexdigest(),
                                     chunk["sha256"])

    def test_each_requested_edition_must_exist(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            game = source / "Game"
            game.mkdir(parents=True)
            spr = make_spr()
            (game / "map.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            output = Path(temporary) / "output"
            with self.assertRaisesRegex(InputError, "multiversejoruney"):
                decode_source(source, output, editions={"Game", "MultiverseJoruney"})
            self.assertFalse(output.exists())
            manifest = decode_source(source, output, editions={"game"})
            self.assertEqual(len(manifest["visual_resources"]), 1)

    def test_default_local_output_is_allowed_in_git_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            init_git_repo(repository)
            source = repository / "source" / "Game"
            source.mkdir(parents=True)
            spr = make_spr()
            (source / "map.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            output = repository / decoder.DEFAULT_OUTPUT

            manifest = decode_source(repository / "source", output)

            self.assertEqual(len(manifest["visual_resources"]), 1)
            self.assertTrue((output / "manifest.json").is_file())
            outside = Path(temporary) / "outside" / "custom-output"
            assert_private_output(outside)
            self.assertFalse(outside.exists())
            self.assertTrue((output / "images").is_dir())

    def test_unignored_custom_git_output_fails_before_output_creation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            init_git_repo(repository)
            source = repository / "source" / "Game"
            source.mkdir(parents=True)
            spr = make_spr()
            (source / "map.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            output = repository / "review-output-check"

            with self.assertRaisesRegex(InputError, "ignored"):
                decode_source(repository / "source", output)

            self.assertFalse(output.exists())

    def test_ignored_children_do_not_protect_transient_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            init_git_repo(repository, "review-output-check/images\nreview-output-check/manifest.json\n")
            output = repository / "review-output-check"
            with self.assertRaisesRegex(InputError, "ignored"):
                assert_private_output(output)
            self.assertFalse(output.exists())

    def test_ignored_custom_git_output_is_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            init_git_repo(repository, ".local/\nreview-output-check/\n")
            source = repository / "source" / "Game"
            source.mkdir(parents=True)
            spr = make_spr()
            (source / "map.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            output = repository / "review-output-check"

            manifest = decode_source(repository / "source", output)

            self.assertEqual(len(manifest["visual_resources"]), 1)
            self.assertTrue((output / "manifest.json").is_file())

    def test_tracked_managed_output_fails_and_preserves_existing_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            init_git_repo(repository)
            source = repository / "source" / "Game"
            source.mkdir(parents=True)
            spr = make_spr()
            (source / "map.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            output = repository / decoder.DEFAULT_OUTPUT
            tracked_file = output / "images" / "tracked.png"
            tracked_file.parent.mkdir(parents=True)
            tracked_file.write_bytes(b"tracked sentinel")
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repository),
                    "add",
                    "-f",
                    "--",
                    str(tracked_file.relative_to(repository)),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            with self.assertRaisesRegex(InputError, "tracked"):
                decode_source(repository / "source", output)

            self.assertEqual(tracked_file.read_bytes(), b"tracked sentinel")
            self.assertFalse((output / "manifest.json").exists())

    def test_case_alias_output_cannot_replace_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            actual_output = Path(temporary) / "Output"
            source = actual_output / "images" / "Game"
            source.mkdir(parents=True)
            alias_output = Path(temporary) / "output"
            if not alias_output.exists() or not alias_output.samefile(actual_output):
                self.skipTest("requires a case-insensitive filesystem")
            original = make_mkf([(make_spr(), len(make_spr()), 24, 512)])
            archive = source / "map.mkf"
            archive.write_bytes(original)
            with self.assertRaises(InputError):
                decode_source(source, alias_output)
            self.assertEqual(archive.read_bytes(), original)
            self.assertFalse((actual_output / "manifest.json").exists())

    def test_output_cannot_replace_original_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            source = output / "images" / "Game"
            source.mkdir(parents=True)
            original = make_mkf([(make_spr(), len(make_spr()), 24, 512)])
            archive = source / "map.mkf"
            archive.write_bytes(original)
            with self.assertRaises(InputError):
                decode_source(source, output)
            self.assertEqual(archive.read_bytes(), original)
            self.assertFalse((output / "manifest.json").exists())
            for overlapping in [source, source / "derived", source.parent]:
                with self.assertRaises(InputError):
                    decode_source(source, overlapping)
                self.assertEqual(archive.read_bytes(), original)

    def test_concurrent_publish_does_not_mix_manifest_and_images(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            source_a = temporary_root / "source-a" / "Game"
            source_b = temporary_root / "source-b" / "Game"
            source_a.mkdir(parents=True)
            source_b.mkdir(parents=True)
            red_spr = make_spr()
            green_spr = bytearray(red_spr)
            struct.pack_into("<H", green_spr, 26, 0x03E0)
            for source, spr in ((source_a, red_spr), (source_b, bytes(green_spr))):
                (source / "Panel.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
                (source / "map.mkf").write_bytes(make_mkf([(b"plain", 5, 0, 0)]))
            output = (temporary_root / "decoded").resolve()
            first_publish_started = threading.Event()
            second_publish_done = threading.Event()
            release_first_publish = threading.Event()
            first_image_install_seen = False
            formal_mutations: list[str] = []
            worker_errors: list[tuple[str, BaseException]] = []
            real_replace = decoder.os.replace

            def replace_with_publish_barrier(
                source: os.PathLike[str], destination: os.PathLike[str]
            ) -> None:
                nonlocal first_image_install_seen
                destination_path = Path(destination)
                block_first_image = (
                    threading.current_thread().name == "publish-A"
                    and destination_path == output / "images"
                    and not first_image_install_seen
                )
                record_formal_mutation = (
                    first_publish_started.is_set()
                    and not release_first_publish.is_set()
                    and destination_path in {output / "images", output / "manifest.json"}
                    and threading.current_thread().name == "publish-B"
                )
                real_replace(source, destination)
                if record_formal_mutation:
                    formal_mutations.append(destination_path.name)
                if block_first_image:
                    first_image_install_seen = True
                    first_publish_started.set()
                    if not second_publish_done.wait(5):
                        raise OSError("second publish did not reach the barrier")
                    if not release_first_publish.wait(5):
                        raise OSError("first publish was not released")

            def decode_in_worker(name: str, source: Path) -> None:
                try:
                    decoder.decode_source(source, output)
                except BaseException as exc:  # noqa: BLE001
                    worker_errors.append((name, exc))
                finally:
                    if name == "publish-B":
                        second_publish_done.set()

            first_thread = threading.Thread(
                target=decode_in_worker, args=("publish-A", source_a), name="publish-A"
            )
            second_thread = threading.Thread(
                target=decode_in_worker, args=("publish-B", source_b), name="publish-B"
            )
            with patch.object(
                decoder.os, "replace", side_effect=replace_with_publish_barrier
            ):
                first_thread.start()
                try:
                    self.assertTrue(first_publish_started.wait(5))
                    self.assertTrue((output / decoder.PUBLISH_LOCK_NAME).is_dir())
                    blocked_image = next((output / "images").rglob("*.png")).read_bytes()
                    second_thread.start()
                    self.assertTrue(second_publish_done.wait(5))
                    self.assertEqual(formal_mutations, [])
                    self.assertTrue((output / decoder.PUBLISH_LOCK_NAME).is_dir())
                    self.assertEqual(
                        next((output / "images").rglob("*.png")).read_bytes(),
                        blocked_image,
                    )
                finally:
                    release_first_publish.set()
                    first_thread.join(5)
                    second_thread.join(5)
            self.assertFalse(first_thread.is_alive())
            self.assertFalse(second_thread.is_alive())
            self.assertEqual(len(worker_errors), 1)
            self.assertEqual(worker_errors[0][0], "publish-B")
            self.assertIsInstance(worker_errors[0][1], InputError)
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            image_entry = manifest["visual_resources"][0]["images"][0]
            image_path = output / image_entry["path"]
            self.assertEqual(
                image_entry["sha256"],
                hashlib.sha256(image_path.read_bytes()).hexdigest(),
            )
            self.assertFalse((output / decoder.PUBLISH_LOCK_NAME).exists())

    def test_existing_publish_lock_fails_closed_and_is_preserved(self) -> None:
        spr = make_spr()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            (root / "Panel.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (root / "map.mkf").write_bytes(make_mkf([(b"plain", 5, 0, 0)]))
            output = Path(temporary) / "decoded"
            output.mkdir()
            images = output / "images"
            images.mkdir()
            sentinel_image = images / "sentinel.bin"
            sentinel_image.write_bytes(b"previous image tree")
            manifest = output / "manifest.json"
            manifest.write_text("previous manifest\n", encoding="utf-8")
            publish_lock = output / decoder.PUBLISH_LOCK_NAME
            publish_lock.mkdir()

            with self.assertRaises(InputError):
                decoder.decode_source(root, output)

            self.assertTrue(publish_lock.is_dir())
            self.assertEqual(sentinel_image.read_bytes(), b"previous image tree")
            self.assertEqual(manifest.read_text(encoding="utf-8"), "previous manifest\n")
            self.assertFalse(any(output.glob(".images-staging-*")))
            self.assertFalse(any(output.glob(".manifest-staging-*.json")))

    def test_publish_lock_release_failure_is_reported_and_lock_remains(self) -> None:
        spr = make_spr()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            (root / "Panel.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (root / "map.mkf").write_bytes(make_mkf([(b"plain", 5, 0, 0)]))
            output = Path(temporary) / "decoded"
            publish_lock = output / decoder.PUBLISH_LOCK_NAME
            real_rmdir = decoder.Path.rmdir

            def fail_publish_lock_release(path: Path) -> None:
                if path.name == decoder.PUBLISH_LOCK_NAME:
                    raise OSError("publish lock release failed")
                real_rmdir(path)

            with patch.object(decoder.Path, "rmdir", new=fail_publish_lock_release):
                with self.assertRaisesRegex(InputError, "cannot release publish lock"):
                    decoder.decode_source(root, output)
            self.assertTrue(publish_lock.is_dir())
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            image_entry = manifest["visual_resources"][0]["images"][0]
            image_path = output / image_entry["path"]
            self.assertEqual(
                image_entry["sha256"],
                hashlib.sha256(image_path.read_bytes()).hexdigest(),
            )

    def test_late_corrupt_archive_preserves_previous_publish(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            output = Path(temporary) / "output"
            spr = make_spr()
            (root / "a.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (root / "map.mkf").write_bytes(make_mkf([(b"data", 4, 0, 0)]))
            manifest = decode_source(root, output)
            image_path = output / manifest["visual_resources"][0]["images"][0]["path"]
            previous_image = image_path.read_bytes()
            manifest_path = output / "manifest.json"
            previous_manifest = manifest_path.read_bytes()
            changed = bytearray(spr)
            struct.pack_into("<H", changed, 26, 0x03E0)
            (root / "a.mkf").write_bytes(make_mkf([(bytes(changed), len(changed), 24, 512)]))
            (root / "map.mkf").write_bytes(b"truncated")
            with self.assertRaises(FormatError):
                decode_source(root, output)
            self.assertEqual(image_path.read_bytes(), previous_image)
            self.assertEqual(manifest_path.read_bytes(), previous_manifest)

    def test_sanitized_archive_collision_fails_before_output_writes(self) -> None:
        spr = make_spr()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            for name in ("a b.mkf", "a_b.mkf"):
                (root / name).write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (root / "map.mkf").write_bytes(make_mkf([(b"plain", 5, 0, 0)]))
            output = Path(temporary) / "decoded"
            with self.assertRaises(InputError):
                decode_source(root, output)
            self.assertFalse(output.exists())

    def test_casefolded_archive_collision_is_rejected_by_preflight(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            first = root / "Panel.mkf"
            second = root / "Panel.MKF"
            with patch(
                "decode_original_images._archive_files",
                return_value=[first, second],
            ):
                with self.assertRaises(InputError):
                    _preflight_output_keys([("Game", root)], root)

    def test_removed_visual_archive_replaces_images_with_empty_publish(self) -> None:
        spr = make_spr()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            panel = root / "Panel.mkf"
            panel.write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (root / "map.mkf").write_bytes(make_mkf([(b"plain", 5, 0, 0)]))
            output = Path(temporary) / "decoded"
            decode_source(root, output)
            unrelated = output / "keep-me.txt"
            unrelated.write_text("preserve", encoding="utf-8")
            panel.unlink()
            manifest = decode_source(root, output)
            self.assertEqual(manifest["visual_resources"], [])
            self.assertTrue((output / "images").is_dir())
            self.assertEqual(list((output / "images").rglob("*.png")), [])
            self.assertEqual(unrelated.read_text(encoding="utf-8"), "preserve")
            self.assertEqual(
                json.loads((output / "manifest.json").read_text())[
                    "visual_resources"
                ],
                [],
            )

    def test_manifest_install_failure_rolls_back_matching_images_and_manifest(self) -> None:
        spr = make_spr()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            panel = root / "Panel.mkf"
            panel.write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (root / "map.mkf").write_bytes(make_mkf([(b"plain", 5, 0, 0)]))
            output = Path(temporary) / "decoded"
            decoder.decode_source(root, output)
            image_path = next((output / "images").rglob("*.png"))
            previous_image = image_path.read_bytes()
            manifest_path = output / "manifest.json"
            previous_manifest = manifest_path.read_bytes()
            real_replace = decoder.os.replace
            failed = False

            def fail_manifest_install(source: os.PathLike[str], destination: os.PathLike[str]) -> None:
                nonlocal failed
                if Path(destination).name == "manifest.json" and not failed:
                    failed = True
                    raise OSError("manifest install failed")
                real_replace(source, destination)

            with patch.object(decoder.os, "replace", side_effect=fail_manifest_install):
                with self.assertRaises(InputError):
                    decoder.decode_source(root, output)
            self.assertEqual(image_path.read_bytes(), previous_image)
            self.assertEqual(manifest_path.read_bytes(), previous_manifest)
            self.assertFalse((output / decoder.PUBLISH_LOCK_NAME).exists())

    def test_image_rollback_failure_leaves_manifest_absent_and_backups(self) -> None:
        spr = make_spr()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "Game"
            root.mkdir()
            panel = root / "Panel.mkf"
            panel.write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (root / "map.mkf").write_bytes(make_mkf([(b"plain", 5, 0, 0)]))
            output = Path(temporary) / "decoded"
            decoder.decode_source(root, output)
            real_replace = decoder.os.replace
            manifest_failed = False

            def fail_image_restore(source: os.PathLike[str], destination: os.PathLike[str]) -> None:
                nonlocal manifest_failed
                source_name = Path(source).name
                destination_name = Path(destination).name
                if destination_name == "manifest.json" and source_name.startswith(
                    ".manifest-staging-"
                ):
                    manifest_failed = True
                    raise OSError("manifest install failed")
                if manifest_failed and destination_name == "images" and source_name.startswith(
                    ".images-backup-"
                ):
                    raise OSError("image restore failed")
                real_replace(source, destination)

            with patch.object(decoder.os, "replace", side_effect=fail_image_restore):
                with self.assertRaises(InputError):
                    decoder.decode_source(root, output)
            self.assertFalse((output / "manifest.json").exists())
            self.assertTrue(any(output.glob(".images-backup-*")))
            self.assertTrue(any(output.glob(".manifest-backup-*")))
            self.assertFalse((output / decoder.PUBLISH_LOCK_NAME).exists())

    def test_private_codec_decodes_initial_tree_literal_and_rejects_truncation(
        self,
    ) -> None:
        literal = pack_bits(initial_code(ord("A")))
        self.assertEqual(decompress_private(literal, 1), b"A")
        with self.assertRaises(CodecError):
            decompress_private(literal, 2)

    def test_mkf_rejects_resource_span_and_size_limit_violations(self) -> None:
        data = bytearray(make_mkf([(b"abc", 3, 0, 0)]))
        struct.pack_into("<I", data, 8, 4)
        with self.assertRaises(FormatError):
            parse_mkf(Path("bad.mkf"), bytes(data))
        with self.assertRaises(FormatError):
            parse_mkf(
                Path("large.mkf"), make_mkf([(b"abc", 3, 0, 0)]), max_resource_bytes=2
            )

    def test_visual_resource_bounds_and_graph_sizes(self) -> None:
        spr = make_spr()
        entry = MkfEntry(0, 4, len(spr), len(spr), 24, 512, 20, 20 + len(spr))
        parsed = parse_visual_resource(spr, entry)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.signature, "SPR")
        self.assertEqual(parsed.chunks[0].pixels, b"\0\1")

        malformed = bytearray(spr)
        struct.pack_into("<I", malformed, 12 + 8, 3)
        with self.assertRaises(ImageError):
            parse_visual_resource(bytes(malformed), entry)
        with self.assertRaises(ImageError):
            parse_visual_resource(spr, entry, max_dimension=1)
        overlapping = bytearray(spr)
        struct.pack_into("<I", overlapping, 8, 12)
        with self.assertRaises(ImageError):
            parse_visual_resource(bytes(overlapping), entry)
        with self.assertRaises(ImageError):
            parse_visual_resource(b"SPR\0\0\0\0\0", entry)

    def test_png_conversion_preserves_indexed_pixels_and_transparency(self) -> None:
        spr = make_spr()
        entry = MkfEntry(0, 4, len(spr), len(spr), 24, 512, 20, 20 + len(spr))
        resource = parse_visual_resource(spr, entry)
        assert resource is not None
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "chunk.png"
            write_png(path, resource.chunks[0], resource, pixel_format="rgb555")
            width, height, rgba = read_png_rgba(path.read_bytes())
        self.assertEqual((width, height), (2, 1))
        self.assertEqual(rgba, bytes((0, 0, 0, 0, 255, 0, 0, 255)))

    def test_decode_source_writes_manifest_and_bounded_visuals(self) -> None:
        spr = make_spr()
        smp = make_smp()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "installation"
            edition = root / "Game"
            edition.mkdir(parents=True)
            (edition / "Panel.mkf").write_bytes(make_mkf([(spr, len(spr), 24, 512)]))
            (edition / "map.mkf").write_bytes(
                make_mkf(
                    [
                        (smp, len(smp), 24, 2),
                        (b"plain", 5, 0, 0),
                    ]
                )
            )
            output = Path(temporary) / "decoded"
            manifest = decode_source(root, output)
            self.assertEqual(len(manifest["visual_resources"]), 2)
            self.assertEqual(
                {item["archive"] for item in manifest["visual_resources"]},
                {"Game/Panel.mkf", "Game/map.mkf"},
            )
            self.assertTrue(manifest["gnd_resources_skipped"])
            self.assertEqual(
                json.loads((output / "manifest.json").read_text())["version"], 1
            )
            images = sorted((output / "images").rglob("*.png"))
            self.assertEqual(len(images), 2)
            self.assertTrue(
                (output / "images/Game/Panel/resource-0000/chunk-0000.png").is_file()
            )
            self.assertTrue(all(path.stat().st_size > 64 for path in images))


if __name__ == "__main__":
    unittest.main()
