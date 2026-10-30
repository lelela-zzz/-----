#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 props.json 里 4 张长桌各拆成「凳层 + 桌面层」两个 prop。

凳层：只画左右凳、sort_y 设在角色脚底之下(角色坐凳上)、no_collision。
桌面层：只画桌面、sort_y 设在角色脚底之上(桌挡重叠)、保留原碰撞框(可行走性不变)。

角色脚底 y：上排桌(1,2)=210、下排桌(3,4)=296。
故 sort_y：上排凳 200 / 桌 220；下排凳 286 / 桌 306（脚底落在两者之间）。

用法：python tools/split_props_json.py
"""
from __future__ import annotations

import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(ROOT, "assets", "house", "v4", "objects", "props.json")

# name -> (bench_sort_y, top_sort_y, label)
SPLIT = {
    "prop_09_long_table_1": (200, 220, "长桌 1"),
    "prop_10_long_table_2": (200, 220, "长桌 2"),
    "prop_11_long_table_3": (286, 306, "长桌 3"),
    "prop_12_long_table_4": (286, 306, "长桌 4"),
}


def main() -> None:
    shutil.copy(PROPS, PROPS + ".bak")
    with open(PROPS, "r", encoding="utf-8") as f:
        data = json.load(f)

    out = []
    for e in data["props"]:
        name = e.get("name", "")
        if name in SPLIT:
            bsort, tsort, label = SPLIT[name]
            rect = e["sprite_rect"]
            collision = e.get("collision_rect")
            # 凳层：无碰撞，排序在角色之后(数值更小=更靠后)
            bench = {
                "name": name + "_bench",
                "label": label + "·凳",
                "file": "res://assets/house/v4/objects/%s_bench.png" % name,
                "sprite_rect": rect,
                "sort_y": bsort,
                "wall": False,
                "no_collision": True,
                "has_sprite": True,
            }
            # 桌面层：保留原碰撞，排序在角色之前(数值更大=更靠前)
            top = {
                "name": name + "_top",
                "label": label + "·桌面",
                "file": "res://assets/house/v4/objects/%s_top.png" % name,
                "sprite_rect": rect,
                "sort_y": tsort,
                "wall": False,
                "collision_rect": collision,
                "has_sprite": True,
            }
            out.append(bench)
            out.append(top)
        else:
            out.append(e)
    data["props"] = out

    with open(PROPS, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("props.json 已拆分长桌为凳层+桌面层；备份 %s.bak" % os.path.basename(PROPS))


if __name__ == "__main__":
    main()
