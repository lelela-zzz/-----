#!/usr/bin/env python3
"""酒馆外观底图（从酒馆内部正门出来的场景）。

剪贴板源图 1645x1645 JPEG → 0.4x BOX 降采样 → 658x658。
0.4 是按「门宽对齐玩家尺度」定的：源图门洞宽 ~115px，0.4x 后 ~46px，
与室内门洞（door_gap_x 46px）和村庄酒馆门（触发框 40px）同一尺度；
1645 * 0.4 = 658 恰为整数，地图宽出 640 视口，PixelCamera 可纵向卷动。

用法：python tools/make_tavern_ext_maps.py
产出：assets/tavern_exterior/v1/scene_day_1x.png (+ scene_day_src.png 存档源图)
之后跑：python tools/relight_tavern_ext.py
"""
from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

CLIPBOARD = Path(r"C:\Users\了了啦\.workbuddy\clipboard-images"
                 r"\clipboard-2026-10-22T14-15-54-270Z-93306769.jpg")
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/tavern_exterior/v1"
SCALE = 0.4


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(CLIPBOARD).convert("RGB")
    w, h = src.size
    tw, th = round(w * SCALE), round(h * SCALE)
    day = src.resize((tw, th), Image.BOX)
    day.save(OUT / "scene_day_1x.png")
    shutil.copyfile(CLIPBOARD, OUT / "scene_day_src.png")
    print(f"源图 {w}x{h} -> {tw}x{th} -> {OUT/'scene_day_1x.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
