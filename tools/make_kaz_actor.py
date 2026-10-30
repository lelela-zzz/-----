#!/usr/bin/env python3
"""卡兹图集：以「巫妖_维兹」为骨架做**定向换色**（不重画、不改轮廓）。

为什么这么做：卡兹（第三章反派·古代生物）的正式立绘还没到，但剧情要人。
维兹的体态（长裙、长发、纤瘦）与「近乎女相的优雅」对得上，换色后
- 棕发 → 近黑长发
- 浅紫裙摆 → 苍白肤色（读作裸露的肢体）
- 深蓝布片 → 炭黑布料
就能读成「肌肤苍白、赤着上身、深色长发的上古生物」。

⚠ 这是占位方案。拿到正式图后，直接同名覆盖
   assets/actors/npc/古代生物_卡兹.png 即可（尺寸 240×480、格子 60×120 不变）。

用法：python tools/make_kaz_actor.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/actors/npc/巫妖_维兹.png"
OUT = ROOT / "assets/actors/npc/古代生物_卡兹.png"


def _lum(c: tuple[int, int, int]) -> float:
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def _ramp(colors: list[tuple[int, int, int]], t: float) -> tuple[int, int, int]:
    """在一组由深到浅的目标色里按 t（0=最暗,1=最亮）线性插值。"""
    if t <= 0.0:
        return colors[0]
    if t >= 1.0:
        return colors[-1]
    pos = t * (len(colors) - 1)
    i = int(pos)
    f = pos - i
    a, b = colors[i], colors[i + 1]
    return (round(a[0] + (b[0] - a[0]) * f),
            round(a[1] + (b[1] - a[1]) * f),
            round(a[2] + (b[2] - a[2]) * f))


# 目标色阶（暗 → 亮）
HAIR = [(18, 16, 20), (34, 29, 35), (56, 48, 57), (78, 68, 78)]
SKIN = [(186, 172, 168), (206, 192, 186), (222, 210, 204), (238, 228, 222)]
CLOTH = [(26, 25, 30), (40, 38, 46), (56, 53, 62), (76, 72, 82)]


def main() -> int:
    im = Image.open(SRC).convert("RGBA")
    px = im.load()
    W, H = im.size
    changed = 0
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            c = (r, g, b)
            lo = _lum(c)
            if r > g + 12 and r > b + 18 and lo > 60:
                # 棕发族：暖、饱和 → 近黑长发
                px[x, y] = _ramp(HAIR, min(1.0, max(0.0, (lo - 55) / 130))) + (a,)
                changed += 1
            elif b >= r and b >= g and lo >= 120:
                # 浅紫裙摆（偏冷的亮色）→ 苍白肤色
                px[x, y] = _ramp(SKIN, min(1.0, max(0.0, (lo - 120) / 60))) + (a,)
                changed += 1
            elif b >= g and lo < 120:
                # 深蓝/深紫布料 → 炭黑
                px[x, y] = _ramp(CLOTH, min(1.0, max(0.0, lo / 110))) + (a,)
                changed += 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT)
    print(f"{SRC.name} -> {OUT.name}  {im.size}，改色像素 {changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
