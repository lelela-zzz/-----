#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""生成指引罗盘箭头：assets/ui/guide_arrow.png（16x16，朝上，黄色 + 描边黑）。

给 QuestGuide 的表现层 GuideArrow 用 —— 贴在屏幕边缘、绕自身中心旋转，
指向当前地图里的"下一跳传送点"（或目的地）。

画法纪律和项目美术管线一致：
  · 尺寸整除（16x16，运行时按 render_scale 整数倍放大，Nearest 不糊）；
  · **颜色只从色板取**（assets/palette/hearthvale-palette-v4.json）：
      FIRE_CORE #F6D08A 亮面、FIRE #E8963C 暗面、INK #181818 描边；
  · 描边黑 1px：像素箭头压在雪地/木墙/夜色上都得看得清轮廓。
  · 形状：上半三角箭头 + 下方短柄，上下左右对称，旋转后不歪。
"""

import os

from PIL import Image

SIZE = 16
CX = 8

# UiStyle 色板常量（assets/palette/hearthvale-palette-v4.json）
INK = (0x18, 0x18, 0x18, 255)        # 描边黑
FIRE_CORE = (0xF6, 0xD0, 0x8A, 255)    # 火心（亮面）
FIRE = (0xE8, 0x96, 0x3C, 255)         # 火光（暗面）
CLEAR = (0, 0, 0, 0)

HEAD_ROWS = 7     # 0..6 是箭头三角
STEM_TOP = 7      # 7..14 是柄
STEM_BOTTOM = 14


def is_arrow(x: int, y: int) -> bool:
    """箭头形状掩码：上三角 + 下竖柄，左右对称（以 x=7/8 之间为轴）。"""
    if 0 <= y < HEAD_ROWS:
        half = y + 1
        return CX - half <= x <= CX + half - 1
    if STEM_TOP <= y <= STEM_BOTTOM:
        return 6 <= x <= 9
    return False


def build():
    mask = [[is_arrow(x, y) for x in range(SIZE)] for y in range(SIZE)]

    img = Image.new("RGBA", (SIZE, SIZE), CLEAR)
    px = img.load()

    # 1px 描边：非箭头像素但八邻域里挨着箭头 → 描黑
    for y in range(SIZE):
        for x in range(SIZE):
            if mask[y][x]:
                continue
            hit = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < SIZE and 0 <= nx < SIZE and mask[ny][nx]:
                        hit = True
                        break
                if hit:
                    break
            if hit:
                px[x, y] = INK

    # 填色：竖中分，左亮右暗，给一点体积感（旋转时跟着转，一致）
    for y in range(SIZE):
        for x in range(SIZE):
            if not mask[y][x]:
                continue
            px[x, y] = FIRE_CORE if x < CX else FIRE

    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "ui")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "guide_arrow.png")
    build().save(out)
    print("wrote %s (%dx%d)" % (out, SIZE, SIZE))


if __name__ == "__main__":
    main()
