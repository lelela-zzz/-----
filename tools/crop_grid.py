#!/usr/bin/env python3
"""生成带坐标网格的放大裁剪图，用于手工描多边形。

用法：python tools/crop_grid.py X0 Y0 X1 Y1 NAME [倍数]
产物：tests/probe_shots/grid_NAME.png（网格 = 原图 10px 细线 / 50px 粗线+坐标标注）
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/village/v1/scene_day_1x.png"
OUT = ROOT / "tests/probe_shots"


def main() -> int:
    x0, y0, x1, y1 = (int(v) for v in sys.argv[1:5])
    name = sys.argv[5]
    scale = int(sys.argv[6]) if len(sys.argv) > 6 else 4
    im = Image.open(SRC).convert("RGB").crop((x0, y0, x1, y1))
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    d = ImageDraw.Draw(im, "RGBA")
    for gx in range(x0 - x0 % 10 + 10, x1, 10):
        strong = gx % 50 == 0
        d.line([( (gx - x0) * scale, 0), ((gx - x0) * scale, im.height)],
               fill=(255, 255, 255, 90 if strong else 40))
        if strong:
            d.text(((gx - x0) * scale + 2, 2), str(gx), fill=(255, 235, 120, 255))
    for gy in range(y0 - y0 % 10 + 10, y1, 10):
        strong = gy % 50 == 0
        d.line([(0, (gy - y0) * scale), (im.width, (gy - y0) * scale)],
               fill=(255, 255, 255, 90 if strong else 40))
        if strong:
            d.text((2, (gy - y0) * scale + 2), str(gy), fill=(255, 235, 120, 255))
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / f"grid_{name}.png")
    print(f"grid_{name}.png  crop=({x0},{y0})-({x1},{y1})  x{scale}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
