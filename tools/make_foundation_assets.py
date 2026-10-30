#!/usr/bin/env python3
"""生成 Godot 基础模块所需的两张程序化素材。

1) 角色占位色块：严格 1:3 长宽比（竖块，1x 16x48 / 2x 32x96），
   纯色填充 + 1px 深色描边 + 顶部 1px 高光（读作"头"），便于在木地板上辨识、
   也给后续替换成真像素角色留出同样的画布尺寸。
2) 炉火点光源贴图：PointLight2D 用的径向遮罩，做成 10 台阶跳变
   （而非平滑渐变），保持项目"实色分档 + 禁半透明光斑"的像素画规范。

用法：python tools/make_foundation_assets.py
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

OUT_ACTOR = "assets/actors"
OUT_LIGHT = "assets/lighting"

PLAYER_W, PLAYER_H = 16, 48           # 1:3（宽:高）
PLAYER_FILL = (146, 158, 180)         # 中性石板灰蓝：与暖木背景最大区分，且夜里压得住光
PLAYER_EDGE = (43, 50, 64)            # 描边 #2B3240
PLAYER_TOP = (178, 188, 206)          # 顶缘高光

LIGHT_SIZE = 128
LIGHT_STEPS = 10
LIGHT_CORE = (255, 246, 232)          # 近白暖，避免与 light_color 叠加成橙雾


def make_player(path: str, scale: int) -> None:
    w, h = PLAYER_W * scale, PLAYER_H * scale
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], fill=PLAYER_FILL, outline=PLAYER_EDGE, width=scale)
    d.rectangle([scale, scale, w - scale - 1, 2 * scale - 1], fill=PLAYER_TOP)
    im.save(path)
    print(f"角色占位 → {path}  {w}x{h}  宽:高 = 1:{h / w:.2f}")


def make_light(path: str, scale: int) -> None:
    size = LIGHT_SIZE * scale
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    cx = cy = (size - 1) / 2.0
    r_max = size / 2.0
    for y in range(size):
        for x in range(size):
            # 归一化距离 + 轻微 gamma 让外圈铺得开一点
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / r_max
            if d >= 1.0:
                continue
            v = (1.0 - d) ** 1.35                     # 连续衰减
            step = round(v * LIGHT_STEPS) / LIGHT_STEPS  # 台阶化
            if step <= 0.0:
                continue
            px[x, y] = (*LIGHT_CORE, int(round(step * 255)))
    im.save(path)
    print(f"炉火光贴图 → {path}  {size}x{size}  {LIGHT_STEPS} 台阶")


def main() -> int:
    os.makedirs(OUT_ACTOR, exist_ok=True)
    os.makedirs(OUT_LIGHT, exist_ok=True)
    make_player(f"{OUT_ACTOR}/player_placeholder_1x.png", 1)
    make_player(f"{OUT_ACTOR}/player_placeholder_2x.png", 2)
    make_light(f"{OUT_LIGHT}/light_warm_radial_1x.png", 1)
    make_light(f"{OUT_LIGHT}/light_warm_radial_2x.png", 2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
