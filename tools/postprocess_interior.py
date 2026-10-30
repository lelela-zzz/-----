#!/usr/bin/env python3
"""室内底图后处理：裁边 → 整数倍降采样 → 自动测壁炉/窗口坐标。

用法：
    python tools/postprocess_interior.py <raw.png> [--tag v5]

流程（对应《炉火镇-室内底图-提示词包-v2.md》§5 第 1–3 步）：
1. 若输入不是 1280×768：先用 BOX 降到 1280×768（整 2×），再做 NEAREST 2× → 640×384
   （直接对 1536×1024 做 2.4× 非整数 NEAREST 就是旧室内"杂色"的根因）
2. 去掉四边均匀画框（若存在）
3. 自动检测：火焰质心（壁炉）、窗口蓝色聚类
4. 输出 scene_day_<tag>_1x/2x.png 与 <tag>_coords.json（供 relight 换坐标）
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image

W, H = 640, 384
OUT = "assets/house/v4"


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def crop_frame(im):
    """裁掉四边近似纯色的画框（只在边缘 3% 内探测）。"""
    px = im.load()
    w, h = im.size
    edge = max(2, int(min(w, h) * 0.03))

    def row_uniform(y):
        vals = [px[x, y] for x in range(0, w, 7)]
        base = vals[0]
        return all(abs(c[0] - base[0]) + abs(c[1] - base[1]) + abs(c[2] - base[2]) < 26 for c in vals)

    def col_uniform(x):
        vals = [px[x, y] for y in range(0, h, 7)]
        base = vals[0]
        return all(abs(c[0] - base[0]) + abs(c[1] - base[1]) + abs(c[2] - base[2]) < 26 for c in vals)

    top = 0
    while top < edge and row_uniform(top):
        top += 1
    bot = h - 1
    while bot > h - edge and row_uniform(bot):
        bot -= 1
    left = 0
    while left < edge and col_uniform(left):
        left += 1
    right = w - 1
    while right > w - edge and col_uniform(right):
        right -= 1
    if (top, left, bot, right) != (0, 0, h - 1, w - 1):
        im = im.crop((left, top, right + 1, bot + 1))
        print(f"  裁掉画框 → {im.size}")
    return im


def detect(im):
    px = im.load()
    w, h = im.size

    # 火：只在**中间三分之一宽度**的炉膛带内找（壁炉居中），取最大簇质心
    x_lo, x_hi = int(w * 0.33), int(w * 0.67)
    # 火：在炉膛带内找"最橙"的点（r-b 最大）作锚，再取该点附近的候选中位数
    cand = [(x, y, px[x, y][0] - px[x, y][2]) for y in range(int(h * 0.14), int(h * 0.27))
            for x in range(x_lo, x_hi)
            if (lambda c: c[0] > 150 and c[0] - c[2] > 90 and c[0] - c[1] > 35)(px[x, y])]
    hearth = None
    if len(cand) >= 15:
        # 按列统计橙像素数量：火是成团的一小块，瓶子/烛光是零散 1–2px，列峰值能区分
        col = {}
        for (x, y, d) in cand:
            col[x] = col.get(x, 0) + 1
        peak = max(col, key=lambda k: (col[k], -abs(k - w // 2)))
        near = [(x, y) for (x, y, _d) in cand if abs(x - peak) <= 10]
        if len(near) >= 8:
            xs = sorted(p[0] for p in near)
            ys = sorted(p[1] for p in near)
            hearth = (xs[len(xs) // 2], ys[len(ys) // 2])

    # 窗：亮蓝聚类（只在上部 1/4）
    blue = sorted((x, y) for y in range(0, int(h * 0.28)) for x in range(w)
                  if (lambda c: c[2] > 95 and c[2] > c[0] + 18 and c[2] > c[1] + 8)(px[x, y]))
    groups, cur = [], []
    for p in blue:
        if cur and p[0] - cur[-1][0] <= 8:
            cur.append(p)
        else:
            if cur:
                groups.append(cur)
            cur = [p]
    if cur:
        groups.append(cur)
    windows = []
    for g in groups:
        if len(g) < 20:
            continue
        xs = [p[0] for p in g]
        ys = [p[1] for p in g]
        windows.append(dict(cx=(min(xs) + max(xs)) // 2, cy=(min(ys) + max(ys)) // 2,
                            box=[min(xs), min(ys), max(xs), max(ys)], n=len(g)))
    return hearth, windows


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    raw = sys.argv[1]
    tag = "v5"
    if "--tag" in sys.argv:
        tag = sys.argv[sys.argv.index("--tag") + 1]

    im = Image.open(raw).convert("RGB")
    print(f"输入 {raw} {im.size}")
    im = crop_frame(im)

    if im.size == (W * 2, H * 2):
        one = im.resize((W, H), Image.NEAREST)
        print("  输入正好 1280×768 → 直接 NEAREST 2× 降采样")
    else:
        mid = im.resize((W * 2, H * 2), Image.BOX)
        one = mid.resize((W, H), Image.NEAREST)
        print(f"  {im.size} → BOX 到 1280×768 → NEAREST 2×（避免非整数比取样）")

    one.save(f"{OUT}/scene_day_{tag}_1x.png")
    one.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/scene_day_{tag}_2x.png")

    hearth, windows = detect(one)
    coords = dict(hearth=hearth, windows=windows)
    with open(f"{OUT}/{tag}_coords.json", "w", encoding="utf-8") as f:
        json.dump(coords, f, ensure_ascii=False, indent=1)

    print(f"  火焰质心 {hearth}")
    print(f"  窗口 {len(windows)} 个：{[(w['cx'], w['cy']) for w in windows]}")
    print(f"→ scene_day_{tag}_1x.png / _2x.png / {tag}_coords.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
