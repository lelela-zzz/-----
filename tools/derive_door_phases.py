#!/usr/bin/env python3
"""从四张烘焙光照帧里抠出"下方入口门"作为前景 sprite。

为什么单独做：
  门是烤在背景里的，没有单独的白天拆件 PNG。这里直接按 props.json 里
  door_foreground 的 sprite_rect，从 黎明/白天/黄昏/夜晚 四帧同位置抠出，
  存成 PropLayer 能直接吃的命名（day 无后缀、其余带 _dawn/_dusk/_night）。
  门作为前景 sprite 放进 Sorted，跟随昼夜换帧，并叠加半透明实现"虚化"。

用法：python tools/derive_door_phases.py
产物：assets/house/v4/objects/door_foreground{_dawn,_dusk,_night}.png（1x）
"""
from __future__ import annotations

import json

from PIL import Image

OUT = "assets/house/v4/objects"
# key 必须和 PropLayer.PHASE_SUFFIX = ["_dawn","","_dusk","_night"] 对齐
FRAMES = {
    "_dawn": "assets/house/v4/scene_dawn_v15_1x.png",
    "": "assets/house/v4/scene_day_v15_1x.png",
    "_dusk": "assets/house/v4/scene_dusk_v15_1x.png",
    "_night": "assets/house/v4/scene_night_v15_1x.png",
}


def main() -> int:
    with open(f"{OUT}/props.json", encoding="utf-8") as f:
        data = json.load(f)
    door = next((e for e in data["props"] if e["name"] == "door_foreground"), None)
    if door is None:
        raise SystemExit("props.json 里找不到 door_foreground")
    x, y, w, h = door["sprite_rect"]
    count = 0
    for suffix, path in FRAMES.items():
        src = Image.open(path).convert("RGBA")
        crop = src.crop((x, y, x + w, y + h))
        out = f"{OUT}/door_foreground{suffix}.png"
        crop.save(out)
        count += 1
        print(f"  {out}  ({crop.size[0]}x{crop.size[1]})")
    print(f"派生 {count} 张门前景 sprite")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
