#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 .seat.bak 还原后用 v3 精准去座椅残留，写回 col1/col2（不动 col0/col3）。
v3：从透明边缘洪水，只吞「低饱和 + 中亮度」灰/暖灰像素（seats/阴影），
碰到高饱和衣物 / 纯白大衣 / 深描边就停。"""
from collections import deque
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]
SIT_ROW_Y = 480


def removable(c):
    r, g, b, a = c
    if a < 128:
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    br = (r + g + b) / 3.0
    return (mx - mn) < 32 and 110 < br < 222


def clean_cell(cell):
    W, H = cell.size
    px = cell.load()
    seen = [[False] * W for _ in range(H)]
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if not seen[y][x]:
                seen[y][x] = True
                q.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            if not seen[y][x]:
                seen[y][x] = True
                q.append((x, y))
    out = cell.copy()
    op = out.load()
    while q:
        x, y = q.popleft()
        c = px[x, y]
        if c[3] >= 128 and removable(c) and y >= 50:
            op[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx]:
                nc = px[nx, ny]
                if nc[3] < 128 or removable(nc):
                    seen[ny][nx] = True
                    q.append((nx, ny))
    return out


def main():
    for name in NAMES:
        base = os.path.join(NPC, name + ".png")
        bak = base + ".seat.bak"
        src = bak if os.path.exists(bak) else base
        sheet = Image.open(src).convert("RGBA")
        W, H = sheet.size
        assert (W, H) == (240, 600), "%s %s" % (name, (W, H))
        px = sheet.load()
        total = 0
        for col in (1, 2):
            cell = sheet.crop((col * 60, SIT_ROW_Y, col * 60 + 60, SIT_ROW_Y + 120))
            cell = clean_cell(cell)
            cpx = cell.load()
            for y in range(120):
                for x in range(60):
                    r, g, b, a = cpx[x, y]
                    px[col * 60 + x, SIT_ROW_Y + y] = (r, g, b, a)
                    if a == 0:
                        total += 1
        sheet.save(base)
        print("v3 cleaned ->", os.path.relpath(base, ROOT), "transparent px:", total)


if __name__ == "__main__":
    main()
