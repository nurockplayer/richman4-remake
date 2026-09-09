#!/usr/bin/env python3
"""Package only verified private Media/Music Ogg files for a macOS app."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from pathlib import PurePosixPath
import shutil
import tempfile
from typing import Any

import verify_private_assets


PACKAGE_SCHEMA = "richman4.audio-package/v1"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise verify_private_assets.VerificationError(f"cannot read packaged music file {path}: {exc}") from exc
    return digest.hexdigest()


def _manifest_sha256(config_path: Path) -> str:
    binding = json.loads(config_path.read_text(encoding="utf-8"))
    digest = binding.get("manifest_sha256") if isinstance(binding, dict) else None
    if not isinstance(digest, str):
        raise verify_private_assets.VerificationError("private asset binding has no manifest SHA-256")
    return digest


def _read_verified_manifest(
    asset_root: Path,
    verification: dict[str, Any],
    config_path: Path,
) -> tuple[dict[str, Any], str]:
    expected_digest = _manifest_sha256(config_path)
    manifest_path = asset_root / str(verification["manifest"])
    try:
        manifest_bytes = manifest_path.read_bytes()
    except OSError as exc:
        raise verify_private_assets.VerificationError(f"cannot read verified private asset manifest: {exc}") from exc
    if hashlib.sha256(manifest_bytes).hexdigest() != expected_digest:
        raise verify_private_assets.VerificationError("private asset manifest changed after verification")
    try:
        manifest = json.loads(manifest_bytes.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise verify_private_assets.VerificationError(f"cannot read verified private asset manifest: {exc}") from exc
    if not isinstance(manifest, dict):
        raise verify_private_assets.VerificationError("verified private asset manifest is not an object")
    return manifest, expected_digest


def _music_records(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    records = manifest.get("files")
    if not isinstance(records, list):
        raise verify_private_assets.VerificationError("private asset manifest files must be an array")
    selected: list[dict[str, Any]] = []
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            raise verify_private_assets.VerificationError(f"manifest file record {index} is not an object")
        relative = record.get("path")
        path = PurePosixPath(relative) if isinstance(relative, str) else PurePosixPath()
        if path.parts[:2] != ("Media", "Music") or path.suffix.lower() != ".ogg":
            continue
        size = record.get("size")
        digest = record.get("sha256")
        if not isinstance(relative, str) or not isinstance(size, int) or size < 0 or not isinstance(digest, str):
            raise verify_private_assets.VerificationError(f"manifest file record {index} has invalid size or SHA-256")
        selected.append({"path": relative, "size": size, "sha256": digest})
    selected.sort(key=lambda record: (str(record["path"]).casefold(), str(record["path"])))
    if not selected:
        raise verify_private_assets.VerificationError("private asset source contains no Media/Music Ogg files")
    return selected


def _assert_matches(path: Path, record: dict[str, Any], *, label: str) -> None:
    if path.is_symlink() or not path.is_file():
        raise verify_private_assets.VerificationError(f"{label} is missing or is a symlink: {record['path']}")
    try:
        actual_size = path.stat().st_size
    except OSError as exc:
        raise verify_private_assets.VerificationError(f"cannot stat {label}: {path}: {exc}") from exc
    if actual_size != record["size"]:
        raise verify_private_assets.VerificationError(f"size mismatch for {label}: {record['path']}")
    if _sha256(path) != record["sha256"]:
        raise verify_private_assets.VerificationError(f"SHA-256 mismatch for {label}: {record['path']}")


def package(asset_root: Path, destination: Path, config_path: Path) -> dict[str, Any]:
    """Verify a pinned checkout and atomically publish its Ogg music package."""

    asset_root = Path(asset_root)
    destination = Path(destination)
    config_path = Path(config_path)
    verification = verify_private_assets.verify(asset_root, config_path)
    source_root = (asset_root.resolve() / Path(verification["source_root"])).resolve()
    source_root_relative = source_root.relative_to(asset_root.resolve())
    source_manifest, source_manifest_sha256 = _read_verified_manifest(asset_root.resolve(), verification, config_path)
    records = _music_records(source_manifest)
    total_bytes = sum(record["size"] for record in records)

    manifest: dict[str, Any] = {
        "schema": PACKAGE_SCHEMA,
        "version": 1,
        "source_revision": verification["revision"],
        "source_manifest_sha256": source_manifest_sha256,
        "source_root": source_root_relative.as_posix(),
        "file_count": len(records),
        "source_bytes": total_bytes,
        "files": records,
    }
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    output_manifest_sha256 = hashlib.sha256(manifest_bytes).hexdigest()

    destination = destination.absolute()
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(f"music package destination already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{destination.name}.", dir=destination.parent))
    try:
        for record in records:
            source = source_root.joinpath(*PurePosixPath(record["path"]).parts)
            target = staging.joinpath(*PurePosixPath(record["path"]).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copyfile(source, target)
            except OSError as exc:
                raise verify_private_assets.VerificationError(
                    f"cannot copy verified private music file {record['path']}: {exc}"
                ) from exc
        for record in records:
            source = source_root.joinpath(*PurePosixPath(record["path"]).parts)
            target = staging.joinpath(*PurePosixPath(record["path"]).parts)
            _assert_matches(source, record, label="source music file")
            _assert_matches(target, record, label="staged music file")
        (staging / "manifest.json").write_bytes(manifest_bytes)
        staging.rename(destination)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    return {
        "destination": str(destination),
        "source_revision": verification["revision"],
        "source_manifest_sha256": manifest["source_manifest_sha256"],
        "file_count": len(records),
        "source_bytes": total_bytes,
        "manifest_sha256": output_manifest_sha256,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=Path("config/private-assets.json"))
    parser.add_argument("--destination", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    result = package(args.asset_root, args.destination, args.config)
    print(
        "Packaged {file_count} verified private Ogg files ({source_bytes} bytes), manifest SHA-256 {manifest_sha256}".format(
            **result
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
