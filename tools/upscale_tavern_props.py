#!/usr/bin/env python3
"""酒馆家具的 2× 重制：alpha 掩膜照抄现有 1× 图，颜色从 v16 的 2× 底图取。

和 upscale_village_props.py 同一套思路（只换像素来源，不动 sprite_rect /
sort_y / 碰撞框），区别只是基准是 640×384、底图是 1280×768。

用法：
  python tools/upscale_tavern_props.py          # 四个时段全做
  python tools/upscale_tavern_props.py day      # 只做白天
产物：assets/house/v4/objects2x/{name}{suffix}.png
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "assets/house/v4"
OUT = SRC_DIR / "objects2x"
PROPS = SRC_DIR / "objects/props.json"

FRAMES = {
    "": SRC_DIR / "scene_day_v16_2x.png",
    "_dawn": SRC_DIR / "scene_dawn_v16_2x.png",
    "_dusk": SRC_DIR / "scene_dusk_v16_2x.png",
    "_night": SRC_DIR / "scene_night_v16_2x.png",
}


def main() -> int:
    only = sys.argv[1] if len(sys.argv) > 1 else None
    data = json.loads(PROPS.read_text(encoding="utf-8"))
    if only == "day":
        sufs = [""]
    elif only:
        sufs = ["_" + only]
    else:
        sufs = list(FRAMES)

    OUT.mkdir(parents=True, exist_ok=True)
    frames = {s: Image.open(p).convert("RGB") for s, p in FRAMES.items() if s in sufs}

    done = 0
    skipped = 0
    for item in data["props"]:
        if not item.get("has_sprite", True):
            skipped += 1
            continue
        name = item["name"]
        x, y, w, h = (int(v) for v in item["sprite_rect"])
        base_path = SRC_DIR / "objects" / (name + ".png")
        if not base_path.exists():
            print("缺 1x 图:", base_path.name)
            skipped += 1
            continue
        mask = Image.open(base_path).convert("RGBA")

        for suf in sufs:
            box = (x * 2, y * 2, (x + w) * 2, (y + h) * 2)
            patch = frames[suf].crop(box).convert("RGB")
            alpha = mask.split()[3].resize((patch.width, patch.height), Image.NEAREST)
            out = patch.convert("RGBA")
            out.putalpha(alpha)
            out.save(OUT / (name + suf + ".png"))
            done += 1

    print(f"产出 {done} 张 2x 家具 → {OUT}（跳过 {skipped}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
