#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""精准去「座椅/阴影残留」：从透明边缘洪水，只吞「低饱和 + 中亮度」的灰/暖灰像素
（座椅垫/背景阴影），碰到高饱和衣物、纯白大衣、深描边就停。预览 4 客户 col1/col2。"""
from collections import deque
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]


def removable(c):
    r, g, b, a = c
    if a < 128:
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    br = (r + g + b) / 3.0
    return (mx - mn) < 32 and 110 < br < 222


def clean(cell):
    W, H = cell.size
    px = cell.load()
    # BFS 从透明边界进入 removable 像素
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
                # 只有透明像素或 removable 像素才继续扩散
                if nc[3] < 128 or removable(nc):
                    seen[ny][nx] = True
                    q.append((nx, ny))
    return out


S = 4
cw, ch = 60 * S, 120 * S
pad = 12
lab = 22
W = pad + (cw + pad) * 2
H = pad + (ch + lab + pad) * len(NAMES)
canvas = Image.new("RGB", (W, H), (255, 0, 255))  # 品红底：透明=品红
d = ImageDraw.Draw(canvas)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 15)
except Exception:
    font = ImageFont.load_default()
for r, name in enumerate(NAMES):
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    y0 = pad + r * (ch + lab + pad)
    d.text((pad, y0), name, font=font, fill=(0, 0, 0))
    for k, col in enumerate((1, 2)):
        cell = sheet.crop((col * 60, 480, col * 60 + 60, 600))
        cell = clean(cell)
        big = cell.resize((cw, ch), Image.NEAREST)
        x0 = pad + k * (cw + pad)
        canvas.paste(big, (x0, y0 + lab), big)
        d.text((x0 + 2, y0 + lab + ch + 1), "col%d" % col, font=font, fill=(0, 0, 0))
canvas.save(os.path.join(ROOT, "tests", "clean_v3_preview.png"))
print("saved", canvas.size)
