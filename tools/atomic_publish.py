#!/usr/bin/env python3
"""Publish a staged directory with atomic no-replace semantics."""

from __future__ import annotations

import argparse
import ctypes
import errno
import os
import sys
from pathlib import Path


AT_FDCWD = -2
RENAME_EXCL_DARWIN = 0x00000004
RENAME_NOREPLACE_LINUX = 0x00000001


def _rename_exclusive(source: Path, destination: Path) -> bool:
    """Atomically rename source unless destination already exists.

    ``mv -n`` is not sufficient for directories: on macOS it nests the source
    below a destination that appeared after the initial existence check. Use
    the platform's no-replace rename primitive instead.
    """
    libc = ctypes.CDLL(None, use_errno=True)
    encoded_source = os.fsencode(source)
    encoded_destination = os.fsencode(destination)

    if sys.platform == "darwin":
        renameatx_np = getattr(libc, "renameatx_np", None)
        if renameatx_np is None:
            raise OSError(errno.ENOTSUP, "renameatx_np is unavailable")
        renameatx_np.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameatx_np.restype = ctypes.c_int
        result = renameatx_np(
            AT_FDCWD,
            encoded_source,
            AT_FDCWD,
            encoded_destination,
            RENAME_EXCL_DARWIN,
        )
    else:
        renameat2 = getattr(libc, "renameat2", None)
        if renameat2 is None:
            raise OSError(errno.ENOTSUP, "renameat2 is unavailable")
        renameat2.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameat2.restype = ctypes.c_int
        result = renameat2(
            AT_FDCWD,
            encoded_source,
            AT_FDCWD,
            encoded_destination,
            RENAME_NOREPLACE_LINUX,
        )

    if result == 0:
        return True
    error = ctypes.get_errno()
    if error == errno.EEXIST:
        return False
    raise OSError(error, os.strerror(error), destination)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        published = _rename_exclusive(args.source, args.destination)
    except OSError as error:
        print(f"Atomic private asset publish failed: {error}", file=sys.stderr)
        return 1
    if not published:
        print(f"Atomic private asset publish skipped; destination exists: {args.destination}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
