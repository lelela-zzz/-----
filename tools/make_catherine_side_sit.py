#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只给凯瑟琳的坐姿行补「侧面」两格（左=col1 / 右=col2），其余格（正/背）保持不动。

素材来源：凯瑟琳现有侧面站立帧（行1=左、行2=右）的【上半身】直接复用，
保证配色/描边/风格与整套图完全一致；下半身据坐姿重画——
长裙向前（朝坐姿朝向）垂落盖住大腿、鞋尖在身前落地，这是侧视"坐着"的最强剪影线索。
调色板取自凯瑟琳自己的图（cream 裙摆 / green 裙身 / 深棕发 / 深色鞋 / 暗描边），
不引入新颜色。

用法
----
  python tools/make_catherine_side_sit.py           # 写回凯瑟琳图
  python tools/make_catherine_side_sit.py --dry-run # 只出预览
"""
from __future__ import annotations

import argparse
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "actors", "npc", "集市管理员_凯瑟琳.png")

CELL_W, CELL_H = 60, 120
SIT_ROW_Y = 480  # 第 5 行（index 4）

# 凯瑟琳调色板（取自她自己的图，保持统一）
HAIR = (104, 79, 56)
APRON = (255, 252, 238)   # cream 围裙/前身
SKIRT = (60, 100, 83)     # green 裙身
SHOE = (37, 34, 31)       # 深色鞋
OUTLINE = (61, 55, 50)    # 暗描边/裙摆线


def draw_span(px, y, lx, rx, fill):
    """水平画一段，并在与透明相邻的边上描 1px 暗线。"""
    lx, rx = max(0, int(lx)), min(CELL_W - 1, int(rx))
    for x in range(lx, rx + 1):
        for nx in (x - 1, x + 1):
            if 0 <= nx < CELL_W and px[nx, y][3] < 200:
                px[nx, y] = (OUTLINE[0], OUTLINE[1], OUTLINE[2], 255)
        for ny in (y - 1, y + 1):
            if 0 <= ny < CELL_H and px[x, ny][3] < 200:
                px[x, ny] = (OUTLINE[0], OUTLINE[1], OUTLINE[2], 255)
        px[x, y] = (fill[0], fill[1], fill[2], 255)


def build_side_sit(base: Image.Image, facing: int) -> Image.Image:
    """facing>0=朝右(右坐姿 col2)，facing<0=朝左(左坐姿 col1)。"""
    base_px = base.load()
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    px = cell.load()

    # 1) 上半身（头+躯干+裙腰）直接复用站立帧顶部（截到 y<=72，不带竖直站立腿）
    for y in range(0, 73):
        for x in range(0, CELL_W):
            r, g, b, a = base_px[x, y]
            if a >= 200:
                px[x, y] = (r, g, b, 255)

    # 2) 长裙向前(朝坐姿朝向)垂落盖住大腿 + 鞋尖在身前落地
    #    侧视"坐着"的剪影线索：裙摆不是竖直下垂，而是向前凸出（膝前）再落地。
    #    用 y 从 70→92 的梯形：左缘略外扩、右缘（前身）大幅前伸。
    for y in range(70, 93):
        t = (y - 70) / 22.0
        left = 20 + t * 5.0
        right = 40 + t * 19.0          # 前身大幅前伸（右=朝右）
        if facing < 0:                 # 镜像到左侧
            left, right = (CELL_W - 1 - right), (CELL_W - 1 - left)
        draw_span(px, y, left, right, SKIRT)
        # 前身围裙(cream)条：贴前缘 14px
        apron_l = right - 14
        if facing < 0:
            apron_l = left
        draw_span(px, y, apron_l, right, APRON)

    # 3) 鞋：在前身正下方落地（指向坐姿朝向）
    for y in range(92, 119):
        if facing > 0:
            draw_span(px, y, 44, 58, SHOE)
        else:
            draw_span(px, y, 60 - 58, 60 - 44, SHOE)  # 镜像 44..58 -> 1..15? 计算：60-58=2,60-44=16 -> x 2..16

    return cell


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    sheet = Image.open(SRC).convert("RGBA")
    w, h = sheet.size
    assert (w, h) == (240, 600), "预期 240x600（已含坐姿行），实际 %s" % ((w, h),)
    s_px = sheet.load()

    # 站立帧：行1=左(frame0 在 x60,y120)、行2=右(x120,y240)
    left_base = sheet.crop((60, 120, 120, 240))
    right_base = sheet.crop((120, 240, 180, 360))

    sit_left = build_side_sit(left_base, -1)    # col1 朝左
    sit_right = build_side_sit(right_base, +1)  # col2 朝右

    # 只替换坐姿行第 1、2 列（x60..180），第 0、3 列（正/背）保持原样
    for cx, cell in ((60, sit_left), (120, sit_right)):
        cpx = cell.load()
        for y in range(CELL_H):
            for x in range(CELL_W):
                r, g, b, a = cpx[x, y]
                if a >= 200:
                    s_px[cx + x, SIT_ROW_Y + y] = (r, g, b, 255)

    if args.dry_run:
        stem = os.path.splitext(os.path.basename(SRC))[0]
        sheet.save(os.path.join(ROOT, "tests", "catherine_side_sit_preview.png"))
        sit_left.save(os.path.join(ROOT, "tests", "cath_sit_left_preview.png"))
        sit_right.save(os.path.join(ROOT, "tests", "cath_sit_right_preview.png"))
        print("[dry] 预览 -> tests/catherine_side_sit_preview.png (+ 左右单格)")
        return

    bak = SRC + ".side.bak"
    if not os.path.exists(bak):
        Image.open(SRC).convert("RGBA").save(bak, "PNG")
    sheet.save(SRC)
    print("已写回 ->", os.path.relpath(SRC, ROOT))


if __name__ == "__main__":
    main()
