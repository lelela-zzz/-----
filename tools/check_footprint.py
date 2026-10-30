#!/usr/bin/env python3
"""网格对齐与元素占地校验工具（炉火镇）

两个子命令：
  inspect <目录>            体检模式：扫描目录内 PNG，报告尺寸整格性、包围盒、是否触边
  check   <manifest.json>   校验模式：按 manifest 声明的 footprint 严格校验，不合规退出码 3

退出码：0 通过 / 1 参数错误 / 2 文件或目录问题 / 3 校验发现违规

用法：
  python check_footprint.py inspect assets/house/v2/sprites --tile 32
  python check_footprint.py check assets/sprites.manifest.example.json --tile 32
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

try:
    from PIL import Image
except ImportError:
    print("需要 Pillow：pip install Pillow", file=sys.stderr)
    sys.exit(2)


def alpha_bbox(path: str):
    im = Image.open(path).convert("RGBA")
    return im, im.getbbox()


def inspect(path: str, tile: int, scale: int, as_json: bool) -> int:
    files = sorted(glob.glob(os.path.join(path, "*.png")))
    if not files:
        print(f"目录内没有 PNG：{path}", file=sys.stderr)
        return 2

    rows, bad = [], 0
    for f in files:
        im, bb = alpha_bbox(f)
        w, h = im.size
        if bb is None:
            rows.append({"file": os.path.basename(f), "error": "全透明，无内容"})
            bad += 1
            continue
        unit = tile * scale
        gw, gh = w / unit, h / unit
        w_int = float(gw).is_integer()
        h_int = float(gh).is_integer()
        bottom_aligned = bb[3] == h
        touch_left, touch_right = bb[0] == 0, bb[2] == w
        issues = []
        if not w_int:
            issues.append(f"宽 {w}px 不是 {unit}px 的整数倍（{gw:.2f} 格）")
        if not h_int:
            issues.append(f"高 {h}px 不是 {unit}px 的整数倍（{gh:.2f} 格）")
        if not bottom_aligned:
            issues.append(f"内容未贴底，底部余白 {h - bb[3]}px")
        if issues:
            bad += 1
        rows.append({
            "file": os.path.basename(f), "size": [w, h],
            "size_grid": [round(gw, 2), round(gh, 2)],
            "content_bbox": list(bb),
            "content_grid": [round(bb[2] / unit, 2), round(bb[3] / unit, 2)],
            "bottom_aligned": bottom_aligned,
            "touch_edge": {"left": touch_left, "right": touch_right},
            "issues": issues,
        })

    if as_json:
        print(json.dumps({"tile": tile, "scale": scale, "assets": rows}, ensure_ascii=False, indent=2))
    else:
        print(f"体检目录：{path}   tile={tile} scale={scale}   共 {len(rows)} 个文件\n")
        print(f"{'文件':28} {'画布':>11} {'格数':>11}  问题")
        for r in rows:
            if "error" in r:
                print(f"{r['file']:28} {'-':>11} {'-':>11}  {r['error']}")
                continue
            sz = f"{r['size'][0]}x{r['size'][1]}"
            gd = f"{r['size_grid'][0]}x{r['size_grid'][1]}"
            flag = "；".join(r["issues"]) if r["issues"] else "OK"
            print(f"{r['file']:28} {sz:>11} {gd:>11}  {flag}")
        print(f"\n不合规：{bad} / {len(rows)}")
    return 0 if bad == 0 else 3


def check(manifest_path: str, tile: int) -> int:
    try:
        m = json.load(open(manifest_path, encoding="utf-8"))
    except Exception as e:
        print(f"读取 manifest 失败：{e}", file=sys.stderr)
        return 2

    tile = m.get("tile", tile)
    base = os.path.dirname(os.path.abspath(manifest_path))
    bad = 0
    print(f"校验 manifest：{manifest_path}   tile={tile}\n")
    for a in m.get("assets", []):
        f = os.path.join(base, a["file"])
        name = a["file"]
        if not os.path.exists(f):
            print(f"[缺文件] {name}")
            bad += 1
            continue
        fp = a["footprint"]
        over = a.get("overhang_up", 0)
        scale = a.get("scale", 1)
        unit = tile * scale
        im, bb = alpha_bbox(f)
        w, h = im.size
        exp_w = fp["w"] * unit
        exp_h = (fp["h"] + over) * unit
        issues = []
        if w != exp_w:
            issues.append(f"画布宽 {w} ≠ footprint {fp['w']}×{unit} = {exp_w}")
        if h != exp_h:
            issues.append(f"画布高 {h} ≠ ({fp['h']}+overhang {over})×{unit} = {exp_h}")
        if bb is None:
            issues.append("全透明")
        else:
            if bb[0] < 0 or bb[2] > exp_w:
                issues.append(f"横向越界：内容 x [{bb[0]},{bb[2]}]")
            if bb[3] != h:
                issues.append(f"未贴底：底部余白 {h - bb[3]}px")
            if bb[1] < (exp_h - (fp["h"] + over) * unit):
                issues.append("纵向超出画布")
            if over > fp["h"]:
                issues.append(f"overhang {over} 格 > footprint 高 {fp['h']} 格，疑似误填")
        if issues:
            bad += 1
            print(f"[违规] {name}")
            for i in issues:
                print(f"        - {i}")
        else:
            print(f"[通过] {name}  {fp['w']}×{fp['h']} 格" + (f" + overhang {over}" if over else ""))
    print(f"\n违规：{bad} / {len(m.get('assets', []))}")
    return 0 if bad == 0 else 3


def main() -> int:
    p = argparse.ArgumentParser(description="网格对齐与元素占地校验")
    sub = p.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("inspect", help="体检目录内 PNG 是否整格对齐")
    pi.add_argument("dir")
    pi.add_argument("--tile", type=int, default=32)
    pi.add_argument("--scale", type=int, default=1, help="@2x 目录填 2")
    pi.add_argument("--json", action="store_true")

    pc = sub.add_parser("check", help="按 manifest 严格校验")
    pc.add_argument("manifest")
    pc.add_argument("--tile", type=int, default=32)

    args = p.parse_args()
    if args.cmd == "inspect":
        if not os.path.isdir(args.dir):
            print(f"不是目录：{args.dir}", file=sys.stderr)
            return 2
        return inspect(args.dir, args.tile, args.scale, args.json)
    return check(args.manifest, args.tile)


if __name__ == "__main__":
    sys.exit(main())
