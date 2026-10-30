#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用一张侧视【坐姿】图直接替换凯瑟琳坐姿行的侧面两格（左/右），不重画。

流程：读图 -> 去背景（灰底洪水填充 + 去晕；已透明则跳过）-> 裁主体 ->
等比例缩放到填满 60x120 格（LANCZOS，脚底对齐格底、水平居中）-> alpha 二值化(0/255) ->
右朝向=原图、左朝向=镜像 -> 贴进坐姿行第 1(左)/2(右)列。第 0/3 列(正/背)不动。

用法
----
  python tools/place_catherine_sit_image.py <图片路径> [--dry-run]
"""
from __future__ import annotations

import argparse
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "actors", "npc", "集市管理员_凯瑟琳.png")

CELL_W, CELL_H = 60, 120
SIT_ROW_Y = 480
TARGET_H = 116          # 缩放后主体高度（留少量上下边距）
BG = (202, 203, 197)    # 新图背景色（暖灰）
TOL = 45


def key_background(im: Image.Image) -> Image.Image:
    """把与 BG 接近、且从边框连通的背景抠成透明；再去贴近透明的灰晕。"""
    W, H = im.size
    px = im.load()
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    op = out.load()
    for y in range(H):
        for x in range(W):
            r, g, b, _a = px[x, y]
            op[x, y] = (r, g, b, 255)

    def isbg(c):
        return max(abs(c[0] - BG[0]), abs(c[1] - BG[1]), abs(c[2] - BG[2])) <= TOL

    seen = [[False] * W for _ in range(H)]
    q = deque()
    for x in range(W):
        for yy in (0, H - 1):
            if isbg(px[x, yy]) and not seen[yy][x]:
                seen[yy][x] = True; q.append((x, yy))
    for y in range(H):
        for xx in (0, W - 1):
            if isbg(px[xx, y]) and not seen[y][xx]:
                seen[y][xx] = True; q.append((xx, y))
    while q:
        x, y = q.popleft(); op[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and isbg(px[nx, ny]):
                seen[ny][nx] = True; q.append((nx, ny))

    # 去晕：仍不透明但近背景色、且贴透明 -> 透明（迭代到稳定）
    changed = True
    def opaque(x, y): return op[x, y][3] > 0
    while changed:
        changed = False
        for y in range(H):
            for x in range(W):
                if not opaque(x, y):
                    continue
                c = op[x, y]
                if max(abs(c[0] - BG[0]), abs(c[1] - BG[1]), abs(c[2] - BG[2])) <= TOL:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if not (0 <= nx < W and 0 <= ny < H) or not opaque(nx, ny):
                            op[x, y] = (0, 0, 0, 0); changed = True; break
    return out


def bbox(im: Image.Image):
    op = im.load(); W, H = im.size
    xs = [x for x in range(W) for y in range(H) if op[x, y][3] > 0]
    ys = [y for y in range(H) for x in range(W) if op[x, y][3] > 0]
    return min(xs), min(ys), max(xs), max(ys)


def make_cell(img: Image.Image) -> Image.Image:
    x0, y0, x1, y1 = bbox(img)
    body = img.crop((x0, y0, x1 + 1, y1 + 1))
    bw, bh = body.size
    scale = TARGET_H / float(bh)
    nw = max(1, int(round(bw * scale)))
    big = body.resize((nw, TARGET_H), Image.LANCZOS)

    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    cpx = cell.load(); bpx = big.load()
    ox = (CELL_W - nw) // 2
    oy = CELL_H - TARGET_H          # 脚底对齐格底
    for y in range(TARGET_H):
        for x in range(nw):
            r, g, b, a = bpx[x, y]
            if a > 128:              # alpha 二值化：和项目 0/255 约定一致
                cpx[ox + x, oy + y] = (r, g, b, 255)
    return cell


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    img = Image.open(args.image).convert("RGBA")
    # 若不透明（有底色）则抠背景；本就透明（PNG）则跳过
    corners = [img.getpixel((0, 0)), img.getpixel((img.size[0] - 1, 0))]
    if any(c[3] > 0 for c in corners):
        img = key_background(img)

    right_cell = make_cell(img)                                  # 朝右（原样）
    left_cell = right_cell.transpose(Image.FLIP_LEFT_RIGHT)      # 朝左（镜像）

    sheet = Image.open(SRC).convert("RGBA")
    assert sheet.size == (240, 600), "预期 240x600，实际 %s" % (sheet.size,)
    s_px = sheet.load()
    for cx, cell in ((120, right_cell), (60, left_cell)):        # col2=右, col1=左
        cpx = cell.load()
        for y in range(CELL_H):
            for x in range(CELL_W):
                r, g, b, a = cpx[x, y]
                if a > 0:
                    s_px[cx + x, SIT_ROW_Y + y] = (r, g, b, 255)

    if args.dry_run:
        right_cell.save(os.path.join(ROOT, "tests", "cathsit_right.png"))
        left_cell.save(os.path.join(ROOT, "tests", "cathsit_left.png"))
        sheet.save(os.path.join(ROOT, "tests", "cathsit_full_preview.png"))
        right_cell.resize((240, 480), Image.NEAREST).save(os.path.join(ROOT, "tests", "cathsit_right_4x.png"))
        left_cell.resize((240, 480), Image.NEAREST).save(os.path.join(ROOT, "tests", "cathsit_left_4x.png"))
        print("[dry] 预览 -> tests/cathsit_right_4x.png / cathsit_left_4x.png / cathsit_full_preview.png")
        return

    bak = SRC + ".sit2.bak"
    if not os.path.exists(bak):
        Image.open(SRC).convert("RGBA").save(bak, "PNG")
    sheet.save(SRC)
    print("已写回 ->", os.path.relpath(SRC, ROOT))


if __name__ == "__main__":
    main()
