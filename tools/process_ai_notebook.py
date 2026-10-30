#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""处理 AI 像素手册原图（纯洋红底）-> 64x64 游戏图标。

背景是洋红系（角部 (225,82,229) 到主体 (255,14,255) 都有），按「R 高 / G 低 / B 高」
判定洋红 -> 透明；书的棕/米白/金都不满足该条件，不会误伤。
流程：chroma key -> 只留最大连通域（去水印残块）-> 裁包围盒 -> 等比缩 58 ->
居中 64x64（NEAREST）-> 补 1px 暗描边。

输入：tests/keep_the_pixel_art_quest_journ_2026-10-24T13-59-06.png
输出：assets/items/icons/quest_notebook.png
"""
from __future__ import annotations

import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tests", "keep_the_pixel_art_quest_journ_2026-10-24T13-59-06.png")
OUT = os.path.join(ROOT, "assets", "items", "icons", "quest_notebook.png")
OUTL = (40, 26, 18)


def is_magenta(c):
    return c[3] > 0 and c[0] > 170 and c[1] < 130 and c[2] > 170


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    W, H = im.size
    px = im.load()

    # 1) chroma key 洋红 -> 透明
    for y in range(H):
        for x in range(W):
            if is_magenta(px[x, y]):
                px[x, y] = (0, 0, 0, 0)

    # 2) 只留最大连通域（书），去掉水印文字等残块
    label = [[0] * W for _ in range(H)]
    comp = 0; sizes = {}
    for y0 in range(H):
        for x0 in range(W):
            if px[x0, y0][3] > 0 and label[y0][x0] == 0:
                comp += 1
                q = deque([(x0, y0)]); label[y0][x0] = comp; n = 0
                while q:
                    x, y = q.popleft(); n += 1
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < W and 0 <= ny < H and px[nx, ny][3] > 0 and label[ny][nx] == 0:
                            label[ny][nx] = comp; q.append((nx, ny))
                sizes[comp] = n
    keep = max(sizes, key=lambda k: sizes[k])
    for y in range(H):
        for x in range(W):
            if px[x, y][3] > 0 and label[y][x] != keep:
                px[x, y] = (0, 0, 0, 0)

    # 3) 包围盒 -> 裁 -> 等比缩到最长边 58 -> 居中 64x64
    xs = [x for x in range(W) for y in range(H) if px[x, y][3] > 0]
    ys = [y for y in range(H) for x in range(W) if px[x, y][3] > 0]
    book = im.crop((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    bw, bh = book.size
    s = 58.0 / max(bw, bh)
    nw, nh = max(1, int(round(bw * s))), max(1, int(round(bh * s)))
    book = book.resize((nw, nh), Image.NEAREST)
    canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    canvas.alpha_composite(book, ((64 - nw) // 2, (64 - nh) // 2))

    # 4) 补 1px 暗描边
    cp = canvas.load()
    edge = []
    for y in range(64):
        for x in range(64):
            if cp[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 64 and 0 <= ny < 64 and cp[nx, ny][3] > 0:
                        edge.append((x, y)); break
    for (x, y) in edge:
        cp[x, y] = (OUTL[0], OUTL[1], OUTL[2], 255)

    canvas.save(OUT)
    print("saved", os.path.relpath(OUT, ROOT), canvas.size)


if __name__ == "__main__":
    main()
