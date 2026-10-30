#!/usr/bin/env python3
"""地窖底图：源图 2048²（4x 网格）→ 512² 原生，再向左右各延展 64px 边框，
得到 640×512 的底图（视口 640×384，横向刚好铺满、纵向可上下摇）。

用法：python tools/make_cellar_bg.py [源图路径]
产物：assets/cellar/v1/scene_day_1x.png（640×512）
      tests/probe_shots/cellar_bg_2x.png（2 倍预览）
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = Path(
    r"C:/Users/了了啦/Documents/xwechat_files/wxid_m8ebswf5xjtx22_0473/"
    r"temp/RWTemp/2026-10/53cbb0eaedd5b4c2323ff3929e36b572.png")
OUT = ROOT / "assets/cellar/v1/scene_day_1x.png"
PREVIEW = ROOT / "tests/probe_shots/cellar_bg_2x.png"
NATIVE = 512
CANVAS_W = 640


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    im = Image.open(src).convert("RGB")
    if im.size != (2048, 2048):
        im = im.resize((2048, 2048), Image.LANCZOS)
    core = im.resize((NATIVE, NATIVE), Image.NEAREST)   # 2048/4 整数倍

    canvas = Image.new("RGB", (CANVAS_W, NATIVE))
    pad = (CANVAS_W - NATIVE) // 2
    canvas.paste(core, (pad, 0))
    # 左右用边框列延展（保住竖向木纹）
    for x in range(pad):
        for y in range(NATIVE):
            canvas.putpixel((x, y), core.getpixel((0, y)))
            canvas.putpixel((CANVAS_W - 1 - x, y), core.getpixel((NATIVE - 1, y)))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((CANVAS_W * 2, NATIVE * 2), Image.NEAREST).save(PREVIEW)
    print(f"地窖底图 -> {OUT}  {canvas.size}")
    print(f"预览     -> {PREVIEW}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
