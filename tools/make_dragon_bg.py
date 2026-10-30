#!/usr/bin/env python3
"""龙巢底图：1920² 源图 → 1x(960) + 2x(1920) + 网格预览。

**尺寸决策**：源图 1920 是 960 的整数倍（×2），所以
- 2x 直接就是源图本身（零重采样，画质最保真）
- 1x 用 NEAREST 做 2×2 抽取（保住限色板，LANCZOS 会混出新色）
游戏逻辑尺寸 = 960²（`scenes/dragon_lair.tscn` 相机 map_rect 960²），
Background 用 2x 且 scale=0.5 → 渲染回 960 逻辑尺寸。

源图自带构图（不改图，只做尺寸与预览）：
- 中央巨石上盘踞的巨龙（演出主体）
- 底部正中魔法传送门（入口）
- 左侧骨骼堆 / 右下骨痕（纯装饰）
- 岩壁红色熔岩纹（环境光参考）
源图无水印（右下白痕经裁剪确认是骨骼装饰，不是签名）。

用法：python tools/make_dragon_bg.py <源图路径>
产物：assets/dragon_lair/v1/scene_1x.png   (960²)
      assets/dragon_lair/v1/scene_2x.png   (1920²)
      tests/probe_shots/dragon_bg_grid.png (带 100px 网格的 1x 预览)
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets/dragon_lair/v1"
PREVIEW = ROOT / "tests/probe_shots/dragon_bg_grid.png"
NATIVE = 960
DEFAULT_SRC = Path(
    r"C:/Users/了了啦/.workbuddy/clipboard-images/"
    r"clipboard-2026-10-30T01-45-09-643Z-82325cd1.jpg"
)


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.exists():
        raise SystemExit(f"没找到源图：{src}")
    im = Image.open(src).convert("RGB")
    W, H = im.size

    if W % NATIVE == 0 and H % NATIVE == 0:
        one = im.resize((NATIVE, NATIVE), Image.NEAREST)
        how = f"NEAREST 整数抽取 (÷{W // NATIVE})"
    else:
        one = im.resize((NATIVE, NATIVE), Image.LANCZOS)
        how = "LANCZOS（非整数倍，会轻微混色）"

    two = one.resize((NATIVE * 2, NATIVE * 2), Image.NEAREST)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    one.save(OUT_DIR / "scene_1x.png")
    two.save(OUT_DIR / "scene_2x.png")

    grid = one.copy()
    d = ImageDraw.Draw(grid)
    for g in range(0, NATIVE + 1, 100):
        col = (255, 255, 0) if g % 200 == 0 else (255, 0, 255)
        d.line([(g, 0), (g, NATIVE)], fill=col)
        d.line([(0, g), (NATIVE, g)], fill=col)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    grid.save(PREVIEW)

    print(f"源 -> {src.name}  ({W}x{H})")
    print(f"缩放 -> {how}  -> 1x {NATIVE}²")
    print(f"龙巢底图 1x -> {OUT_DIR / 'scene_1x.png'}  {one.size}")
    print(f"龙巢底图 2x -> {OUT_DIR / 'scene_2x.png'}  {two.size}")
    print(f"网格预览 -> {PREVIEW}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
