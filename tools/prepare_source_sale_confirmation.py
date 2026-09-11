#!/usr/bin/env python3
"""Add only the six audited SALE YES/NO frames to an existing private overlay."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

from decode_original_images import decode_entry, parse_mkf, parse_visual_resource, write_png
from prepare_inventory_assets import _ensure_base_link
from prepare_source_shop import _ensure_resolved_overlay_links, _verify_scene_paths

BASE_SHA256 = "fd96a7d686f3aa2d91a7e22099562214ff7d9dc3c1c11b6ac83651b6f1ac8fee"
PAYLOAD_SHA256 = "dfe92eff65dfb3df7282d511236530724b2d94912752f225490141a14da68ad0"
SOURCE = {
    "Game": (399, "c63023e815b1ad4bef172b6415d128c7f041f12b71b5d80dc3ff29240a0a1988"),
    "MultiverseJourney": (440, "0506fc7951b0556e6e65889c2d712d1f9d87a4e753d02870e67b8c9807d54c33"),
}
PIXEL_HASHES = (
    "b7da461b3f7eeba30403bb0172e7eb6bf9d5bc685bdfd59bd21a6559739d17cd",
    "64a0089b48f954d8880cfe499104d82a5af5d1fd7f14c97a784fe695fef235b5",
    "e5a7e651d4f17a747fdbae0df1928788ed6cb6576e7e86389a541664c46bfa5a",
)


def prepare(zip_path: Path, base_path: Path, output: Path) -> dict:
    if hashlib.sha256(base_path.read_bytes()).hexdigest() != BASE_SHA256:
        raise ValueError("SALE base overlay hash mismatch")
    if output.exists():
        raise ValueError("confirmation output already exists")
    if shutil.disk_usage(output.parent).free < 2 * 1024 * 1024:
        raise ValueError("insufficient space for bounded six-frame overlay")
    scene = json.loads(base_path.read_text())
    original = copy.deepcopy(scene)
    staged = []
    with zipfile.ZipFile(zip_path) as archive:
        for edition, (resource, archive_hash) in SOURCE.items():
            member = f"dfw4cskzl_136622/{edition}/Data.mkf"
            data = archive.read(member)
            if hashlib.sha256(data).hexdigest() != archive_hash:
                raise ValueError("Data archive identity mismatch")
            mkf = parse_mkf(Path(member), data)
            payload = decode_entry(mkf, mkf.entries[resource])
            if hashlib.sha256(payload).hexdigest() != PAYLOAD_SHA256:
                raise ValueError("YES/NO payload identity mismatch")
            visual = parse_visual_resource(payload, mkf.entries[resource])
            if visual is None or visual.signature != "SMP" or visual.chunk_count != 3:
                raise ValueError("YES/NO visual shape mismatch")
            for chunk in visual.chunks:
                if (chunk.width, chunk.height) != (96, 48) or hashlib.sha256(chunk.pixels).hexdigest() != PIXEL_HASHES[chunk.index]:
                    raise ValueError("YES/NO frame identity mismatch")
            resources = scene["ui"][edition]["Data"]["resources"]
            if str(resource) in resources:
                raise ValueError("YES/NO resource collision")
            staged.append((edition, resource, member, archive_hash, visual))
    output.mkdir()
    for edition, resource, member, archive_hash, visual in staged:
        chunks = {}
        for chunk in visual.chunks:
            relative = Path("images") / edition / "ui" / "Data" / str(resource) / f"{chunk.index}.png"
            path = output / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            write_png(path, chunk, visual, pixel_format="rgb555", transparent_word_zero=False)
            chunks[str(chunk.index)] = {"path": relative.as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "width": 96, "height": 48, "logical": {"width": 96, "height": 48, "anchor_x": chunk.x, "anchor_y": chunk.y}, "transparent_word_zero": False}
        scene["ui"][edition]["Data"]["resources"][str(resource)] = {"resource_index": resource, "signature": "SMP", "format": "SMP", "pixel_format": "rgb555", "source": {"edition": edition, "archive": "Data.mkf", "resource_index": resource, "zip_member": member, "archive_sha256": archive_hash, "payload_sha256": PAYLOAD_SHA256}, "chunks": chunks}
    _ensure_base_link(output, base_path)
    _ensure_resolved_overlay_links(output, base_path)
    _verify_scene_paths(scene, output)
    for edition, (resource, _) in SOURCE.items():
        inherited = copy.deepcopy(scene["ui"][edition]["Data"]["resources"])
        inherited.pop(str(resource))
        if inherited != original["ui"][edition]["Data"]["resources"]:
            raise ValueError("inherited Data references changed")
    scene_path = output / "scene-manifest.json"
    scene_path.write_text(json.dumps(scene, ensure_ascii=False, indent=2) + "\n")
    provenance = {"schema": "richman4.source-sale-confirmation/v1", "base_sha256": BASE_SHA256, "scene_sha256": hashlib.sha256(scene_path.read_bytes()).hexdigest(), "selected_png_count": 6, "payload_sha256": PAYLOAD_SHA256, "source_call": "rich4_ui_yesno.asm:366-372 reads MJ Data440; rich4_ui_sale.asm:4560-4564 calls centered at (320,240)", "position": [272, 216], "size": [96, 48], "alpha": "opaque fcn_004563f5", "Game_evidence": "Data399 decoded payload byte-identical to MJ Data440; not Game original-runtime validation", "frames": {"0": "neutral", "1": "left YES hover", "2": "right NO hover"}}
    (output / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    return provenance


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", required=True, type=Path)
    parser.add_argument("--base-manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.zip, args.base_manifest, args.output), ensure_ascii=False))
