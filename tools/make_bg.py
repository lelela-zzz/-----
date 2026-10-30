#!/usr/bin/env python3
"""程序化复刻酒馆背景 —— 以 AI 生成图为蓝本（scene_ai_1x_nopalette.png），按其框架重绘。

640×384 / 20×12 格。与家具同一套限色（palette v4：结构 + 地形木/石 + 光），
硬边、无渐变、无噪点、无半透明 —— 保证与程序化家具同族。

框架对照蓝本：
- 后墙 row0-1（深木骨墙：横梁+立柱）｜石拱小门 col0-1｜发光窗 col5-6｜酒瓶背柜 col9-12
- 石烟囱+壁炉 col13-15（从顶垂下，炉膛 y50-104）｜楼梯 col18-19 rows2-5
- 吧台 col4-12 rows4.5-8（台面 / 前立面 / 深影 三段）｜主门 col9-10 row11
- 地板竖向木板 + 窗光/火光三级实色光池（checker 抖动过渡）

明度阶梯：墙(最深) → 地板 MID → 光池 LIGHT/HI → 火/窗(最亮)
"""
from __future__ import annotations

import math
import random

from PIL import Image, ImageDraw

TILE = 32
W, H = 640, 384
OUT1 = "assets/house/v3/bg_procedural_1x.png"
OUT2 = "assets/house/v3/bg_procedural_2x.png"

# ── 与家具同一套限色 ──
OUTLINE = (0x3A, 0x2A, 0x22)   # 深褐描边/墙基/暗缝
INK = (0x20, 0x20, 0x18)       # 结构近黑（深影/炉膛内/板壁纹）
DARK = (0x50, 0x38, 0x18)      # 深木
MID = (0x78, 0x50, 0x28)       # 中木（地板基色）
LIGHT = (0x90, 0x68, 0x38)     # 浅木（台面/光池一级）
HI = (0xB0, 0x84, 0x50)        # 磨亮高光（光池二级/板缘受光）
STONE_D = (0x58, 0x58, 0x48)
STONE_M = (0x78, 0x78, 0x68)
STONE_L = (0xA0, 0x98, 0x88)
FIRE = (0xF2, 0x96, 0x32)
FIRE_HI = (0xFC, 0xD2, 0x84)


# ── 抖动工具（checker 硬边过渡，禁半透明）──
def dither_band(d, y0, y1, x0f, x1f, c):
    for y in range(y0, y1):
        a, b = int(x0f(y)), int(x1f(y))
        for x in range(a, b):
            if (x + y) % 4 < 2:
                d.point((x, y), c)


def dither_ring(d, cx, cy, rx, ry, c):
    for deg in range(0, 360, 2):
        rad = math.radians(deg)
        x = int(cx + math.cos(rad) * (rx + 2))
        y = int(cy + math.sin(rad) * (ry + 2))
        if 0 <= x < W and 0 <= y < H and (x + y) % 4 < 2:
            d.point((x, y), c)


def chamfer(d, box, bg, r=2, which="all"):
    """把矩形 box=(x0,y0,x1,y1) 的四角削 r 像素斜角，露出底色 bg（颜色，或按角 dict）。须在 fill 后调用。"""
    x0, y0, x1, y1 = box
    named = {"tl": (x0, y0), "tr": (x1, y0), "bl": (x0, y1), "br": (x1, y1)}
    pick = {"all": ("tl", "tr", "bl", "br"),
            "bottom": ("bl", "br"), "top": ("tl", "tr")}[which]
    for k in pick:
        cx, cy = named[k]
        c = bg[k] if isinstance(bg, dict) else bg
        for dx in range(r):
            for dy in range(r):
                if dx + dy <= r - 1:
                    px = cx + (dx if cx == x0 else -dx)
                    py = cy + (dy if cy == y0 else -dy)
                    d.point((px, py), c)


