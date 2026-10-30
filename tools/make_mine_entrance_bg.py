#!/usr/bin/env python3
"""矿道入口底图：源图 2048² → 1024² 原生（÷2 整数倍），供大地图用。

用法：python tools/make_mine_entrance_bg.py [源图路径]
产物：assets/mine_entrance/v1/scene_day_1x.png（1024×1024）
      tests/probe_shots/mine_entrance_bg_grid.png（带 100px 网格的预览）
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = Path(
    r"C:/Users/了了啦/Documents/xwechat_files/wxid_m8ebswf5xjtx22_0473/"
    r"temp/RWTemp/2026-10/97147f7c841c31977426c1952f974979.png")
OUT = ROOT / "assets/mine_entrance/v1/scene_day_1x.png"
PREVIEW = ROOT / "tests/probe_shots/mine_entrance_bg_grid.png"
NATIVE = 1024


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    im = Image.open(src).convert("RGB")
    if im.size != (2048, 2048):
        im = im.resize((2048, 2048), Image.LANCZOS)
    core = im.resize((NATIVE, NATIVE), Image.NEAREST)      # 2048/2 整数倍

    OUT.parent.mkdir(parents=True, exist_ok=True)
    core.save(OUT)

    grid = core.copy()
    d = ImageDraw.Draw(grid)
    for g in range(0, NATIVE + 1, 100):
        d.line([(g, 0), (g, NATIVE)], fill=(255, 255, 0))
        d.line([(0, g), (NATIVE, g)], fill=(255, 255, 0))
        d.text((g + 2, 2), str(g), fill=(255, 255, 0))
        d.text((2, g + 2), str(g), fill=(255, 255, 0))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    grid.save(PREVIEW)
    print(f"矿道入口底图 -> {OUT}  {core.size}")
    print(f"网格预览 -> {PREVIEW}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
