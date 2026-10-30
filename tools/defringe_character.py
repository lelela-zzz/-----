#!/usr/bin/env python3
"""角色白边（浅色残留带）去除工具。

背景：walk_v5.png 是从"浅底 + 柔和边缘"的立绘二值抠出来的，深色衣物（马甲/裙边）
外沿残留 2~4px 的浅色带，在深背景上像"白边"。alpha 已是二值（0/255），不是半透明渗色。

做法（不改变剪影 alpha，只改边缘 RGB）：
  1. BFS 求每个不透明像素到透明区的距离 dist。
  2. 对外沿 dist<=MAX_D 的像素，沿"向内"方向（dist 递减的反向，即取 dist 更大的邻居）
     走到深色本体锚点。
  3. 若该像素比锚点亮超过 TH：dist<=2 整格回填本体色，3..MAX_D 柔和混合。
  4. 透明像素 RGB 归 0（防任何过滤把白色渗到边缘）。
银发/皮肤的浅色边不会被误伤（它们向内也亮，亮度差 < TH）。

用法：python tools/defringe_character.py
会先备份原图到 _archive/walk_v5_backup_YYYYMMDD.png（已存在则跳过）。
"""
from __future__ import annotations

import datetime
import os
import shutil
from collections import deque

import numpy as np
from PIL import Image

SRC = "assets/hero/walk_v5.png"
BAK_DIR = "_archive"
TH = 16.0        # 比锚点亮多少才判定为白边
MAX_D = 4        # 处理外沿层数（像素）
WALK = 7         # 向内走的最大步数
OUTER_FULL = 2   # dist<=此值整格回填，否则柔和混合


def main() -> int:
    os.makedirs(BAK_DIR, exist_ok=True)
    bak = os.path.join(BAK_DIR, f"walk_v5_backup_{datetime.date.today():%Y%m%d}.png")
    if not os.path.exists(bak):
        shutil.copy2(SRC, bak)
        print("备份 ->", bak)
    else:
        print("备份已存在:", bak)

    arr = np.array(Image.open(bak).convert("RGBA"))  # 始终从原始备份重做
    rgb = arr[:, :, :3].astype(np.float32)
    al = arr[:, :, 3]
    h, w = al.shape
    op = al == 255
    tr = al == 0
    lum = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]

    dist = np.full((h, w), 9999, np.int32)
    dq: deque = deque()
    for y, x in zip(*np.where(tr)):
        dist[y, x] = 0
        dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and dist[ny, nx] > dist[y, x] + 1:
                    dist[ny, nx] = dist[y, x] + 1
                    dq.append((ny, nx))

    out = rgb.copy()
    changed = 0
    for y, x in sorted(zip(*np.where(op)), key=lambda t: dist[t[0], t[1]]):
        if dist[y, x] > MAX_D:
            continue
        cur = (y, x)
        for _ in range(WALK):
            cy, cx = cur
            bestd = dist[cy, cx]
            best = None
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dy == 0 and dx == 0:
                        continue
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and op[ny, nx] and dist[ny, nx] > bestd:
                        bestd = dist[ny, nx]
                        best = (ny, nx)
            if best is None:
                break
            cur = best
        ay, ax = cur
        if lum[ay, ax] < lum[y, x] - TH:
            blend = 1.0 if dist[y, x] <= OUTER_FULL else 0.8
            out[y, x] = (1 - blend) * rgb[y, x] + blend * rgb[ay, ax]
            changed += 1

    final = np.dstack([np.clip(out, 0, 255).astype(np.uint8), al])
    final[al == 0] = [0, 0, 0, 0]
    Image.fromarray(final, "RGBA").save(SRC)
    print(f"回填 {changed} 像素，已写回 {SRC}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