# ── 后墙 row0-1 ──
def wall(d):
    d.rectangle([0, 0, W - 1, 63], fill=OUTLINE)
    for x in range(10, W, 14):                      # 板壁竖细纹
        d.line([x, 10, x, 54], fill=INK)
    d.rectangle([0, 0, W - 1, 7], fill=DARK)        # 顶梁
    d.line([0, 0, W - 1, 0], fill=MID)
    d.line([0, 7, W - 1, 7], fill=INK)
    d.rectangle([0, 56, W - 1, 63], fill=DARK)      # 墙脚梁
    d.line([0, 56, W - 1, 56], fill=MID)
    for px_ in (0, 128, 256, 384, 512, 631):        # 立柱
        d.rectangle([px_, 8, px_ + 8, 55], fill=DARK)
        d.line([px_, 8, px_, 55], fill=MID)


# ── 地板 ──
def floor_planks(d):
    d.rectangle([0, 64, W - 1, H - 1], fill=MID)
    for x in range(0, W + 1, 24):                   # 竖板缝
        d.line([x, 64, x, H - 1], fill=OUTLINE)
    for i, x in enumerate(range(0, W, 24)):         # 错缝横线（逐板错位）
        off = (i % 4) * 24
        for y in range(64 + off, H, 96):
            d.line([x + 1, y, min(x + 22, W - 1), y], fill=OUTLINE)
    random.seed(11)
    for _ in range(150):                            # 稀疏木纹短刻
        x = random.randrange(2, W - 6)
        if x % 24 < 2:
            continue
        y = random.randrange(70, H - 2)
        d.line([x, y, x + random.randrange(2, 5), y], fill=DARK)
    d.rectangle([0, 64, W - 1, 67], fill=DARK)      # 墙脚接触阴影


# ── 光池（实色三级 + checker 抖动）──
# 注：窗光梯形池已按用户要求删除（地板上的"地毯"太奇怪）；火光池保留为炉火落地暖光。
def fire_pool(d):
    d.ellipse([410, 122, 554, 246], fill=LIGHT)     # 外圈浅木
    d.ellipse([442, 138, 522, 214], fill=HI)        # 内圈磨亮（贴炉膛）
    dither_ring(d, 482, 184, 55, 38, HI)            # HI→LIGHT 抖动过渡
    dither_ring(d, 482, 184, 71, 61, LIGHT)         # LIGHT→地板 抖动过渡


# ── 墙上构件 ──
def window(d):
    d.rectangle([146, 8, 238, 60], fill=DARK)       # 墙面暖光晕
    d.rectangle([158, 16, 226, 56], fill=OUTLINE)   # 框
    chamfer(d, (158, 16, 226, 56), DARK, 2)         # 框圆角（露出暖光）
    d.rectangle([161, 19, 223, 53], fill=FIRE)      # 玻璃
    d.line([191, 19, 192, 53], fill=OUTLINE, width=2)
    d.line([161, 35, 223, 36], fill=OUTLINE, width=2)
    for xa_, xb_ in ((163, 189), (194, 221)):       # 每块玻璃内上缘亮
        d.rectangle([xa_, 21, xb_, 24], fill=FIRE_HI)
        d.rectangle([xa_, 38, xb_, 41], fill=FIRE_HI)
    d.rectangle([154, 56, 230, 62], fill=STONE_M)   # 石窗台
    d.line([154, 56, 230, 56], fill=STONE_L)
    chamfer(d, (154, 56, 230, 62),
            {"tl": DARK, "tr": DARK, "bl": OUTLINE, "br": OUTLINE}, 2)


def shelf(d):
    bx0, bx1, by = 292, 380, 40
    d.rectangle([bx0, by, bx1, by + 6], fill=LIGHT)
    d.line([bx0, by, bx1, by], fill=HI)
    d.line([bx0, by + 6, bx1, by + 6], fill=DARK)
    chamfer(d, (bx0, by, bx1, by + 6), OUTLINE, 2)
    for bx in (bx0 + 6, bx1 - 16):
        d.polygon([(bx, by + 6), (bx + 11, by + 6), (bx, by + 18)], fill=DARK)
    bottles = [(302, 16, MID), (314, 12, DARK), (330, 18, MID),
               (346, 14, FIRE), (362, 16, DARK)]
    for x, h, c in bottles:
        d.rectangle([x, by - h, x + 7, by - 1], fill=c)
        d.rectangle([x + 2, by - h - 3, x + 4, by - h], fill=c)
        d.line([x + 1, by - h, x + 1, by - 1],
               fill=(FIRE_HI if c == FIRE else HI))


