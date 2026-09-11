#!/usr/bin/env python3
"""Prepare only source minigame artwork and the private penguin click plane.

Read the owner ZIP in place. Existing scene assets remain behind a symlink;
this is not a full export. Original data and generated output must stay private.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from decode_original_images import decode_entry, parse_mkf, parse_visual_resource, VisualChunk, VisualResource, write_png
from prepare_lottery_assets import decode_flic, write_png as write_flic_png, _rewrite_base_paths, AssetError

EDITIONS = ("Game", "MultiverseJourney")
# Source background callers copy these opaquely. Other SMP callers skip WORD0.
OPAQUE = {(80, 0), (91, 0), (92, 0)} | {(79, digit) for digit in range(10)}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def prepare(zip_path: Path, output: Path, base_manifest: Path, grid_path: Path, catching_path: Path) -> dict:
    if output.exists() and any(output.iterdir()):
        raise AssetError("output must be a fresh scoped directory")
    output.mkdir(parents=True, exist_ok=True)
    base_manifest = base_manifest.resolve()
    scene = _rewrite_base_paths(json.loads(base_manifest.read_text()))
    if scene.get("schema") != "richman4.scene-images/v1": raise AssetError("invalid base scene")
    base_link = output / "images/base"
    base_link.parent.mkdir(parents=True, exist_ok=True)
    base_link.symlink_to(base_manifest.parent / "images", target_is_directory=True)
    grid = json.loads(grid_path.read_text())
    if grid.get("schema") != "richman4.private-source-penguin-coordinate-table/v1" or len(grid.get("records", [])) != 81:
        raise AssetError("invalid penguin source grid")
    catching = json.loads(catching_path.read_text())
    if len(catching.get("thrower_frame_lookup",[])) != 36: raise AssetError("invalid catching source lookup")
    scene["minigame_source"]={"thrower_frames":catching["thrower_frame_lookup"]}
    input_dir = output / "input"
    input_dir.mkdir()
    grid_target = input_dir / "penguin-grid.json"
    grid_target.write_bytes(grid_path.read_bytes())
    manifest = {"schema": "richman4.minigame-assets/v1", "version": 1,
                "base_manifest": {"path": str(base_manifest), "sha256": sha(base_manifest.read_bytes())},
                "input": {"penguin_grid": {"path": "input/penguin-grid.json", "sha256": sha(grid_target.read_bytes())}}, "resources": {}}
    with zipfile.ZipFile(zip_path) as archive:
        for edition in EDITIONS:
            member = f"dfw4cskzl_136622/{edition}/Panel.mkf"
            raw = archive.read(member)
            mkf = parse_mkf(Path(member), raw)
            group = scene["ui"][edition]["Panel"]
            if group["archive_sha256"] != sha(raw): raise AssetError("base source archive mismatch")
            resources = {}
            for index in range(78, 112):
                payload = decode_entry(mkf, mkf.entries[index])
                if index == 81:
                    if len(payload) != 640*480 or sha(payload) != "972f3ced79cb4421c16b454b46656e0f7e2f0d2f3ced5dfe5217edbfbf353325":
                        raise AssetError("unexpected penguin click plane")
                    target = input_dir / "penguin-mask.bin"
                    if target.exists() and target.read_bytes() != payload: raise AssetError("edition click plane mismatch")
                    target.write_bytes(payload)
                    manifest["input"]["penguin_mask"] = {"path":"input/penguin-mask.bin", "sha256":sha(payload), "width":640, "height":480}
                    continue
                chunks = {}
                fmt = "SMP"
                if index == 78:
                    width, height, frames = decode_flic(payload, max_frames=20)
                    if (width, height, len(frames)) != (640,480,20): raise AssetError("unexpected minigame intro dimensions")
                    fmt = "FLIC"
                    for number, (pixels,palette) in enumerate(frames):
                        relative = Path("images")/edition/"ui/Panel"/str(index)/f"{number}.png"
                        target=output/relative
                        write_flic_png(target,pixels,palette,width,height,True)
                        chunks[str(number)]={"path":relative.as_posix(),"sha256":sha(target.read_bytes()),"width":width,"height":height,"logical":{"width":640,"height":480,"anchor_x":0,"anchor_y":0},"transparent_index_zero":True}
                else:
                    if index == 92:
                        if len(payload)!=640*480*2: raise AssetError("invalid raw catching background")
                        visual=VisualResource("RAW555",1,0,None,(VisualChunk(0,640,480,0,0,payload),))
                        fmt="RAW555"
                    else:
                        visual=parse_visual_resource(payload,mkf.entries[index])
                        if visual is None or visual.signature not in ("SMP","SPR"): raise AssetError(f"unsupported Panel{index}")
                        fmt=visual.signature
                    for chunk in visual.chunks:
                        relative=Path("images")/edition/"ui/Panel"/str(index)/f"{chunk.index}.png"
                        target=output/relative
                        target.parent.mkdir(parents=True,exist_ok=True)
                        transparent=(index,chunk.index) not in OPAQUE
                        write_png(target,chunk,visual,pixel_format="rgb555",transparent_word_zero=transparent)
                        chunks[str(chunk.index)]={"path":relative.as_posix(),"sha256":sha(target.read_bytes()),"width":chunk.width,"height":chunk.height,"logical":{"width":chunk.width,"height":chunk.height,"anchor_x":chunk.x,"anchor_y":chunk.y},"transparent_word_zero":transparent}
                record={"resource_index":index,"payload_sha256":sha(payload),"signature":fmt,"format":fmt,"source":{"edition":edition,"archive":"Panel.mkf","zip_member":member,"resource_index":index,"payload_sha256":sha(payload),"archive_sha256":sha(raw)},"chunks":chunks}
                if index==78: record["caller"]={"flags":1,"delay_ms":114,"loop":False,"skip_on_release":False,"transparent_index_zero":True}
                group["resources"][str(index)]=record
                resources[str(index)]=record
            data_member=f"dfw4cskzl_136622/{edition}/Data.mkf"
            data_raw=archive.read(data_member)
            data_mkf=parse_mkf(Path(data_member),data_raw)
            explosion=decode_entry(data_mkf,data_mkf.entries[526])
            width,height,frames=decode_flic(explosion,max_frames=64)
            chunks={}
            for number,(pixels,palette) in enumerate(frames):
                relative=Path("images")/edition/"ui/Data/526"/f"{number}.png"
                target=output/relative
                write_flic_png(target,pixels,palette,width,height,True)
                chunks[str(number)]={"path":relative.as_posix(),"sha256":sha(target.read_bytes()),"width":width,"height":height,"logical":{"width":width,"height":height,"anchor_x":0,"anchor_y":0},"transparent_index_zero":True}
            record={"resource_index":526,"payload_sha256":sha(explosion),"signature":"FLIC","format":"FLIC","source":{"edition":edition,"archive":"Data.mkf","zip_member":data_member,"resource_index":526,"payload_sha256":sha(explosion),"archive_sha256":sha(data_raw)},"chunks":chunks,"caller":{"flags":1,"loop":False,"x_offset":-55,"y":295,"delay_ms":int.from_bytes(explosion[16:20],"little")}}
            scene["ui"][edition].setdefault("Data",{"archive_sha256":sha(data_raw),"resources":{}})["resources"]["526"]=record
            resources["Data526"]=record
            manifest["resources"][edition]=resources
    (output/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    (output/"scene-manifest.json").write_text(json.dumps(scene,ensure_ascii=False,indent=2)+"\n")
    return manifest


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip",dest="zip_path",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--base-manifest",type=Path,required=True)
    parser.add_argument("--penguin-grid",type=Path,required=True)
    parser.add_argument("--catching-data",type=Path,required=True)
    args=parser.parse_args()
    result=prepare(args.zip_path,args.output,args.base_manifest,args.penguin_grid,args.catching_data)
    print("Prepared bounded minigame resources:",sum(len(v) for v in result["resources"].values()))


if __name__=="__main__": main()
