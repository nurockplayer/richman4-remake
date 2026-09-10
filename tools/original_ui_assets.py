"""Export the bounded, source-mapped UI resources into a private scene bundle."""
from __future__ import annotations

import hashlib
from pathlib import Path

from decode_original_images import (
    FormatError, _find_casefolded, decode_entry, parse_mkf,
    parse_visual_resource, write_png,
)

# Source identity is kept separate from presentation coordinates.  These are
# archive indices, not screen positions; see docs/original-ui-assets.md.
UI_RESOURCES = {"Data": (1, 2, 3), "Panel": (0, 1, 2, 75)}


def export_ui_resources(edition: str, directory: Path, stage: Path) -> dict:
    result = {}
    for name, indices in UI_RESOURCES.items():
        path = _find_casefolded(directory, name + ".mkf")
        if path is None:
            continue
        archive = parse_mkf(path)
        resources = {}
        for index in indices:
            if index >= len(archive.entries):
                continue
            entry = archive.entries[index]
            payload = decode_entry(archive, entry)
            visual = parse_visual_resource(payload, entry)
            if visual is None or visual.signature not in ("SMP", "SPR"):
                raise FormatError(f"unsupported UI image at {path}:{index}")
            chunks = {}
            for chunk in visual.chunks:
                relative = Path("images") / edition / "ui" / name / str(index) / f"{chunk.index}.png"
                target = stage / relative
                # UI sprites use a zero background around their irregular
                # edges.  Keep that background transparent when compositing.
                write_png(target, chunk, visual, pixel_format="rgb555",
                          transparent_word_zero=True)
                chunks[str(chunk.index)] = {
                    "path": relative.as_posix(),
                    "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                    "width": chunk.width, "height": chunk.height,
                    "logical": {"width": chunk.width, "height": chunk.height,
                                "anchor_x": chunk.x, "anchor_y": chunk.y},
                }
            resources[str(index)] = {
                "payload_sha256": hashlib.sha256(payload).hexdigest(),
                "signature": visual.signature,
                "transparent_word_zero": True,
                "chunks": chunks,
            }
        result[name] = {"archive_sha256": hashlib.sha256(archive.data).hexdigest(),
                        "resources": resources}
    return result
