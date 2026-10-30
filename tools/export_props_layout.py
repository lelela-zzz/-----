#!/usr/bin/env python3
"""按原布局整张导出遮挡件（人工精修用）。

掩膜在 cut_village_props 的结果上**外扩 2px**（MaxFilter）——宁可多留背景、
不切掉物体边缘，方便后期手修。产物：
  exports/village_props_layout_1x.png       透明底 866x866（真实像素网格，建议在 1x 上修）
  exports/village_props_layout_2x.png       透明底 1732x1732（看大图用）
  exports/village_props_layout_preview.png  深底+名字牌 2x（快速核对）

用法：python tools/export_props_layout.py
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cut_village_props import OBJECTS, SRC, build_mask  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "exports"
DILATE = 2  # 外扩像素（"大概轮廓"：宁可多不肯少）


def main() -> int:
    day = Image.open(SRC).convert("RGB")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGBA", day.size, (0, 0, 0, 0))
    n = 0
    for entry in OBJECTS:
        if "shapes" not in entry:
            continue
        cut, rect = build_mask(day, entry)
        alpha = cut.getchannel("A")
        for _ in range(DILATE):
            alpha = alpha.filter(ImageFilter.MaxFilter(3))
        cut.putalpha(alpha)
        canvas.alpha_composite(cut, (rect[0], rect[1]))
        n += 1

    p1 = OUT_DIR / "village_props_layout_1x.png"
    canvas.save(p1)

    big = canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST)
    p2 = OUT_DIR / "village_props_layout_2x.png"
    big.save(p2)

    # 深底 + 序号名牌预览（只用于快速核对，不是交付件）
    prev = Image.new("RGBA", canvas.size, (24, 26, 32, 255))
    prev.alpha_composite(canvas)
    d = ImageDraw.Draw(prev, "RGBA")
    marks: list[tuple[int, str, tuple[int, int, int, int]]] = []
    idx = 0
    for entry in OBJECTS:
        if "shapes" not in entry:
            continue
        idx += 1
        _, rect = build_mask(day, entry)
        marks.append((idx, entry["label"], rect))
        text = f"{idx:02d} {entry['label']}"
        tw = d.textlength(text)
        x0, y0 = rect[0], max(0, rect[1] - 11)
        d.rectangle((x0, y0, x0 + tw + 3, y0 + 11), fill=(0, 0, 0, 170))
        d.text((x0 + 1, y0 + 1), text, fill=(255, 235, 120, 255))
    pp = OUT_DIR / "village_props_layout_preview.png"
    prev.resize((prev.width * 2, prev.height * 2), Image.NEAREST).save(pp)

    # 原图 + 序号标注（对照参考图：底图不被裁，序号即交付件的编号）
    ref = day.convert("RGBA")
    rd = ImageDraw.Draw(ref, "RGBA")
    for idx, label, rect in marks:
        bx, by = rect[0], max(0, rect[1] - 2)
        txt = f"{idx:02d}"
        rd.rectangle((bx, by, bx + 20, by + 13), fill=(178, 34, 34, 230),
                     outline=(255, 235, 120, 255))
        rd.text((bx + 3, by + 2), txt, fill=(255, 245, 200, 255))
        rd.text((bx + 22, by + 2), label, fill=(255, 235, 120, 255),
                stroke_width=2, stroke_fill=(0, 0, 0, 200))
    pf = OUT_DIR / "village_props_numbered_2x.png"
    ref.resize((ref.width * 2, ref.height * 2), Image.NEAREST).save(pf)

    print(f"导出 {n} 件（外扩 {DILATE}px）:")
    for p in (p1, p2, pp, pf):
        print("  ", p)
    print("序号对照：")
    for idx, label, rect in marks:
        print(f"  {idx:02d}  {label:8s} rect={list(rect)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
