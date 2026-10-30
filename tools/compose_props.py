#!/usr/bin/env python3
"""把拆好的家具按原有布局合成一张总图（不重新抠图）。

和 export_props_v15.py 的分工：
  · export_props_v15.py 负责"拆"，会覆盖 objects/*.png
  · 本脚本只负责"合"，读现有 PNG → 合成，随时可跑，不会动任何素材
所以手改完之后再跑一次，就能看到整体效果。

产物（assets/house/v4/objects/）：
  _layout_checker_2x.png   棋盘底总图（2×，用来肉眼检查透明区）
  _layout_alpha_1x.png     透明底总图（1×，可直接当一层用）
  _layout_alpha_2x.png     透明底总图（2×）
用法：python tools/compose_props.py
"""
from __future__ import annotations

import json

from PIL import Image, ImageDraw

OUT = "assets/house/v4/objects"
W, H = 640, 384
CHECK = 8          # 棋盘格边长（1x 像素）


def main() -> int:
    with open(f"{OUT}/props.json", encoding="utf-8") as f:
        data = json.load(f)

    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    composed: int = 0
    for e in data["props"]:
        if not e.get("has_sprite", True):
            continue
        composed += 1
        x, y, w, h = e["sprite_rect"]
        part = Image.open(f"{OUT}/{e['name']}.png").convert("RGBA")
        if part.size != (w, h):
            print(f"  !! {e['name']} 尺寸 {part.size} 与 props.json 的 {w}x{h} 不一致，按图片实际尺寸贴")
        layer.alpha_composite(part, (x, y))
    layer.save(f"{OUT}/_layout_alpha_1x.png")
    layer.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/_layout_alpha_2x.png")

    board = Image.new("RGB", (W, H), (205, 205, 205))
    d = ImageDraw.Draw(board)
    for yy in range(0, H, CHECK):
        for xx in range(0, W, CHECK):
            if ((xx // CHECK) + (yy // CHECK)) % 2 == 0:
                d.rectangle([xx, yy, xx + CHECK - 1, yy + CHECK - 1], fill=(160, 160, 160))
    board = board.convert("RGBA")
    board.alpha_composite(layer)
    board.convert("RGB").resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/_layout_checker_2x.png")

    total = sum(1 for p in layer.getdata() if p[3])
    print(f"合成 {composed} 件，不透明像素 {total} / {W * H}（{total / (W * H):.1%}）")
    print(f"  → {OUT}/_layout_checker_2x.png")
    print(f"  → {OUT}/_layout_alpha_1x.png / _2x.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