def arch_door(d):
    d.rectangle([6, 30, 58, 96], fill=STONE_M)
    d.ellipse([6, 12, 58, 60], fill=STONE_M)
    d.rectangle([12, 36, 52, 96], fill=INK)
    d.ellipse([12, 20, 52, 62], fill=INK)
    for x0, y0, x1, y1 in ((32, 20, 32, 12), (20, 24, 14, 18), (44, 24, 50, 18)):
        d.line([x0, y0, x1, y1], fill=STONE_D)
    d.line([9, 62, 9, 96], fill=STONE_D)
    d.line([55, 62, 55, 96], fill=STONE_D)
    d.line([6, 60, 12, 60], fill=STONE_D)
    d.line([52, 60, 58, 60], fill=STONE_D)
    d.rectangle([8, 14, 14, 20], fill=STONE_L)
    d.rectangle([46, 14, 52, 20], fill=STONE_L)


def fireplace(d):
    # 石烟囱：左受光 STONE_L / 中 STONE_M / 右阴影 STONE_D（立体块面）
    x0, x1, top, bot = 416, 511, 0, 104
    d.rectangle([x0, top, x1, bot], fill=STONE_M)
    d.rectangle([x0, top, x0 + 12, bot], fill=STONE_L)     # 左立受光
    d.rectangle([x1 - 14, top, x1, bot], fill=STONE_D)     # 右立阴影
    d.rectangle([x0, top, x1, top + 3], fill=STONE_L)      # 顶受光
    for y in range(12, bot, 12):                           # 砌石横缝
        d.line([x0 + 12, y, x1 - 14, y], fill=STONE_D)
    for i, y in enumerate(range(0, bot, 12)):
        off = 40 if i % 2 == 0 else 16
        for x in range(x0 + 12 + off, x1 - 14, 48):
            d.line([x, y + 1, x, min(y + 11, bot - 1)], fill=STONE_D)
    d.rectangle([x0, top, x1, bot], outline=OUTLINE)
    chamfer(d, (x0, top, x1, bot), OUTLINE, 2)
    # 炉膛（凹陷：左内受光 / 右内阴影 / 顶阴过梁投影）
    hx0, hx1, hy0, hy1 = 430, 497, 50, 104
    d.rectangle([hx0, hy0, hx1, hy1], fill=INK)
    d.rectangle([hx0, hy0, hx0 + 4, hy1], fill=STONE_L)    # 左内受光
    d.rectangle([hx1 - 4, hy0, hx1, hy1], fill=STONE_D)    # 右内阴影
    d.rectangle([hx0, hy0, hx1, hy0 + 6], fill=STONE_D)    # 顶阴
    d.rectangle([hx0, hy0, hx1, hy1], outline=OUTLINE)
    # 火
    d.rectangle([436, 78, 491, 104], fill=FIRE)
    d.ellipse([443, 70, 484, 96], fill=FIRE)
    for fx in (444, 460, 474):                             # 火焰舔舌
        fh = random.randrange(10, 18)
        d.polygon([(fx, 104), (fx + 7, 104), (fx + 3, 104 - fh)], fill=FIRE_HI)
    d.rectangle([438, 95, 472, 99], fill=DARK)             # 柴
    d.rectangle([452, 99, 488, 103], fill=DARK)
    # 石炉槛（mantel，立体：顶受光 / 左受光 / 右阴影）
    d.rectangle([412, 104, 515, 118], fill=STONE_M)
    d.rectangle([412, 104, 515, 106], fill=STONE_L)        # 顶受光
    d.rectangle([412, 104, 420, 118], fill=STONE_L)        # 左受光
    d.rectangle([507, 104, 515, 118], fill=STONE_D)        # 右阴影
    d.rectangle([412, 104, 515, 118], outline=OUTLINE)
    for x in range(436, 515, 26):
        d.line([x, 107, x, 117], fill=STONE_D)
    chamfer(d, (412, 104, 515, 118),
            {"tl": STONE_M, "tr": STONE_M, "bl": MID, "br": MID}, 2)


