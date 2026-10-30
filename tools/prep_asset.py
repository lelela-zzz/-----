#!/usr/bin/env python3
"""把 AI 出图转成合规像素资产。

流程：抠洋红 → 裁到内容 → 校正到目标宽高比 → 缩放到目标尺寸 → 量化到 v4 色板 → 导出 @1x/@2x

用法：
  python prep_asset.py <src.png> <out_dir> <name> <W> <H> [--tile 32] [--scale 2] [--tol 60]
  例：python prep_asset.py raw/t.png out table_old 2 1
"""
from __future__ import annotations

import argparse
import json
import os
import sys

try:
    from PIL import Image, ImageChops
except ImportError:
    print("需要 Pillow", file=sys.stderr)
    sys.exit(2)

PALETTE_JSON = os.path.join(os.path.dirname(__file__), "..", "assets", "palette", "hearthvale-palette-v4.json")


def _hx(h: str) -> tuple[int, int, int]:
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))


# 材质色阶：(亮度上限, 颜色)。按亮度分段硬映射，避免串到不该用的材质色。
RAMPS = {
    "wood": [(30, "#181818"), (72, "#503818"), (145, "#785028"), (255, "#906838")],
    "stone": [(30, "#181818"), (72, "#585848"), (145, "#787868"), (255, "#A09888")],
}


def load_palette(d: dict, scope: str = "world") -> list[tuple[int, int, int]]:
    """按用途取子色板。

    world = 世界材质（建筑/家具/地面）：结构 + 地形 + 金属 + 火，**不含肤色与 UI**
    char  = 角色/UI：核心 32 全量
    """
    hexes: list[str] = []
    core = d["core"]["groups"]
    if scope == "char":
        for g in core:
            for c in g["colors"]:
                hexes.append(c["hex"])
    else:
        keep = {"structure", "metal", "light"}
        for g in core:
            if g["id"] in keep:
                for c in g["colors"]:
                    hexes.append(c["hex"])
        for g in d["terrain"]["palettes"][0]["seasons"]["summer"]["groups"]:
            for c in g["colors"]:
                hexes.append(c["hex"])
    out = []
    for h in hexes:
        rgb = (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))
        if rgb not in out:
            out.append(rgb)
    return out


def keyout_magenta(im: Image.Image, tol: int) -> Image.Image:
    """洋红及近洋红→透明。用『红蓝高、绿低』判定，比单点距离更稳。"""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r > 100 and b > 100 and g < min(r, b) - tol:
                px[x, y] = (0, 0, 0, 0)
    return im


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out_dir")
    ap.add_argument("name")
    ap.add_argument("gw", type=int, help="footprint 宽（格）")
    ap.add_argument("gh", type=int, help="footprint 高（格）")
    ap.add_argument("--tile", type=int, default=32)
    ap.add_argument("--scale", type=int, default=2, help="额外导出 @2x")
    ap.add_argument("--tol", type=int, default=60)
    ap.add_argument("--scope", choices=["world", "char"], default="world",
                    help="world=建筑家具地面（不含肤色）；char=角色与UI")
    ap.add_argument("--ramp", choices=list(RAMPS), default=None,
                    help="按材质色阶硬映射（推荐用于木/石类资产）")
    a = ap.parse_args()

    if not os.path.exists(a.src):
        print(f"找不到文件：{a.src}", file=sys.stderr)
        return 2
    pal = load_palette(json.load(open(PALETTE_JSON, encoding="utf-8")), a.scope)

    im = keyout_magenta(Image.open(a.src), a.tol)
    bbox = im.getbbox()
    if bbox is None:
        print("抠图后全透明，失败", file=sys.stderr)
        return 3
    im = im.crop(bbox)
    w0, h0 = im.size

    # 校正到目标宽高比（居中裁掉多余部分）
    tw, th = a.gw, a.gh
    target_ratio = tw / th
    cur_ratio = w0 / h0
    if cur_ratio > target_ratio:
        nw = int(round(h0 * target_ratio))
        off = (w0 - nw) // 2
        im = im.crop((off, 0, off + nw, h0))
    else:
        nh = int(round(w0 / target_ratio))
        off = (h0 - nh) // 2
        im = im.crop((0, off, w0, off + nh))

    # 缩放到目标像素：用 NEAREST 点采样，保留原图色块（面积平均会在平涂面产生杂色）
    W, H = tw * a.tile, th * a.tile
    im = im.resize((W, H), Image.NEAREST)

    # 上色：优先用材质色阶映射（保证不会串到别的材质），否则退回全色板最近色
    alpha = im.getchannel("A").point(lambda v: 255 if v > 96 else 0)
    if a.ramp:
        ramp = RAMPS[a.ramp]
        g = im.convert("L")
        base = Image.new("RGBA", im.size, _hx(ramp[-1][1]))
        for i, (thr, hexv) in enumerate(ramp):
            lo = ramp[i - 1][0] if i > 0 else -1
            mask = g.point(lambda v, lo=lo, thr=thr: 255 if lo < v <= thr else 0)
            base.paste(Image.new("RGBA", im.size, _hx(hexv)), (0, 0), mask)
        out = base
    else:
        rgb = im.convert("RGB")
        pal_img = Image.new("P", (1, 1))
        flat = [v for c in pal for v in c]
        pal_img.putpalette(flat + [0] * (768 - len(flat)))
        out = rgb.quantize(palette=pal_img, dither=Image.Dither.NONE).convert("RGBA")
    out.putalpha(alpha)

    # 锚点对齐：内容底边贴画布底、水平居中（避免下采样后留边）
    bb2 = out.getbbox()
    if bb2:
        dx = (out.width - (bb2[2] + bb2[0])) // 2
        dy = out.height - bb2[3]
        out = ImageChops.offset(out, dx, dy)
    # 兜底：极少数边缘像素会被量化成板外色，统一压到描边黑
    if not a.ramp:
        px = out.load()
        pset = set(pal)
        for yy in range(out.height):
            for xx in range(out.width):
                r, g, b, al = px[xx, yy]
                if al > 0 and (r, g, b) not in pset:
                    px[xx, yy] = (pal[0][0], pal[0][1], pal[0][2], 255)

    os.makedirs(a.out_dir, exist_ok=True)
    p1 = os.path.join(a.out_dir, f"{a.name}@{1}x.png")
    out.save(p1, optimize=True)
    p2 = None
    if a.scale > 1:
        p2 = os.path.join(a.out_dir, f"{a.name}@{a.scale}x.png")
        out.resize((W * a.scale, H * a.scale), Image.NEAREST).save(p2, optimize=True)

    cols = len({c for c in out.getcolors(100000) if c[1][3] > 0})
    inpal = all(tuple(c[1][:3]) in {tuple(p) for p in pal} for c in out.getcolors(100000) if c[1][3] > 0)
    print(f"{a.name}: {W}×{H} px（{tw}×{th} 格）| 用色 {cols} | 全部在板内：{'是' if inpal else '否'}")
    print(f"  → {p1}" + (f"\n  → {p2}" if p2 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
