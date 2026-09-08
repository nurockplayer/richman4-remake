#!/usr/bin/env python3
"""Install the checksum-pinned Godot macOS export template using Python stdlib."""
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
    if sys.platform != "darwin":
        raise SystemExit("This installer targets macOS only.")
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
    target = Path.home() / f"Library/Application Support/Godot/export_templates/{VERSION}.stable"
    target.mkdir(parents=True, exist_ok=True)
    output = target / "macos.zip"
    temporary = target / "macos.zip.tmp"
    with zipfile.ZipFile(download) as archive:
        with archive.open("templates/macos.zip") as source, temporary.open("wb") as out:
            shutil.copyfileobj(source, out)
    os.replace(temporary, output)
    print(f"Verified template installed: {output}")


if __name__ == "__main__":
    main()
