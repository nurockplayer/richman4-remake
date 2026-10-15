#!/usr/bin/env python3
"""Install checksum-pinned Godot desktop export templates using Python stdlib."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile

VERSION = "4.7.2"
SHA512 = "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("macos", "linux"),
                        default="macos" if sys.platform == "darwin" else "linux")
    parser.add_argument("--template-dir", type=Path,
                        help="Godot export-template directory override")
    args = parser.parse_args()
    if args.template_dir:
        target = args.template_dir
    elif sys.platform == "darwin":
        target = Path.home() / f"Library/Application Support/Godot/export_templates/{VERSION}.stable"
    else:
        data_home = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
        target = data_home / f"godot/export_templates/{VERSION}.stable"
    root = Path(__file__).resolve().parent.parent
    download = root / ".local/downloads/export_templates.tpz"
    download.parent.mkdir(parents=True, exist_ok=True)
    if not download.exists():
        temporary = download.with_suffix(".download")
        print("Downloading official export templates (~1.3 GB).", flush=True)
        with urllib.request.urlopen(URL, timeout=60) as response, temporary.open("wb") as out:
            shutil.copyfileobj(response, out)
        os.replace(temporary, download)
    digest = hashlib.sha512()
    with download.open("rb") as data:
        for block in iter(lambda: data.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != SHA512:
        raise SystemExit(f"Template checksum mismatch: remove {download} and retry.")
    target.mkdir(parents=True, exist_ok=True)
    names = ["macos.zip"] if args.platform == "macos" else ["linux_debug.x86_64", "linux_release.x86_64"]
    with zipfile.ZipFile(download) as archive:
        for name in names:
            output = target / name
            temporary = target / (name + ".tmp")
            with archive.open("templates/" + name) as source, temporary.open("wb") as out:
                shutil.copyfileobj(source, out)
            if args.platform == "linux":
                temporary.chmod(0o755)
            os.replace(temporary, output)
            print(f"Verified template installed: {output}")


if __name__ == "__main__":
    main()
