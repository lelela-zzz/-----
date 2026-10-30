#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""手绘【像素风】任务手册图标 v3（64x64，硬像素、限量色板）。
参考用户给的样图：一本**斜放(约 -18°)的 3/4 俯视**厚皮手册 ——
顶盖(棕皮) + 前/右页口(米白) + 一条横亘的皮带(红梅) + 金属扣。
画风对齐小镇/item 图标：纯色像素块 + 5 档明暗 + 1px 暗描边 + 柔和暖光晕。

流程：在 76x76 画布上画轴对齐的 3/4 书 → 旋转 -18°(顺时针) → 裁回 64x64。
输出：assets/items/icons/quest_notebook.png
"""
from __future__ import annotations

import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "items", "icons", "quest_notebook.png")

C = 76            # 工作画布（留旋转余量）
img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
P = img.load()

# 限量色板（小镇皮革/亚麻/火色系）
OUTL = (40, 26, 18)
LEA_SH = (72, 44, 30)
LEA_D = (108, 68, 42)
LEA = (150, 100, 60)
LEA_L = (192, 138, 88)
LEA_HL = (218, 172, 120)
PAGE = (224, 214, 194)
PAGE_D = (188, 176, 150)
PAGE_L = (242, 234, 216)
STRAP = (188, 60, 84)      # 红梅皮带
STRAP_D = (140, 42, 62)
METAL = (190, 180, 152)
METAL_D = (110, 100, 82)
METAL_L = (224, 214, 188)
GOLD = (206, 162, 86)
GLOW = (255, 228, 156)

random.seed(11)


def px(x, y, c):
    if 0 <= x < C and 0 <= y < C:
        P[x, y] = (c[0], c[1], c[2], 255)


def rect(x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(x, y, c)


def hline(x0, x1, y, c):
    for x in range(x0, x1 + 1):
        px(x, y, c)


def vline(x, y0, y1, c):
    for y in range(y0, y1 + 1):
        px(x, y, c)


def rrect(x0, y0, x1, y1, c, cut=2):
    """圆角矩形（像素风：切掉 cut 像素的角）。"""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            dx = min(x - x0, x1 - x)
            dy = min(y - y0, y1 - y)
            if dx + dy >= cut:
                px(x, y, c)


def glow(cx, cy, rx, ry):
    for y in range(C):
        for x in range(C):
            if P[x, y][3] != 0:
                continue
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d < 1.0:
                a = int(74 * (1.0 - d))
                if a > 6:
                    P[x, y] = (GLOW[0], GLOW[1], GLOW[2], a)


# ---- 3/4 书（轴对齐）------------------------------------------------------
# 顶盖面
TX0, TY0, TX1, TY1 = 16, 12, 56, 46
# 右侧页口（3/4 Depth：右缘下移）
RX0, RX1 = 56, 63
RY0, RY1 = 17, 52
# 前侧页口（底缘）
FY0, FY1 = 46, 54

glow((TX0 + RX1) // 2, (TY0 + FY1) // 2, 32, 36)

# 页口（右 + 前），米白 + 页线
rect(RX0, RY0, RX1, RY1, PAGE)
rect(TX0, FY0, RX1, FY1, PAGE)
hline(RX0, RX1, RY0, PAGE_D); hline(RX0, RX1, RY1, PAGE_D)
hline(TX0, RX1, FY0, PAGE_D); hline(TX0, RX1, FY1, PAGE_D)
for y in range(RY0 + 2, RY1, 2):
    px(RX0 + 2, y, PAGE_L); px(RX0 + 4, y, PAGE_D)
for y in range(FY0 + 2, FY1, 2):
    px(TX0 + 3, y, PAGE_L); px(TX0 + 6, y, PAGE_D)

# 顶盖（棕皮，5 档斜向明暗：左上受光）
tw, th = TX1 - TX0, TY1 - TY0
for y in range(TY0, TY1 + 1):
    for x in range(TX0, TX1 + 1):
        t = ((x - TX0) + (y - TY0)) / float(tw + th)
        if t < 0.16:
            c = LEA_HL
        elif t < 0.40:
            c = LEA_L
        elif t < 0.64:
            c = LEA
        elif t < 0.85:
            c = LEA_D
        else:
            c = LEA_SH
        px(x, y, c)
# 切圆角
for (cx, cy) in [(TX0, TY0), (TX1, TY0), (TX0, TY1), (TX1, TY1)]:
    px(cx, cy, (0, 0, 0, 0))
    P[cx, cy] = (0, 0, 0, 0)
# 皮革颗粒
for _ in range(40):
    gx = random.randint(TX0 + 2, TX1 - 2)
    gy = random.randint(TY0 + 2, TY1 - 2)
    px(gx, gy, LEA_D if random.random() < 0.5 else LEA_L)

# 封面缝线（内缩虚线）
for x in range(TX0 + 4, TX1 - 3, 3):
    px(x, TY0 + 3, OUTL); px(x, TY1 - 3, OUTL)
for y in range(TY0 + 3, TY1 - 3, 3):
    px(TX0 + 3, y, OUTL); px(TX1 - 3, y, OUTL)

# 皮带（横亘顶盖 + 包到前/右页口），红梅 + 暗边
BY0, BY1 = 26, 33
rect(TX0, BY0, TX1, BY1, STRAP)
hline(TX0, TX1, BY0, STRAP_D); hline(TX0, TX1, BY1, STRAP_D)
# 皮带包到前页口（向下延伸）
rect(TX0 + 2, FY0 - 2, TX1 - 2, FY1, STRAP)
hline(TX0 + 2, TX1 - 2, FY0 - 2, STRAP_D)

# 金属扣（皮带正中，金色）
kx, ky = 36, 29
rect(kx - 5, ky - 4, kx + 5, ky + 4, METAL)
hline(kx - 5, kx + 5, ky - 4, METAL_L); hline(kx - 5, kx + 5, ky + 4, METAL_D)
vline(kx - 5, ky - 4, ky + 4, METAL_D); vline(kx + 5, ky - 4, ky + 4, METAL_D)
rect(kx - 2, ky - 2, kx + 2, ky + 2, GOLD)
px(kx, ky, OUTL)

# 整书 1px 暗描边（顶盖 + 页口外缘）
for x in range(TX0, TX1 + 1):
    px(x, TY0, OUTL)
for y in range(TY0, TY1 + 1):
    px(TX0, y, OUTL); px(TX1, y, OUTL)
for y in range(RY0, RY1 + 1):
    px(RX1, y, OUTL)
for x in range(TX0, RX1 + 1):
    px(x, FY1, OUTL)

# ---- 旋转 -18°（顺时针）并裁回 64x64 --------------------------------------
rot = img.rotate(-18, resample=Image.NEAREST, expand=False)
# 裁中心 64x64
ox, oy = (C - 64) // 2, (C - 64) // 2
final = rot.crop((ox, oy, ox + 64, oy + 64))
final.save(OUT)
print("saved", os.path.relpath(OUT, ROOT), final.size)
