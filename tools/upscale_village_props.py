#!/usr/bin/env python3
"""把村庄道具（objects/*.png）重做成 2× 版本，细节从 2× 底图里取。

为什么这么做，而不是重跑 cut_village_props.py：
  · OBJECTS 表里的坐标、掩膜算法、碰撞框全是为 866 基准写的，重跑一遍容易
    把抠图边界和碰撞数据一起改歪；
  · 这里只做**像素来源升级**：alpha 掩膜照抄现有 1× 图（放大 2× 保持硬边），
    颜色从对应的 2× 底图同区域取 → 位置、大小、边缘形状一字不变，
    唯一的差别是贴图从 866 级细节变成 1732 级细节。

用法：
  python tools/upscale_village_props.py            # 全部时段
  python tools/upscale_village_props.py day        # 只做白天
产物：assets/village/v1/objects2x/{name}{suffix}.png（1732 底图尺度）
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "assets/village/v1"
OUT = SRC_DIR / "objects2x"
PROPS = SRC_DIR / "objects/props.json"

# 时段后缀 → 2× 底图
FRAMES = {
    "": SRC_DIR / "scene_day_2x.png",
    "_dawn": SRC_DIR / "scene_dawn_2x.png",
    "_dusk": SRC_DIR / "scene_dusk_2x.png",
    "_night": SRC_DIR / "scene_night_2x.png",
}


def main() -> int:
    only = sys.argv[1] if len(sys.argv) > 1 else None
    data = json.loads(PROPS.read_text(encoding="utf-8"))
    sufs = [""] if only == "day" else list(FRAMES)
    if only and only != "day":
        sufs = ["_" + only]

    OUT.mkdir(parents=True, exist_ok=True)
    frames = {s: Image.open(p).convert("RGB") for s, p in FRAMES.items() if s in sufs}

    done = 0
    skipped = 0
    for item in data["props"]:
        if not item.get("has_sprite", True):
            skipped += 1
            continue
        name = item["name"]
        rect = item["sprite_rect"]
        x, y, w, h = (int(v) for v in rect)
        base_path = SRC_DIR / "objects" / (name + ".png")
        if not base_path.exists():
            print("缺 1x 图:", base_path.name)
            skipped += 1
            continue
        mask = Image.open(base_path).convert("RGBA")

        for suf in sufs:
            src = frames[suf]
            box = (x * 2, y * 2, (x + w) * 2, (y + h) * 2)
            patch = src.crop(box).convert("RGB")
            # 1× 图的 alpha → 2× 掩膜（NEAREST 放大，边缘保持硬像素）
            alpha = mask.split()[3].resize((patch.width, patch.height), Image.NEAREST)
            out = patch.convert("RGBA")
            out.putalpha(alpha)
            out.save(OUT / (name + suf + ".png"))
            done += 1

    print(f"产出 {done} 张 2x 道具 → {OUT}（跳过 {skipped}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
