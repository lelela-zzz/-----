#!/usr/bin/env python3
"""雪山底图：清理生成图水印 → 1x(512) + 2x(1024)。

**尺寸以游戏内为准**：雪山地图逻辑尺寸 = 512²
（`scenes/snow_mountain.tscn` 相机 map_rect 512²、MapBounds walkable 504²、
objects/props.json 512 空间）。所以 1x=512²、2x=1024²；
Background 用 2x 且 scale=0.5 → 渲染回 512 逻辑尺寸，与相机限位吻合。

2x 是 1x 的 NEAREST 整数倍，保证 2x 渲染下每个逻辑像素 = 2×2。

缩放方式（像素画要点）：源图是 1x 的整数倍时用 **NEAREST 抽取**
——LANCZOS 会把相邻色混出新色，破坏限色板；非整数倍才退回 LANCZOS。

用法：python tools/make_snow_bg.py [源图路径]
默认源：tools/snow_src/ 下最新那张生成图
产物：assets/snow/v1/scene_day_1x.png（512²）
      assets/snow/v1/scene_day_2x.png（1024²）
      tests/probe_shots/snow_bg_grid.png（带 100px 网格的 1x 预览）
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "tools/snow_src"
OUT_DIR = ROOT / "assets/snow/v1"
PREVIEW = ROOT / "tests/probe_shots/snow_bg_grid.png"
NATIVE = 512

# 水印区域（右下角）。消除策略：从左侧克隆同色雪地覆盖
# （先前用"上方平移"会盖到深色植被，留下色块，故改为左向克隆 + 雪色校验）
# 按「原 1024 设计稿」的比例给出，NATIVE 变了自动跟随，不用手改坐标
WM_X0_F, WM_X1_F = 880 / 1024, 1.0
WM_Y0_F, WM_Y1_F = 950 / 1024, 1.0
WM_DX_F = 120 / 1024          # 向左克隆的水平偏移
WM_DY_UP_F = 110 / 1024       # 左手边若非雪，则向上取一截
WM_FALLBACK = (226, 236, 244)  # 兜底雪色（调冷后的冷白雪，别再用旧的暖雪色）


def _latest_raw() -> Path:
    imgs = sorted(SRC_DIR.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not imgs:
        raise SystemExit(f"没找到源图：{SRC_DIR}")
    return imgs[0]


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else _latest_raw()
    im = Image.open(src).convert("RGB")
    W, H = im.size

    # 1x：源图缩到 NATIVE。整数倍抽取用 NEAREST 保住限色板（LANCZOS 会混色）
    if W % NATIVE == 0 and H % NATIVE == 0:
        one = im.resize((NATIVE, NATIVE), Image.NEAREST)
        how = "NEAREST 整数抽取"
    else:
        one = im.resize((NATIVE, NATIVE), Image.LANCZOS)
        how = "LANCZOS（非整数倍，会轻微混色）"
    px = one.load()

    # 水印区按 NATIVE 折算（比例定义，换尺寸不用改坐标）
    WM_X0, WM_X1 = int(NATIVE * WM_X0_F), int(NATIVE * WM_X1_F)
    WM_Y0, WM_Y1 = int(NATIVE * WM_Y0_F), int(NATIVE * WM_Y1_F)
    WM_DX = max(1, int(NATIVE * WM_DX_F))
    WM_DY_UP = max(1, int(NATIVE * WM_DY_UP_F))

    def _is_snow(c: tuple[int, int, int]) -> bool:
        r, g, b = c
        return (b - r) < 30 and (r + g + b) / 3 > 175

    for y in range(WM_Y0, WM_Y1):
        for x in range(WM_X0, WM_X1):
            sx = x - WM_DX
            if 0 <= sx and _is_snow(px[sx, y]):
                px[x, y] = px[sx, y]
                continue
            sy = y - WM_DY_UP
            if 0 <= sy and _is_snow(px[x, sy]):
                px[x, y] = px[x, sy]
                continue
            px[x, y] = WM_FALLBACK

    two = one.resize((NATIVE * 2, NATIVE * 2), Image.NEAREST)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    one.save(OUT_DIR / "scene_day_1x.png")
    two.save(OUT_DIR / "scene_day_2x.png")

    grid = one.copy()
    d = ImageDraw.Draw(grid)
    for g in range(0, NATIVE + 1, 100):
        d.line([(g, 0), (g, NATIVE)], fill=(255, 255, 0))
        d.line([(0, g), (NATIVE, g)], fill=(255, 255, 0))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    grid.save(PREVIEW)

    print(f"源 -> {src.name}  ({W}x{H})")
    print(f"缩放方式 -> {how}  -> 1x {NATIVE}²")
    print(f"雪山底图 1x -> {OUT_DIR / 'scene_day_1x.png'}  {one.size}")
    print(f"雪山底图 2x -> {OUT_DIR / 'scene_day_2x.png'}  {two.size}")
    print(f"网格预览 -> {PREVIEW}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
