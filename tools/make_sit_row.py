#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 4 张顾客行走图集追加第 5 行「坐姿」帧（240x480 -> 240x600）。

设计目标
--------
· 不引入新美术风格：上半身直接复用该角色现有行走帧（保证配色/描边一致）；
· 下半身（大腿前伸 + 靴子落地）用从该角色身上采样到的裤/靴/描边色程序化绘制；
· 每格 60x120 不变，新增行高 120，整图变 600；cell 仍是 [60,120]，原 4 行零改动；
· alpha 严格 0/255，和现有图集一致。

坐姿 4 格对应 ROW_ANIM 的 sit 动画帧：0=下(正面) 1=左 2=右 3=上(背面)，
与现有行走行的朝向约定一致（行 c 的坐姿由行 c 的站立帧推导）。

用法
----
  python tools/make_sit_row.py            # 处理 4 张顾客图，覆盖写回
  python tools/make_sit_row.py --dry-run  # 只生成预览，不写回

写回前会自动把原图备份到 <sheet>.bak（若已存在则跳过备份）。
"""
from __future__ import annotations

import argparse
import os
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC_DIR = os.path.join(ROOT, "assets", "actors", "npc")

CUSTOMERS = [
    "矮人战士_爱德华",
    "矿工少年_西蒙",
    "集市管理员_凯瑟琳",
    "雪山探险家_哈特菲利亚",
]

CELL_W, CELL_H = 60, 120
COLS = 4
SIT_ROW_Y = CELL_H * 4  # = 480，原始 4 行之后


def common_color(px, x0, y0, x1, y1, img_w, img_h, s_min, s_max):
    """取矩形区域内不透明像素、且总亮度 s 落在 [s_min,s_max] 的众数色。

    用亮度区间过滤，避免把黑描边/高光/杂色算进去：
      · 衣色用较亮区间（排除黑描边与白高光）；
      · 靴色用较暗区间（排除亮衣服）。
    """
    cnt = Counter()
    for y in range(max(0, y0), min(img_h, y1)):
        for x in range(max(0, x0), min(img_w, x1)):
            r, g, b, a = px[x, y]
            if a < 200:
                continue
            s = r + g + b
            if s < s_min or s > s_max:
                continue
            cnt[(r, g, b)] += 1
    if not cnt:
        return (120, 120, 120)
    return cnt.most_common(1)[0][0]


def darkest_color(px, x0, y0, x1, y1, img_w, img_h):
    best = None
    for y in range(max(0, y0), min(img_h, y1)):
        for x in range(max(0, x0), min(img_w, x1)):
            r, g, b, a = px[x, y]
            if a < 200:
                continue
            s = r + g + b
            if best is None or s < best[0]:
                best = (s, (r, g, b))
    return (0, 0, 0) if best is None else best[1]


def draw_block(px, x, y, w, h, fill, outline):
    """画一个 1px 描边的实心块（描边色先铺底，再填内部）。"""
    # 描边底
    for yy in range(y - 1, y + h + 1):
        for xx in range(x - 1, x + w + 1):
            if 0 <= xx < CELL_W and 0 <= yy < CELL_H:
                px[xx, yy] = (outline[0], outline[1], outline[2], 255)
    # 内部填充
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < CELL_W and 0 <= yy < CELL_H:
                px[xx, yy] = (fill[0], fill[1], fill[2], 255)


def build_sit_cell(base: Image.Image, facing: int) -> Image.Image:
    """由某方向的站立帧(60x120)推导一个坐姿帧。facing: 0下 1左 2右 3上。

    思路：头+躯干（含胯）直接复用站立帧顶部（截到胯部 y<=UPPER，不要腿），
    下半身整段重画成「大腿水平前伸 + 靴子落地」的坐姿块，去掉所有竖直腿像素，
    这样读起来是坐而不是站。
    """
    base_px = base.load()
    bw, bh = base.size

    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    px = cell.load()

    # 上半身（头+躯干+胯）复用站立帧顶部；截到胯部，绝不带竖直的腿
    UPPER = 70
    for y in range(0, UPPER):
        for x in range(0, CELL_W):
            r, g, b, a = base_px[x, y]
            if a >= 200:
                px[x, y] = (r, g, b, 255)

    # 采样配色：上躯干主衣色（亮区间，排除黑描边/白高光）作大腿/裙摆；
    # 靴子色（暗区间）作脚；最暗色作描边。
    garment = common_color(base_px, 6, 36, 54, 56, bw, bh, 150, 700)
    boots = common_color(base_px, 14, 100, 46, 118, bw, bh, 60, 260)
    outline = darkest_color(base_px, 0, 40, CELL_W, 118, bw, bh)

    # 坐姿下半身几何（按朝向）。大腿是横向块（前伸），脚在身前/侧落地。
    if facing in (0, 3):  # 下(正) / 上(背)：大腿横块与胯同宽，双脚在身前
        lap = (5, 70, 50, 20)      # x, y, w, h  -> 与胯同宽
        foot_l = (11, 90, 14, 28)
        foot_r = (35, 90, 14, 28)
    elif facing == 1:  # 左(侧面朝左)：大腿向左前伸，靴在左前
        lap = (3, 70, 48, 20)
        foot_l = (1, 90, 15, 28)
        foot_r = None
    else:  # facing == 2 右：大腿向右前伸，靴在右前
        lap = (9, 70, 48, 20)
        foot_l = None
        foot_r = (44, 90, 15, 28)

    draw_block(px, *lap, garment, outline)
    if foot_l:
        draw_block(px, *foot_l, boots, outline)
    if foot_r:
        draw_block(px, *foot_r, boots, outline)
    return cell


def extend_sheet(src_path: str, dry: bool) -> str:
    base = Image.open(src_path).convert("RGBA")
    w, h = base.size
    assert (w, h) == (240, 480), "预期 240x480，实际 %s" % ((w, h),)

    out = Image.new("RGBA", (240, 600), (0, 0, 0, 0))
    out.paste(base, (0, 0))

    out_px = out.load()
    for c in range(COLS):  # c = 朝向：0下 1左 2右 3上
        standing = base.crop((c * CELL_W, c * CELL_H, c * CELL_W + CELL_W, c * CELL_H + CELL_H))
        sit = build_sit_cell(standing, c)
        sx = c * CELL_W
        sy = SIT_ROW_Y
        sit_px = sit.load()
        for y in range(CELL_H):
            for x in range(CELL_W):
                r, g, b, a = sit_px[x, y]
                if a >= 200:
                    out_px[sx + x, sy + y] = (r, g, b, 255)

    if dry:
        stem = os.path.splitext(os.path.basename(src_path))[0]
        preview = os.path.join(ROOT, "tests", "sit_preview_%s.png" % stem)
        out.save(preview)
        return preview

    # 写回前备份（强制 PNG 格式，避免 .bak 扩展名让 PIL 猜格式失败）
    bak = src_path + ".bak"
    if not os.path.exists(bak):
        base.save(bak, "PNG")
    out.save(src_path)
    return src_path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for name in CUSTOMERS:
        src = os.path.join(NPC_DIR, name + ".png")
        if not os.path.exists(src):
            print("跳过（不存在）:", src)
            continue
        res = extend_sheet(src, args.dry_run)
        print(("[dry] 预览 -> " if args.dry_run else "已写回 -> "), os.path.relpath(res, ROOT))


if __name__ == "__main__":
    main()
