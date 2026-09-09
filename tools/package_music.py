#!/usr/bin/env python3
"""Package only verified private Media/Music Ogg files for a macOS app."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import verify_private_assets


PACKAGE_SCHEMA = "richman4.audio-package/v1"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _manifest_sha256(config_path: Path) -> str:
    binding = json.loads(config_path.read_text(encoding="utf-8"))
    digest = binding.get("manifest_sha256") if isinstance(binding, dict) else None
    if not isinstance(digest, str):
        raise verify_private_assets.VerificationError("private asset binding has no manifest SHA-256")
    return digest


def _music_files(source_root: Path) -> list[Path]:
    music_root = source_root / "Media" / "Music"
    if not music_root.is_dir() or music_root.is_symlink():
        raise verify_private_assets.VerificationError("private asset Media/Music directory is missing")
    files: list[Path] = []
    for path in sorted(music_root.iterdir(), key=lambda candidate: candidate.name.casefold()):
        if path.is_symlink():
            raise verify_private_assets.VerificationError(f"private music file is a symlink: {path.name}")
        if path.is_file() and path.suffix.lower() == ".ogg":
            files.append(path)
    if not files:
        raise verify_private_assets.VerificationError("private asset source contains no Media/Music Ogg files")
    return files


def package(asset_root: Path, destination: Path, config_path: Path) -> dict[str, Any]:
    """Verify a pinned checkout and atomically publish its Ogg music package."""

    asset_root = Path(asset_root)
    destination = Path(destination)
    config_path = Path(config_path)
    verification = verify_private_assets.verify(asset_root, config_path)
    source_root = (asset_root.resolve() / Path(verification["source_root"])).resolve()
    source_root_relative = source_root.relative_to(asset_root.resolve())
    files = _music_files(source_root)
    records: list[dict[str, Any]] = []
    total_bytes = 0
    for path in files:
        relative = path.relative_to(source_root).as_posix()
        payload_size = path.stat().st_size
        records.append({"path": relative, "size": payload_size, "sha256": _sha256(path)})
        total_bytes += payload_size

    manifest: dict[str, Any] = {
        "schema": PACKAGE_SCHEMA,
        "version": 1,
        "source_revision": verification["revision"],
        "source_manifest_sha256": _manifest_sha256(config_path),
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
        for path, record in zip(files, records):
            target = staging / record["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
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
