#!/usr/bin/env python3
"""以**用户给的整张布局图**为唯一像素来源，重新切出家具。

和 export_props_v15.py 的区别：
  · export_props_v15.py 是从底图自己抠（算法猜的边界，来回改过好几轮）
  · 本脚本直接用用户修好的那张图，只做两件事：
      ① 白底 → 透明（家具上没有任何纯白，白就是空地）
      ② 按 props.json 里已经标定好的 sprite_rect 切块
所以像素完全等于用户给的图，不再经过任何自动判断。

白底判定：亮度 > 235 且近似中性（max-min < 12）→ 透明。
  木色/描边都偏暖，不会误伤；JPEG 压缩在边缘留下的灰白毛边会落进"中性亮"里，一起被清掉。

某一块如果几乎没有不透明像素（用户在图上删掉了它）→ 标 has_sprite = false，
  只保留 collision_rect（比如右侧背柜和楼梯，它们属于建筑，不进排序）。

用法：python tools/import_user_layout.py
"""
from __future__ import annotations

import json
import shutil

from PIL import Image

SRC = "assets/house/v4/objects/_user_layout_2x.png"
OUT = "assets/house/v4/objects"
W, H = 640, 384
WHITE_LUM = 235
NEUTRAL = 12


def is_whitish(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    return lum > WHITE_LUM and (max(c) - min(c)) < NEUTRAL


def main() -> int:
    sheet = Image.open(SRC).convert("RGB")
    if sheet.size != (W * 2, H * 2):
        print(f"!! 期望 {W * 2}x{H * 2}，实际 {sheet.size}，先缩放到 2x")
        sheet = sheet.resize((W * 2, H * 2), Image.NEAREST)

    with open(f"{OUT}/props.json", encoding="utf-8") as f:
        data = json.load(f)

    shutil.copy(f"{OUT}/props.json", f"{OUT}/props_prev.json")
    kept = 0
    dropped: list[str] = []
    for e in data["props"]:
        x, y, w, h = e["sprite_rect"]
        crop2 = sheet.crop((x * 2, y * 2, (x + w) * 2, (y + h) * 2))
        one = crop2.resize((w, h), Image.NEAREST).convert("RGBA")
        src = one.load()
        opaque = 0
        for yy in range(h):
            for xx in range(w):
                r, g, b, _a = src[xx, yy]
                if is_whitish((r, g, b)):
                    src[xx, yy] = (r, g, b, 0)
                else:
                    src[xx, yy] = (r, g, b, 255)
                    opaque += 1
        ratio = opaque / float(w * h)
        if ratio < 0.05:
            e["has_sprite"] = False
            dropped.append(e["name"])
            continue
        e["has_sprite"] = True
        e["coverage"] = round(ratio, 3)
        one.save(f"{OUT}/{e['name']}.png")
        one.resize((w * 2, h * 2), Image.NEAREST).save(f"{OUT}/{e['name']}_2x.png")
        kept += 1
        print(f"  {e['name']:26s} {w:3d}x{h:3d} @({x},{y})  不透明 {ratio:5.1%}")

    with open(f"{OUT}/props.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"有精灵 {kept} 件；只保留碰撞、不出精灵：{', '.join(dropped) if dropped else '无'}")
    print("下一步：python tools/derive_prop_phases.py   （按新 alpha 重出四个时段贴图）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
