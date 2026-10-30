#!/usr/bin/env python3
"""村庄碰撞/遮挡校准叠加图：底图 + 绿墙(sprite范围) + 红框(碰撞) + 50px 网格。

「碰撞箱图必须保留原图底图」的村庄版。数据直接读 cut_village_props.py 的
OBJECTS 单一来源，改完坐标重跑本脚本即可刷新校准图。

产物：tests/probe_shots/village_collision.png
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cut_village_props import OBJECTS, shapes_bbox  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/village/v1/scene_day_1x.png"
OUT = ROOT / "tests/probe_shots/village_collision.png"


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    d = ImageDraw.Draw(im, "RGBA")

    for e in OBJECTS:
        if "shapes" in e:
            box = shapes_bbox(e["shapes"])
            d.rectangle((box[0], box[1], box[0] + box[2] - 1, box[1] + box[3] - 1),
                        outline=(0, 230, 130, 255), width=1)
        c = e["collision"]
        d.rectangle((c[0], c[1], c[0] + c[2] - 1, c[1] + c[3] - 1),
                    outline=(255, 70, 70, 255), width=1)

    # 50px 网格（浅），200px 标签
    for x in range(0, im.width, 50):
        d.line([(x, 0), (x, im.height)], fill=(255, 255, 255, 60), width=1)
    for y in range(0, im.height, 50):
        d.line([(0, y), (im.width, y)], fill=(255, 255, 255, 60), width=1)
    for x in range(0, im.width, 100):
        d.text((x + 2, 2), str(x), fill=(255, 235, 120, 255))
    for y in range(0, im.height, 100):
        d.text((2, y + 2), str(y), fill=(255, 235, 120, 255))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT)
    print(f"校准图 -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
