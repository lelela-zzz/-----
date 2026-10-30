#!/usr/bin/env python3
"""用白天拆件的 alpha，从三张烘焙光照帧里再抠出同位置的家具。

为什么需要：
  背景会用 黎明/白天/黄昏/夜晚 四帧交叉淡入，而家具是从**白天帧**拆的。
  如果家具只有白天色，夜里就是一块"亮着的贴纸"浮在暗房间里。
  这里把同一套 alpha 套到另外三帧上 —— 家具在每一帧里都和它脚下那块背景
  像素完全一致，换帧时无缝。

用法：python tools/derive_prop_phases.py
产物：assets/house/v4/objects/prop_NN_<slug>_{dawn,dusk,night}.png（1x）
"""
from __future__ import annotations

import json

from PIL import Image

OUT = "assets/house/v4/objects"
FRAMES = {
    "dawn": "assets/house/v4/scene_dawn_v15_1x.png",
    "dusk": "assets/house/v4/scene_dusk_v15_1x.png",
    "night": "assets/house/v4/scene_night_v15_1x.png",
}


def main() -> int:
    with open(f"{OUT}/props.json", encoding="utf-8") as f:
        data = json.load(f)

    frames = {k: Image.open(v).convert("RGB") for k, v in FRAMES.items()}
    count = 0
    for e in data["props"]:
        if not e.get("has_sprite", True):
            continue
        day = Image.open(f"{OUT}/{e['name']}.png").convert("RGBA")
        alpha = day.getchannel("A")
        for phase, frame in frames.items():
            color = frame.crop((e["sprite_rect"][0], e["sprite_rect"][1],
                                e["sprite_rect"][0] + day.width,
                                e["sprite_rect"][1] + day.height)).convert("RGBA")
            color.putalpha(alpha)
            color.save(f"{OUT}/{e['name']}_{phase}.png")
            count += 1
    print(f"派生 {count} 张（{count // len(frames)} 件 × {len(frames)} 个时段）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