def stairs(d):
    x0, x1 = 578, 639
    d.rectangle([x0, 62, x1, 160], fill=DARK)
    for i in range(7):
        ty = 66 + i * 13
        d.rectangle([x0, ty, x1, ty + 8], fill=LIGHT if i % 2 == 0 else MID)
        d.line([x0, ty, x1, ty], fill=HI)
        d.line([x0, ty + 8, x1, ty + 8], fill=OUTLINE)
    d.rectangle([570, 62, 578, 168], fill=MID)      # 栏板
    d.line([570, 62, 570, 168], fill=HI)
    d.rectangle([570, 62, 578, 168], outline=OUTLINE)


# ── 吧台（立体：顶受光 / 右段阴影 / 落地投影；三段圆角）──
def counter(d):
    x0, x1 = 128, 383
    FLOOR = MID
    # 台面：左段受窗光更亮，右段进阴影
    d.rectangle([x0, 144, x1, 174], fill=LIGHT)
    d.rectangle([288, 144, x1, 174], fill=MID)          # 右段阴
    d.rectangle([x0, 144, x1, 146], fill=HI)            # 顶受光缘
    d.rectangle([x0, 144, x0 + 2, 174], fill=HI)        # 左立受光
    d.rectangle([x1 - 3, 144, x1, 174], fill=DARK)      # 右立阴影
    for x in range(x0 + 28, x1, 32):
        d.line([x, 147, x, 173], fill=DARK)
    d.line([x0, 174, x1, 174], fill=DARK)               # 台面底阴
    chamfer(d, (x0, 144, x1, 174), FLOOR, 2)
    # 前立面：顶受光 + 右段阴
    d.rectangle([x0, 175, x1, 205], fill=MID)
    d.rectangle([320, 175, x1, 205], fill=DARK)         # 右段阴
    d.rectangle([x0, 175, x1, 177], fill=HI)            # 前顶受光
    d.rectangle([x0, 175, x0 + 2, 205], fill=HI)        # 左立受光
    d.rectangle([x1 - 3, 175, x1, 205], fill=OUTLINE)   # 右立阴影
    for x in range(x0 + 20, x1, 26):
        d.line([x, 178, x, 204], fill=DARK)
    d.line([x0, 205, x1, 205], fill=OUTLINE)
    chamfer(d, (x0, 175, x1, 205), FLOOR, 2)
    # 深陷底柜：上阴 + 底缘受光落地
    d.rectangle([x0, 206, x1, 254], fill=DARK)
    d.rectangle([x0, 206, x1, 208], fill=OUTLINE)       # 凹陷上阴
    for x in range(x0 + 12, x1, 24):
        d.line([x, 209, x, 253], fill=OUTLINE)
    d.rectangle([x0, 252, x1, 254], fill=HI)            # 底柜底缘受光
    chamfer(d, (x0, 206, x1, 254), FLOOR, 2)
    # 落地投影（台前地板，checker 柔边）
    d.rectangle([x0, 255, x1, 257], fill=OUTLINE)
    dither_band(d, 257, 261, lambda y: x0 + 4, lambda y: x1 - 4, OUTLINE)
    # 台面道具：木酒杯 + 深色瓶
    d.rectangle([230, 152, 244, 166], fill=MID)
    d.rectangle([230, 152, 244, 155], fill=HI)
    d.rectangle([236, 166, 238, 172], fill=DARK)
    d.rectangle([231, 172, 243, 174], fill=MID)
    d.rectangle([300, 148, 310, 174], fill=DARK)
    d.rectangle([303, 144, 307, 148], fill=DARK)
    d.line([301, 149, 301, 173], fill=MID)


def main_door(d):
    d.rectangle([286, 350, 353, 383], fill=STONE_M)
    chamfer(d, (286, 350, 353, 383), MID, 2)
    d.line([286, 350, 353, 350], fill=STONE_L)
    d.rectangle([290, 354, 349, 383], fill=INK)
    d.rectangle([290, 354, 349, 358], fill=STONE_D)


def main() -> int:
    random.seed(5)
    im = Image.new("RGB", (W, H), OUTLINE)
    d = ImageDraw.Draw(im)
    wall(d)
    floor_planks(d)
    fire_pool(d)
    window(d)
    shelf(d)
    arch_door(d)
    fireplace(d)
    stairs(d)
    counter(d)
    main_door(d)
    im.save(OUT1)
    im.resize((W * 2, H * 2), Image.NEAREST).save(OUT2)
    print("程序化背景 →", OUT1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
