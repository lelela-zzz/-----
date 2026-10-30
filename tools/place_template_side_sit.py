#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把用户给的凯瑟琳侧视图【直接】用到她的坐姿行侧面两格（不重画、不改配色）。

步骤（严格按用户要求："拿我给的图直接用"+"等比例放大到合适大小"+"只做侧面"）：
  1. 读入模板图（已是透明背景 RGBA）；
  2. 裁到主体包围盒（按列/行 alpha 计数 >=3 判主体，剔除右下角零星杂点）；
  3. 等比例放大（NEAREST，保像素），目标填满 60x120 格：高度贴到 ~118、脚底对齐格底；
  4. 水平居中放进 60x120 单元格 —— 这就是"右朝向"（模板原朝右）；
  5. 左右镜像得到"左朝向"；
  6. 贴进凯瑟琳坐姿行第 1（左）、2（右）列；第 0/3 列（正/背）保持不动。

用法
----
  python tools/place_template_side_sit.py           # 写回
  python tools/place_template_side_sit.py --dry-run # 只出预览
"""
from __future__ import annotations

import argparse
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = r"C:\Users\了了啦\.workbuddy\blobs\ea\ea107f92659ab3704ccbe4b709e95e6de83794fcd012c8fe37758843bddf8c0d.png"
SRC = os.path.join(ROOT, "assets", "actors", "npc", "集市管理员_凯瑟琳.png")

CELL_W, CELL_H = 60, 120
SIT_ROW_Y = 480
TARGET_H = 118   # 放大后主体高度（留 2px 上下不贴边）


def body_bbox(im: Image.Image):
    px = im.load(); W, H = im.size
    colc = [0] * W; rowc = [0] * H
    for y in range(H):
        for x in range(W):
            if px[x, y][3] > 128:
                colc[x] += 1; rowc[y] += 1
    xs = [x for x in range(W) if colc[x] >= 3]
    ys = [y for y in range(H) if rowc[y] >= 3]
    return min(xs), min(ys), max(xs), max(ys)


def make_cell(template: Image.Image) -> Image.Image:
    x0, y0, x1, y1 = body_bbox(template)
    body = template.crop((x0, y0, x1 + 1, y1 + 1))
    bw, bh = body.size
    # 等比例放大到高度 TARGET_H（NEAREST 保像素），宽度按比例
    scale = TARGET_H / float(bh)
    nw = max(1, int(round(bw * scale)))
    nh = TARGET_H
    big = body.resize((nw, nh), Image.NEAREST)

    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    px_x = (CELL_W - nw) // 2           # 水平居中
    px_y = CELL_H - nh                  # 脚底对齐格底
    cell.paste(big, (px_x, px_y), big)
    return cell


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    template = Image.open(TEMPLATE).convert("RGBA")
    right_cell = make_cell(template)              # 朝右（模板原样）
    left_cell = right_cell.transpose(Image.FLIP_LEFT_RIGHT)  # 朝左（镜像）

    sheet = Image.open(SRC).convert("RGBA")
    assert sheet.size == (240, 600), "预期 240x600，实际 %s" % (sheet.size,)
    s_px = sheet.load()
    for cx, cell in ((120, right_cell), (60, left_cell)):  # col2=右, col1=左
        cpx = cell.load()
        for y in range(CELL_H):
            for x in range(CELL_W):
                r, g, b, a = cpx[x, y]
                if a > 128:
                    s_px[cx + x, SIT_ROW_Y + y] = (r, g, b, 255)

    if args.dry_run:
        right_cell.save(os.path.join(ROOT, "tests", "tpl_sit_right.png"))
        left_cell.save(os.path.join(ROOT, "tests", "tpl_sit_left.png"))
        sheet.save(os.path.join(ROOT, "tests", "tpl_sit_full_preview.png"))
        print("[dry] 预览 -> tests/tpl_sit_right.png / tpl_sit_left.png / tpl_sit_full_preview.png")
        return

    bak = SRC + ".tpl.bak"
    if not os.path.exists(bak):
        Image.open(SRC).convert("RGBA").save(bak, "PNG")
    sheet.save(SRC)
    print("已写回 ->", os.path.relpath(SRC, ROOT))


if __name__ == "__main__":
    main()
