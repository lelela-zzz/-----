#!/usr/bin/env python3
"""把程序化家具合成到程序化背景上（同族风格验证）。

底图：assets/house/v3/bg_procedural_1x.png（程序化复刻，640x384）
底图已烘：后墙构件 + 吧台 col4-12 rows4.5-8（照蓝本，搬不动的）
落位（避开吧台与主门）：
- 左区 col1 rows7-8：桌+凳
- 吧台前 col5 rows8-9：桌+凳
- 火光区 col12 rows7-8：桌+凳
- 右下 col16 rows8：桌
- 炉边 col13-15 row4：酒桶 x3
按 footprint 底边 y 排序（远→近）。
"""
from __future__ import annotations

from PIL import Image

TILE = 32
BASE = "assets/house/v3/bg_procedural_1x.png"
SPR = "assets/house/v3/sprites"
OUT1 = "assets/house/v3/scene_proc_furnished_1x.png"
OUT2 = "assets/house/v3/scene_proc_furnished_2x.png"


def main() -> int:
    base = Image.open(BASE).convert("RGBA")

    def paste(name: str, col: int, row: int, fw: int, fh: int) -> None:
        sp = Image.open(f"{SPR}/{name}@1x.png").convert("RGBA")
        y = (row + fh) * TILE - sp.height
        base.alpha_composite(sp, (col * TILE, y))

    items = [
        ("table_old_2x1_down", 1, 7, 2, 1),
        ("bench_old_2x1_down", 1, 8, 2, 1),
        ("table_old_2x1_down", 5, 8, 2, 1),
        ("bench_old_2x1_down", 5, 9, 2, 1),
        ("table_old_2x1_down", 12, 7, 2, 1),
        ("bench_old_2x1_down", 12, 8, 2, 1),
        ("table_old_2x1_down", 16, 8, 2, 1),
        ("barrel_1x1_down", 13, 4, 1, 1),
        ("barrel_1x1_down", 14, 4, 1, 1),
        ("barrel_1x1_down", 15, 4, 1, 1),
    ]

    # 按 footprint 底边 y 排序（远→近）
    items.sort(key=lambda t: t[2] + t[4])
    for it in items:
        paste(*it)

    base.convert("RGB").save(OUT1)
    base.convert("RGB").resize((1280, 768), Image.NEAREST).save(OUT2)
    print(f"合成 {len(items)} 件 → {OUT1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
