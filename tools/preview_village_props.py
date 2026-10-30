#!/usr/bin/env python3
"""遮挡件抠图「按原布局」预览图：所有抠件按 sprite_rect 贴回原位，置于深色底上。

用途：肉眼核验每张抠图的 alpha 边界是否干净、有没有把路面/背景误抠进来。
数据源 = cut_village_props.py 的 OBJECTS（单一来源），改完坐标重跑即可刷新。

用法：
  python tools/preview_village_props.py [倍数]   # 默认 2x NEAREST
产物：tests/probe_shots/village_props_layout.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

import sys as _sys

_sys.path.insert(0, str(Path(__file__).resolve().parent))
from cut_village_props import OBJECTS, build_mask  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/village/v1/scene_day_1x.png"
OUT = ROOT / "tests/probe_shots/village_props_layout.png"

BG = (24, 26, 32)          # 深色底，衬出抠图边界
LABEL = (255, 235, 120)    # 名牌文字
LABEL_BG = (0, 0, 0, 170)


def main() -> int:
    scale = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    day = Image.open(SRC).convert("RGB")

    canvas = Image.new("RGB", (day.width, day.height), BG)
    d = ImageDraw.Draw(canvas, "RGBA")

    n = 0
    for entry in OBJECTS:
        if "shapes" not in entry:
            continue
        cut, rect = build_mask(day, entry)
        canvas.paste(cut, (rect[0], rect[1]), cut)
        # 名牌：抠图左上角
        text = entry["name"]
        tw = d.textlength(text)
        x0, y0 = rect[0], max(0, rect[1] - 11)
        d.rectangle((x0, y0, x0 + tw + 3, y0 + 11), fill=LABEL_BG)
        d.text((x0 + 1, y0 + 1), text, fill=LABEL)
        n += 1

    if scale != 1:
        canvas = canvas.resize((canvas.width * scale, canvas.height * scale),
                               Image.NEAREST)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT)
    print(f"遮挡件布局预览（{n} 件, {scale}x）-> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
