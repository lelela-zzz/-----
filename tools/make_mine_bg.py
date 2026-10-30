#!/usr/bin/env python3
"""矿井底图：把给定的洞穴平面图转成 1x(1024) 与 2x(2048) 两张底图。

思路（像素风标准做法）：先 LANCZOS 缩到 1024 作为 1x，再 NEAREST 2 倍放大得 2x，
保证 2x 是 1x 的干净整数倍，渲染时按 2x 贴、scale=0.5 落回逻辑 1024。

用法：python tools/make_mine_bg.py [源图路径]
默认源：tools/mine_src/mine_ref.jpg（已随工程保存，可复现）
产物：assets/mine/v1/scene_day_1x.png（1024²）
      assets/mine/v1/scene_day_2x.png（2048²）
      tests/probe_shots/mine_bg_grid.png（带 100px 网格的 1x 预览，标定碰撞用）
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = ROOT / "tools/mine_src/mine_ref.jpg"
OUT_DIR = ROOT / "assets/mine/v1"
PREVIEW = ROOT / "tests/probe_shots/mine_bg_grid.png"
NATIVE = 1024


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    im = Image.open(src).convert("RGB")

    one = im.resize((NATIVE, NATIVE), Image.LANCZOS)          # 1x 逻辑
    two = one.resize((NATIVE * 2, NATIVE * 2), Image.NEAREST)  # 2x = 干净 2×

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    one.save(OUT_DIR / "scene_day_1x.png")
    two.save(OUT_DIR / "scene_day_2x.png")

    grid = one.copy()
    d = ImageDraw.Draw(grid)
    for g in range(0, NATIVE + 1, 100):
        d.line([(g, 0), (g, NATIVE)], fill=(255, 255, 0))
        d.line([(0, g), (NATIVE, g)], fill=(255, 255, 0))
        d.text((g + 2, 2), str(g), fill=(255, 255, 0))
        d.text((2, g + 2), str(g), fill=(255, 255, 0))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    grid.save(PREVIEW)

    print(f"矿井底图 1x -> {OUT_DIR / 'scene_day_1x.png'}  {one.size}")
    print(f"矿井底图 2x -> {OUT_DIR / 'scene_day_2x.png'}  {two.size}")
    print(f"网格预览 -> {PREVIEW}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
