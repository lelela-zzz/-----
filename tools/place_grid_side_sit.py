#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从用户给的 4x6 侧坐网格图（深蓝灰底 + 浅灰圆角面板，每格一个朝右侧坐角色）
截取若干格，抠掉面板背景，缩放进 60x120 单元格（脚底对齐格底、水平居中），
右朝向=原样、左朝向=镜像，贴进对应顾客图集坐姿行第 1(左)/2(右) 列。
第 0/3 列（正/背，程序化帧）保持不动。

网格面板坐标由 tools/analyze_grid3.py 检测得到（1920x1370，面板约 310x310）。

用法
----
  python tools/place_grid_side_sit.py --dry-run   # 只出预览
  python tools/place_grid_side_sit.py             # 写回 3 张顾客图
"""
from __future__ import annotations

import argparse
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRID = os.path.join(ROOT, "tests", "sidesit_grid.jpg")
NPC_DIR = os.path.join(ROOT, "assets", "actors", "npc")

CELL_W, CELL_H = 60, 120
SIT_ROW_Y = 480          # 第 5 行（index 4）
MAX_W, MAX_H = 56, 116   # 缩放上限（留 2px 边距）
INSET = 20               # 从面板 bbox 内缩，避开圆角边缘
BG_TOL = 58              # 面板浅灰抠除容差

# 顾客 -> 网格面板 bbox（来自 analyze_grid3.py 检测）
MAP = {
    "雪山探险家_哈特菲利亚":   (1601, 697, 1911, 1007),   # row2,col5 金发女探险家
    "矿工少年_西蒙":     (8, 697, 318, 1007),       # row2,col0 护目镜少年
    "矮人战士_爱德华":   (645, 361, 955, 670),       # row1,col2 络腮胡矮人
}


def flood_from_corner(op, W, H, sx, sy, bg, tol):
    sc = op[sx, sy][:3]
    q = deque([(sx, sy)])
    bg[sy][sx] = True
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and not bg[ny][nx]:
                c = op[nx, ny][:3]
                if max(abs(c[0] - sc[0]), abs(c[1] - sc[1]), abs(c[2] - sc[2])) <= tol:
                    bg[ny][nx] = True
                    q.append((nx, ny))


def key_panel(crop: Image.Image) -> Image.Image:
    """抠掉浅灰面板背景，返回透明背景的 RGBA。"""
    W, H = crop.size
    out = crop.convert("RGBA")
    op = out.load()
    bg = [[False] * W for _ in range(H)]
    for (sx, sy) in [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)]:
        if not bg[sy][sx]:
            flood_from_corner(op, W, H, sx, sy, bg, BG_TOL)
    for y in range(H):
        for x in range(W):
            if bg[y][x]:
                op[x, y] = (0, 0, 0, 0)
    return out


def remove_small_components(im: Image.Image, min_area: int = 45) -> Image.Image:
    """去掉与主体不相连的小块（如源图里角色脚下的彩色地面阴影）。保留 >= min_area 的块。"""
    W, H = im.size
    px = im.load()
    opaque = [[px[x, y][3] > 128 for x in range(W)] for y in range(H)]
    visited = [[False] * W for _ in range(H)]
    comps = []
    for y in range(H):
        for x in range(W):
            if opaque[y][x] and not visited[y][x]:
                q = [(x, y)]
                visited[y][x] = True
                size = 0
                while q:
                    cx, cy = q.pop()
                    size += 1
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < W and 0 <= ny < H and opaque[ny][nx] and not visited[ny][nx]:
                            visited[ny][nx] = True
                            q.append((nx, ny))
                comps.append(size)
    # 仅当小块明显小于主体时才删（避免删掉相连的小附件）
    if not comps:
        return im
    largest = max(comps)
    if largest < min_area * 3:
        return im  # 主体本身就很小，不删
    out = im.copy()
    op = out.load()
    visited = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if opaque[y][x] and not visited[y][x]:
                q = [(x, y)]
                visited[y][x] = True
                size = 0
                while q:
                    cx, cy = q.pop()
                    size += 1
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < W and 0 <= ny < H and opaque[ny][nx] and not visited[ny][nx]:
                            visited[ny][nx] = True
                            q.append((nx, ny))
                if size < min_area:
                    for yy in range(H):
                        for xx in range(W):
                            if visited[yy][xx]:
                                op[xx, yy] = (0, 0, 0, 0)
    return out


def despeckle(im: Image.Image, min_neighbors: int = 2) -> Image.Image:
    """去掉孤立噪点（透明洞/孤点），alpha 二值化到 0/255。"""
    W, H = im.size
    px = im.load()
    opaque = [[px[x, y][3] > 128 for x in range(W)] for y in range(H)]
    out = im.copy()
    op = out.load()
    for y in range(H):
        for x in range(W):
            if not opaque[y][x]:
                continue
            n = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and opaque[ny][nx]:
                    n += 1
            if n < min_neighbors:
                op[x, y] = (0, 0, 0, 0)
            else:
                op[x, y] = (px[x, y][0], px[x, y][1], px[x, y][2], 255)
    return out


def remove_magenta_floor(im: Image.Image) -> Image.Image:
    """去掉角色脚下的品红/紫地面阴影（源图残留、与靴子同块但颜色偏品红）。
    只在底部 10 行、且呈品红（R≈B 且 G 明显偏低）的像素上生效，
    不会误伤暗色靴子或上身紫色衣物。"""
    W, H = im.size
    px = im.load()
    for y in range(H):
        if y < H - 10:
            continue
        for x in range(W):
            r, g, b, a = px[x, y]
            if a > 128 and r > 55 and b > 55 and g < min(r, b) - 18:
                px[x, y] = (0, 0, 0, 0)
    return im


def fit_cell(body: Image.Image) -> Image.Image:
    """把抠好的角色缩放进 60x120：等比 contain，脚底对齐格底、水平居中。"""
    bw, bh = body.size
    if bw == 0 or bh == 0:
        return Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    scale = min(MAX_W / float(bw), MAX_H / float(bh))
    nw = max(1, int(round(bw * scale)))
    nh = max(1, int(round(bh * scale)))
    big = body.resize((nw, nh), Image.NEAREST)
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    ox = (CELL_W - nw) // 2
    oy = CELL_H - nh            # 脚底对齐格底
    cell.paste(big, (ox, oy), big)
    return cell


def build_cell_for(grid: Image.Image, rect) -> Image.Image:
    x0, y0, x1, y1 = rect
    ix0, iy0 = x0 + INSET, y0 + INSET
    ix1, iy1 = x1 - INSET, y1 - INSET
    crop = grid.crop((ix0, iy0, ix1, iy1))
    keyed = key_panel(crop)
    # 裁到角色包围盒
    bbox = keyed.getbbox()
    if bbox is None:
        return Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    body = keyed.crop(bbox)
    body = despeckle(body)
    body = remove_small_components(body, 45)
    body = remove_magenta_floor(body)
    return fit_cell(body)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    grid = Image.open(GRID).convert("RGB")

    cells = {}  # name -> (right_cell, left_cell)
    for name, rect in MAP.items():
        right = build_cell_for(grid, rect)
        left = right.transpose(Image.FLIP_LEFT_RIGHT)
        cells[name] = (right, left)
        print("[%s] 右格尺寸 %s" % (name, right.size))

    if args.dry_run:
        for name, (right, left) in cells.items():
            right.save(os.path.join(ROOT, "tests", "gridsit_%s_right.png" % name))
            left.save(os.path.join(ROOT, "tests", "gridsit_%s_left.png" % name))
        # 合成预览：把右/左格贴进各顾客图集坐姿行，对比原图
        for name, (right, left) in cells.items():
            src = os.path.join(NPC_DIR, name + ".png")
            sheet = Image.open(src).convert("RGBA")
            s_px = sheet.load()
            for cx, cell in ((120, right), (60, left)):
                cpx = cell.load()
                for y in range(CELL_H):
                    for x in range(CELL_W):
                        r, g, b, a = cpx[x, y]
                        if a > 0:
                            s_px[cx + x, SIT_ROW_Y + y] = (r, g, b, 255)
            sheet.save(os.path.join(ROOT, "tests", "gridsit_preview_%s.png" % name))
        print("[dry] 预览 -> tests/gridsit_*_right.png / _left.png / gridsit_preview_*.png")
        return

    for name, (right, left) in cells.items():
        src = os.path.join(NPC_DIR, name + ".png")
        if not os.path.exists(src):
            print("跳过（不存在）:", src)
            continue
        sheet = Image.open(src).convert("RGBA")
        w, h = sheet.size
        assert (w, h) == (240, 600), "预期 240x600，实际 %s (%s)" % ((w, h), name)
        s_px = sheet.load()
        for cx, cell in ((120, right), (60, left)):   # col2=右, col1=左
            cpx = cell.load()
            for y in range(CELL_H):
                for x in range(CELL_W):
                    r, g, b, a = cpx[x, y]
                    if a > 0:
                        s_px[cx + x, SIT_ROW_Y + y] = (r, g, b, 255)
        bak = src + ".grid.bak"
        if not os.path.exists(bak):
            Image.open(src).convert("RGBA").save(bak, "PNG")
        sheet.save(src)
        print("已写回 ->", os.path.relpath(src, ROOT))


if __name__ == "__main__":
    main()
