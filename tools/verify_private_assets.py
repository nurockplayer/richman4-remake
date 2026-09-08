#!/usr/bin/env python3
"""Verify a checked-out private Richman 4 asset revision.

The public code repository stores only this binding and verifier. Original
resources must be obtained from the owner-authenticated private Git/LFS
repository, then checked against the pinned Git revision, manifest digest and
per-file SHA-256 values.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Any


CONFIG_SCHEMA = "richman4.private-assets-binding/v1"
MANIFEST_SCHEMA = "richman4.private-assets/v1"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REVISION_RE = re.compile(r"^[0-9a-f]{40}$")
MAX_CONFIG_BYTES = 64 * 1024
MAX_MANIFEST_BYTES = 32 * 1024 * 1024
LFS_POINTER_PREFIX = b"version https://git-lfs.github.com/spec/v1"


class VerificationError(Exception):
    """The checked-out asset revision is not the bound source."""


def _read_json(path: Path, *, limit: int) -> dict[str, Any]:
    try:
        if path.stat().st_size > limit:
            raise VerificationError(f"JSON file exceeds size limit: {path}")
        value = json.loads(path.read_text(encoding="utf-8"))
    except VerificationError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise VerificationError(f"cannot read JSON file {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise VerificationError(f"JSON root must be an object: {path}")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise VerificationError(f"cannot read asset file {path}: {exc}") from exc
    return digest.hexdigest()


def _safe_relative(value: Any, *, field: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value:
        raise VerificationError(f"{field} must be a relative POSIX path")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise VerificationError(f"{field} must stay below the asset checkout")
    return path


def _under(root: Path, relative: PurePosixPath, *, field: str) -> Path:
    candidate = root.joinpath(*relative.parts)
    for parent in (candidate, *candidate.parents):
        if parent == root:
            break
        if parent.is_symlink():
            raise VerificationError(f"{field} traverses a symlink")
    try:
        resolved_root = root.resolve()
        resolved = candidate.resolve()
        resolved.relative_to(resolved_root)
    except (OSError, ValueError) as exc:
        raise VerificationError(f"{field} escapes the asset checkout") from exc
    return resolved


def _validate_config(config: dict[str, Any]) -> tuple[str, str, str, str]:
    if config.get("schema") != CONFIG_SCHEMA or config.get("version") != 1:
        raise VerificationError("private asset binding schema or version is invalid")
    repository = config.get("repository")
    clone_url = config.get("clone_url")
    revision = config.get("revision")
    manifest = config.get("manifest")
    manifest_sha256 = config.get("manifest_sha256")
    source_root = config.get("source_root")
    if not isinstance(repository, str) or repository != "nurockplayer/richman4-remake-assets":
        raise VerificationError("private asset repository binding is invalid")
    if not isinstance(clone_url, str) or clone_url != "https://github.com/nurockplayer/richman4-remake-assets.git":
        raise VerificationError("private asset clone URL binding is invalid")
    if not isinstance(revision, str) or not REVISION_RE.fullmatch(revision):
        raise VerificationError("private asset revision must be a 40-character lowercase commit SHA")
    manifest_path = _safe_relative(manifest, field="manifest")
    if not SHA256_RE.fullmatch(str(manifest_sha256)):
        raise VerificationError("private asset manifest SHA-256 binding is invalid")
    source_path = _safe_relative(source_root, field="source_root")
    return revision, manifest_path.as_posix(), str(manifest_sha256), source_path.as_posix()


def _git_head(asset_root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(asset_root), "rev-parse", "--verify", "HEAD^{commit}"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        raise VerificationError(f"cannot run git to verify asset revision: {exc}") from exc
    if result.returncode != 0:
        raise VerificationError("asset checkout is not a Git repository with a commit")
    head = result.stdout.strip()
    if not REVISION_RE.fullmatch(head):
        raise VerificationError("asset checkout returned an invalid Git commit SHA")
    return head


def _git_tree_paths(asset_root: Path, source_root: PurePosixPath) -> set[str]:
    """Return the exact UTF-8 relative paths tracked below ``source_root``."""
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(asset_root),
                "ls-tree",
                "-r",
                "-z",
                "--name-only",
                "HEAD",
                "--",
                source_root.as_posix(),
            ],
            check=False,
            capture_output=True,
        )
    except OSError as exc:
        raise VerificationError(f"cannot list the Git tree for private assets: {exc}") from exc
    if result.returncode != 0:
        raise VerificationError("cannot list the Git tree for private assets")

    prefix = source_root.as_posix() + "/"
    paths: set[str] = set()
    for encoded_path in result.stdout.split(b"\0"):
        if not encoded_path:
            continue
        try:
            path = encoded_path.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise VerificationError("private asset Git tree contains a non-UTF-8 path") from exc
        if not path.startswith(prefix):
            raise VerificationError("private asset Git tree returned a path outside source_root")
        paths.add(path[len(prefix) :])
    return paths


def _validate_manifest(
    asset_root: Path,
    manifest: dict[str, Any],
    *,
    expected_source_root: str,
) -> tuple[Path, int, int]:
    if manifest.get("schema") != MANIFEST_SCHEMA or manifest.get("version") != 1:
        raise VerificationError("private asset manifest schema or version is invalid")
    source_root = _safe_relative(manifest.get("source_root"), field="manifest source_root")
    if source_root.as_posix() != expected_source_root:
        raise VerificationError("private asset source_root does not match the public binding")
    source_path = _under(asset_root, source_root, field="source_root")
    if not source_path.is_dir() or source_path.is_symlink():
        raise VerificationError("private asset source_root is not a real directory")
    git_paths = _git_tree_paths(asset_root, source_root)
    records = manifest.get("files")
    if not isinstance(records, list):
        raise VerificationError("private asset manifest files must be an array")
    file_count = manifest.get("file_count")
    source_bytes = manifest.get("source_bytes")
    if not isinstance(file_count, int) or file_count < 0 or not isinstance(source_bytes, int) or source_bytes < 0:
        raise VerificationError("private asset manifest totals are invalid")
    if file_count != len(records):
        raise VerificationError("private asset manifest file_count does not match files")

    seen: set[str] = set()
    manifest_paths: set[str] = set()
    total_bytes = 0
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            raise VerificationError(f"manifest file record {index} is not an object")
        relative = _safe_relative(record.get("path"), field=f"manifest files[{index}].path")
        key = relative.as_posix().casefold()
        if key in seen:
            raise VerificationError(f"manifest contains a duplicate path: {relative}")
        seen.add(key)
        relative_name = relative.as_posix()
        if relative_name not in git_paths:
            raise VerificationError(f"manifest path does not match Git tree exactly: {relative}")
        manifest_paths.add(relative_name)
        size = record.get("size")
        digest = record.get("sha256")
        if not isinstance(size, int) or size < 0 or not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            raise VerificationError(f"manifest file record {index} has invalid size or SHA-256")
        path = _under(source_path, relative, field=f"manifest files[{index}].path")
        if path.is_symlink() or not path.is_file():
            raise VerificationError(f"manifest file is missing or is a symlink: {relative}")
        try:
            actual_size = path.stat().st_size
        except OSError as exc:
            raise VerificationError(f"cannot stat asset file {relative}: {exc}") from exc
        if actual_size != size:
            if path.read_bytes().startswith(LFS_POINTER_PREFIX):
                raise VerificationError(f"Git LFS content was not downloaded: {relative}")
            raise VerificationError(f"size mismatch for asset file: {relative}")
        actual_digest = _sha256(path)
        if actual_digest != digest:
            raise VerificationError(f"SHA-256 mismatch for asset file: {relative}")
        total_bytes += size
    if total_bytes != source_bytes:
        raise VerificationError("private asset manifest source_bytes does not match files")
    if manifest_paths != git_paths:
        raise VerificationError("manifest paths do not match Git tree exactly")
    return source_path, file_count, source_bytes


def verify(asset_root: Path, config_path: Path) -> dict[str, Any]:
    asset_root = asset_root.expanduser().resolve()
    config = _read_json(config_path.expanduser().resolve(), limit=MAX_CONFIG_BYTES)
    revision, manifest_name, manifest_digest, source_root = _validate_config(config)
    head = _git_head(asset_root)
    if head != revision:
        raise VerificationError(f"asset revision mismatch: expected {revision}, got {head}")
    manifest_path = _under(asset_root, PurePosixPath(manifest_name), field="manifest")
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise VerificationError("bound private asset manifest is missing")
    if _sha256(manifest_path) != manifest_digest:
        raise VerificationError("private asset manifest SHA-256 does not match the public binding")
    manifest = _read_json(manifest_path, limit=MAX_MANIFEST_BYTES)
    source_path, file_count, source_bytes = _validate_manifest(
        asset_root,
        manifest,
        expected_source_root=source_root,
    )
    return {
        "revision": head,
        "manifest": manifest_path.relative_to(asset_root).as_posix(),
        "source_root": source_path.relative_to(asset_root).as_posix(),
        "file_count": file_count,
        "source_bytes": source_bytes,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=Path("config/private-assets.json"))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = verify(args.asset_root, args.config)
    except VerificationError as error:
        print(f"Private asset verification failed: {error}", file=sys.stderr)
        return 1
    print(
        "Verified private asset revision {revision}: {file_count} files, {source_bytes} bytes from {source_root}".format(
            **result
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
