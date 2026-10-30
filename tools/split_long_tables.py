#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 4 张长桌贴图按 [左凳|桌面|右凳] 三列组拆成「凳层」和「桌面层」两套，
供 props.json 分成两个 prop 用（凳层 sort_y 在角色脚底之下、桌面层在其之上），
实现"角色坐凳上、桌面挡重叠"。

每张桌对 4 个时段（base/_dawn/_dusk/_night）各切一份，输出：
  <name>_bench<phase>.png  只留左右两条凳（两组外侧列）
  <name>_top<phase>.png    只留中间桌面（一组中列）
_2x 参考图不切（prop_layer 不加载它）。

用法：python tools/split_long_tables.py
"""
from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OBJ = os.path.join(ROOT, "assets", "house", "v4", "objects")
PHASES = ["", "_dawn", "_dusk", "_night"]  # 与 prop_layer.PHASE_SUFFIX 对齐
TABLES = ["prop_09_long_table_1", "prop_10_long_table_2",
          "prop_11_long_table_3", "prop_12_long_table_4"]


def col_groups(px, W, H):
    cols = [x for x in range(W) if any(px[x, y][3] > 128 for y in range(H))]
    groups = []
    s = p = cols[0]
    for x in cols[1:]:
        if x == p + 1:
            p = x
        else:
            groups.append((s, p)); s = p = x
    groups.append((s, p))
    return groups  # 期望 3 组：左凳 / 桌面 / 右凳


def zero_cols(img, ranges):
    px = img.load(); W, H = img.size
    for (a, b) in ranges:
        for x in range(max(0, a), min(W, b + 1)):
            for y in range(H):
                px[x, y] = (0, 0, 0, 0)


def main() -> None:
    for name in TABLES:
        base = Image.open(os.path.join(OBJ, name + ".png")).convert("RGBA")
        g = col_groups(base.load(), base.size[0], base.size[1])
        assert len(g) == 3, "%s 期望 3 个列组(左凳/桌面/右凳)，实际 %s" % (name, g)
        bench_ranges = [g[0], g[2]]   # 外侧两组=凳
        top_range = [g[1]]            # 中间=桌面
        for ph in PHASES:
            src = os.path.join(OBJ, name + ph + ".png")
            if not os.path.exists(src):
                print("缺时段贴图，跳过:", os.path.basename(src)); continue
            im = Image.open(src).convert("RGBA")
            bench = im.copy(); zero_cols(bench, top_range)      # 凳层：抹掉桌面
            top = im.copy(); zero_cols(top, bench_ranges)        # 桌面层：抹掉凳
            bench.save(os.path.join(OBJ, name + "_bench" + ph + ".png"))
            top.save(os.path.join(OBJ, name + "_top" + ph + ".png"))
        print(name, "-> bench+top 已切（列组 %s）" % g)
    print("完成：4 桌 x 2 层 x 4 时段。")


if __name__ == "__main__":
    main()
