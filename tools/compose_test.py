#!/usr/bin/env python3
"""同屏测试：程序化铺一张 20×12（640×384）的黄昏空店底图，再把家具按 v3 布局贴进去。

目的不是"好看的底图"，而是检验三件事：
  1) 家具在木地板上会不会糊（明度是否拉开）
  2) 黄昏光斑是否让家具"跳出来"或"沉下去"
  3) 接触阴影够不够（当前只靠描边）
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageChops, ImageDraw

TILE = 32
COLS, ROWS = 20, 12
W, H = COLS * TILE, ROWS * TILE

OUTLINE = (0x3A, 0x2A, 0x22)
DARK = (0x50, 0x38, 0x18)
MID = (0x78, 0x50, 0x28)
LIGHT = (0x90, 0x68, 0x38)
STONE_D = (0x58, 0x58, 0x48)
STONE_M = (0x78, 0x78, 0x68)
STONE_L = (0xA0, 0x98, 0x88)
FIRE = (0xE8, 0x96, 0x3C)
FIRE_HI = (0xF6, 0xD0, 0x8A)
BLACK = (0x18, 0x18, 0x18)
WHITE = (0xF2, 0xF2, 0xEE)

SPRITES = os.path.join(os.path.dirname(__file__), "..", "assets", "house", "v3", "sprites")


def px(x, y, c, d):
    d.point((x, y), fill=c)


def draw_floor(im, d):
    """木地板：纵向板条。**用深木做主色**——家具是中木/浅木，必须比地板亮一档才跳得出来。"""
    d.rectangle([0, 64, W - 1, H - 1], fill=DARK)
    for x in range(0, W, 24):
        d.line([x, 64, x, H - 1], fill=OUTLINE)
    # 板条之间的错缝（短横线），让地板不像竖条纹
    for y in range(64, H, 64):
        for i, x in enumerate(range(0, W, 24)):
            if i % 2 == 0:
                d.line([x, y, x + 23, y], fill=OUTLINE)


def draw_wall(im, d):
    """后墙：比地板更深，靠木骨横梁与地板区分。"""
    d.rectangle([0, 0, W - 1, 63], fill=OUTLINE)
    d.rectangle([0, 0, W - 1, 8], fill=BLACK)
    for y in (14, 26):
        d.line([0, y, W - 1, y], fill=DARK)
    for x in range(0, W, 48):
        d.line([x, 8, x, 63], fill=DARK)
    d.line([0, 63, W - 1, 63], fill=BLACK)


def draw_openings(im, d):
    """小门 / 主门 / 两扇窗。"""
    # 小门（col1-2, row0-1）：通后院，门洞是全暗 + 一点冷光
    d.rectangle([32, 8, 96 - 1, 63], fill=BLACK)
    d.rectangle([34, 10, 94, 62], fill=(0x2B, 0x2B, 0x2B))

    # 主门（col9-10, row11）：向下开，门口一小片地面暗
    d.rectangle([288, 352, 352 - 1, 383], fill=BLACK)
    d.rectangle([290, 354, 350, 383], fill=(0x5E, 0x4C, 0x33))

    # 窗（col4-5 / col14-15）：黄昏的窗外不该比炉火更亮，用暖橙 + 少量亮芯
    for cx in (4, 14):
        x0 = cx * TILE
        d.rectangle([x0 + 4, 10, x0 + 60, 62], fill=FIRE)
        d.rectangle([x0 + 4, 10, x0 + 60, 62], outline=OUTLINE, width=1)
        d.rectangle([x0 + 8, 14, x0 + 24, 28], fill=FIRE_HI)
        d.line([x0 + 32, 10, x0 + 32, 62], fill=DARK)
        d.line([x0 + 4, 36, x0 + 60, 36], fill=DARK)


def draw_hearth(im, d):
    """壁炉（col7-8，嵌墙）。"""
    x0 = 7 * TILE + 2
    d.rectangle([x0, 12, x0 + 60, 63], fill=STONE_D)
    d.rectangle([x0, 12, x0 + 60, 63], outline=OUTLINE, width=1)
    d.rectangle([x0 + 10, 32, x0 + 50, 62], fill=BLACK)
    d.rectangle([x0 + 14, 48, x0 + 46, 62], fill=FIRE)
    d.rectangle([x0 + 20, 54, x0 + 40, 62], fill=FIRE_HI)


def draw_backbar(im, d):
    """背柜（col10-12，挂墙）。"""
    x0 = 10 * TILE
    d.rectangle([x0 + 2, 16, x0 + 92, 62], fill=DARK)
    d.rectangle([x0 + 2, 16, x0 + 92, 62], outline=OUTLINE, width=1)
    for y in (30, 44):
        d.line([x0 + 2, y, x0 + 92, y], fill=MID)
    for i in range(4):
        bx = x0 + 10 + i * 22
        d.rectangle([bx, 20, bx + 5, 28], fill=LIGHT)


def draw_bar(im, d):
    """吧台 10×1（row4）：台面 + 前沿立面 + 磨损。"""
    x0, y0 = 1 * TILE, 4 * TILE
    w = 10 * TILE
    d.rectangle([x0, y0, x0 + w - 1, y0 + 31], fill=OUTLINE)
    d.rectangle([x0 + 1, y0 + 1, x0 + w - 2, y0 + 19], fill=LIGHT)
    d.rectangle([x0 + 1, y0 + 20, x0 + w - 2, y0 + 30], fill=MID)
    d.line([x0 + 1, y0 + 19, x0 + w - 2, y0 + 19], fill=DARK)
    # 前沿被磨亮的一小段（用得最勤的地方）
    for i in range(6):
        d.line([x0 + 60 + i * 6, y0 + 21, x0 + 64 + i * 6, y0 + 21], fill=LIGHT)


def draw_stairs(im, d):
    """楼梯 2×2（col16-17, row2-3）：阶梯状正交折线。"""
    x0, y0 = 16 * TILE, 2 * TILE
    d.rectangle([x0, y0, x0 + 63, y0 + 63], fill=STONE_M)
    d.rectangle([x0, y0, x0 + 63, y0 + 63], outline=OUTLINE, width=1)
    for i in range(4):
        d.rectangle([x0 + 1, y0 + 1 + i * 15, x0 + 62, y0 + 15 + i * 15],
                    fill=STONE_M if i % 2 == 0 else STONE_D)
        d.line([x0 + 1, y0 + 15 + i * 15, x0 + 62, y0 + 15 + i * 15], fill=BLACK)


def draw_light(im, d):
    """黄昏光池：三级硬边衰减（深木地 → 中木 → 浅木），不用半透明叠加。"""
    for cx, spread in ((4, 26), (14, 26)):
        x0 = cx * TILE + 4
        # 外层：中木
        d.polygon([(x0, 66), (x0 + 56, 66), (x0 + 56 + spread, 214), (x0 - spread, 214)], fill=MID)
        # 中层：浅木（收窄）
        d.polygon([(x0 + 8, 66), (x0 + 48, 66), (x0 + 48 + 14, 178), (x0 + 8 - 14, 178)], fill=LIGHT)
        # 外缘抖动过渡（2 行 checker）
        for y in (214, 216):
            for x in range(x0 - spread, x0 + 56 + spread):
                if (x + y) % 4 < 2:
                    d.point((x, y), fill=DARK)

    # 炉火光池：三圈同心椭圆，硬边衰减
    d.ellipse([7 * TILE - 40, 70, 9 * TILE + 40, 196], fill=MID)
    d.ellipse([7 * TILE - 24, 72, 9 * TILE + 24, 168], fill=LIGHT)
    d.ellipse([7 * TILE - 10, 76, 9 * TILE + 10, 140], fill=FIRE)


def paste_sprite(im, name, col, row, fw, fh):
    p = os.path.join(SPRITES, f"{name}@1x.png")
    sp = Image.open(p).convert("RGBA")
    x = col * TILE
    y = (row + fh) * TILE - sp.height
    im.alpha_composite(sp, (x, y))


def main() -> int:
    im = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(im)

    draw_floor(im, d)
    draw_light(im, d)
    draw_wall(im, d)
    draw_openings(im, d)
    draw_hearth(im, d)
    draw_backbar(im, d)
    draw_stairs(im, d)
    draw_bar(im, d)

    # 家具：按 footprint 底边 y 排序后绘制（低者后画）
    items = []
    for col in (1, 4, 7):
        items.append(("table_old_2x1_down", col, 7, 2, 1))
        items.append(("bench_old_2x1_down", col, 8, 2, 1))
    for col in (11, 14):
        items.append(("table_old_2x1_down", col, 7, 2, 1))
        items.append(("bench_old_2x1_down", col, 8, 2, 1))
    for col in (13, 14, 15):
        items.append(("barrel_1x1_down", col, 4, 1, 1))

    items.sort(key=lambda t: (t[2] + t[4]))
    for name, col, row, fw, fh in items:
        paste_sprite(im, name, col, row, fw, fh)

    out = os.path.join(os.path.dirname(__file__), "..", "assets", "house", "v3")
    im.convert("RGB").save(os.path.join(out, "scene_test_1x.png"))
    im.convert("RGB").resize((W * 2, H * 2), Image.NEAREST).save(os.path.join(out, "scene_test_2x.png"))
    print(f"  640×384 → {out}/scene_test_1x.png")
    print(f"  1280×768 → {out}/scene_test_2x.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
