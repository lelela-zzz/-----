#!/usr/bin/env python3
"""地窖夜景烘焙：把白天底图压成"夜晚基调 + 吊灯暖光池"。

参数与 relight_village.py 的 night KEY 同源（ls=0.67 / ss=0.90 / 冷锚 #2C333E / w=0.22），
差别只在光源：地窖唯一光源是中部的挂灯，光池按径向衰减加在灯下方，
灯罩自身保持高亮度（否则夜景里灯是黑的）。

用法：python tools/relight_cellar.py
产物：assets/cellar/v1/scene_night_1x.png（640×512）
"""
from __future__ import annotations

import colorsys
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/cellar/v1/scene_day_1x.png"
OUT = ROOT / "assets/cellar/v1/scene_night_1x.png"

W, H = 640, 512
L_FLOOR = 0.04

# 夜景 grade（与 v15 night KEY 同参）
LS, SS = 0.67, 0.90
ANCHOR = (0x2C, 0x33, 0x3E)
ANCHOR_W = 0.22

# 吊灯（灯罩玻璃中心）与光池——按酒馆壁炉的路子：火焰本体保持白天像素，
# 周围是很大一片、没有可见边界的柔光，不做"亮球"
LAMP = (320, 236)
POOL_R = 190.0       # 光池半径（大到边缘落在暗部里，看不见圆的边界）
POOL_LIFT = 0.55     # 乘性提亮（越大越亮）
POOL_WARM_W = 0.16   # 暖色偏移强度
GLASS_R = 17.0       # 灯罩恢复白天像素的软半径
GLASS_BOOST = 1.06   # 灯罩亮度增益（略高于白天，像点着的样子）


def clamp8(v: float) -> int:
    return 0 if v < 0 else (255 if v > 255 else int(round(v)))


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    if im.size != (W, H):
        im = im.resize((W, H), Image.NEAREST)
    px = im.load()
    out = Image.new("RGB", (W, H))
    op = out.load()

    cx, cy = LAMP
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
            l = max(l * LS, L_FLOOR)
            s = min(1.0, s * SS)
            r2, g2, b2 = colorsys.hls_to_rgb(h, l, s)
            r2 *= 255.0
            g2 *= 255.0
            b2 *= 255.0
            r2 = r2 * (1 - ANCHOR_W) + ANCHOR[0] * ANCHOR_W
            g2 = g2 * (1 - ANCHOR_W) + ANCHOR[1] * ANCHOR_W
            b2 = b2 * (1 - ANCHOR_W) + ANCHOR[2] * ANCHOR_W

            # 光池：大半径 smoothstep 提亮 + 轻微偏暖，边缘完全融进暗部
            dist = math.hypot(x - cx, (y - cy) * 1.12)
            t = max(0.0, 1.0 - dist / POOL_R)
            s_ = t * t * (3.0 - 2.0 * t)
            r2 *= 1.0 + s_ * POOL_LIFT * (1.0 + POOL_WARM_W)
            g2 *= 1.0 + s_ * POOL_LIFT
            b2 *= 1.0 + s_ * POOL_LIFT * (1.0 - POOL_WARM_W)

            # 灯罩本体：软半径内混回白天像素（保住灯形与火苗，不做亮盘）
            d_glass = math.hypot(x - cx, (y - cy) * 1.02)
            if d_glass < GLASS_R:
                gm = (1.0 - d_glass / GLASS_R) ** 1.5
                r2 = r2 * (1 - gm) + r * GLASS_BOOST * gm
                g2 = g2 * (1 - gm) + g * GLASS_BOOST * gm
                b2 = b2 * (1 - gm) + b * GLASS_BOOST * gm

            op[x, y] = (clamp8(r2), clamp8(g2), clamp8(b2))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    prev = ROOT / "tests/probe_shots/cellar_night_2x.png"
    out.resize((W * 2, H * 2), Image.NEAREST).save(prev)
    print(f"地窖夜景 -> {OUT}")
    print(f"预览     -> {prev}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
