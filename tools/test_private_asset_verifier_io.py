"""I/O regressions for the private asset verifier."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "tools" / "verify_private_assets.py"
SPEC = importlib.util.spec_from_file_location("richman4_private_asset_verifier", VERIFY)
assert SPEC is not None and SPEC.loader is not None
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


class _GuardedStream:
    def __init__(self, payload: bytes) -> None:
        self.payload = payload
        self.read_sizes: list[int] = []

    def __enter__(self) -> "_GuardedStream":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self, size: int = -1) -> bytes:
        self.read_sizes.append(size)
        if size != len(VERIFIER.LFS_POINTER_PREFIX):
            raise AssertionError(f"unbounded pointer read requested: {size}")
        return self.payload[:size]


class _GuardedPath:
    def __init__(self, stream: _GuardedStream) -> None:
        self.stream = stream

    def open(self, mode: str) -> _GuardedStream:
        if mode != "rb":
            raise AssertionError(f"unexpected mode: {mode}")
        return self.stream


class PrivateAssetVerifierIoTests(unittest.TestCase):
    def test_lfs_pointer_probe_reads_only_the_fixed_prefix(self) -> None:
        stream = _GuardedStream(VERIFIER.LFS_POINTER_PREFIX + b"\nrest of pointer")
        self.assertTrue(VERIFIER._starts_with_lfs_pointer(_GuardedPath(stream)))
        self.assertEqual(stream.read_sizes, [len(VERIFIER.LFS_POINTER_PREFIX)])

    def test_non_pointer_probe_is_also_bounded(self) -> None:
        stream = _GuardedStream(b"not an lfs pointer" + b"x" * 256)
        self.assertFalse(VERIFIER._starts_with_lfs_pointer(_GuardedPath(stream)))
        self.assertEqual(stream.read_sizes, [len(VERIFIER.LFS_POINTER_PREFIX)])


if __name__ == "__main__":
    unittest.main()
