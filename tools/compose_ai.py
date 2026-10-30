#!/usr/bin/env python3
"""把程序化家具合成到 AI 生成的酒馆背景上（同屏风格测试）。

底图：assets/house/v3/scene_ai_1x_nopalette.png（AI 原色，640x384）
布局：v3 酒馆布局 —— 客座区 rows7-10、酒桶 row4、按 footprint 底边 y 排序。
"""
from __future__ import annotations

from PIL import Image

TILE = 32
BASE = "assets/house/v3/scene_ai_1x_nopalette.png"
SPR = "assets/house/v3/sprites"
OUT1 = "assets/house/v3/scene_ai_furnished_1x.png"
OUT2 = "assets/house/v3/scene_ai_furnished_2x.png"


def main() -> int:
    base = Image.open(BASE).convert("RGBA")

    def paste(name: str, col: int, row: int, fw: int, fh: int) -> None:
        sp = Image.open(f"{SPR}/{name}@1x.png").convert("RGBA")
        y = (row + fh) * TILE - sp.height
        base.alpha_composite(sp, (col * TILE, y))

    items = []
    # 左长桌区（col1-8）：3 组桌+凳
    for col in (1, 4, 7):
        items.append(("table_old_2x1_down", col, 7, 2, 1))
        items.append(("bench_old_2x1_down", col, 8, 2, 1))
    # 右散座区（col11-18）：2 组桌+凳
    for col in (11, 14):
        items.append(("table_old_2x1_down", col, 7, 2, 1))
        items.append(("bench_old_2x1_down", col, 8, 2, 1))
    # 酒桶 3 只（吧台右侧、壁炉下方）
    for col in (13, 14, 15):
        items.append(("barrel_1x1_down", col, 4, 1, 1))

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
