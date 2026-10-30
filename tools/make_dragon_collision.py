#!/usr/bin/env python3
"""龙巢碰撞：按底图实测生成 props.json（只做碰撞，不含精灵）。

判定方式（与雪山/矿道同一套口径，**不做骨架化**）：
1. 地面判据：亮度 >= 24 的像素算「洞窟内地面」。洞外是近乎纯黑（lum 17 左右），
   地面是暗棕灰（lum 30~42），阈值落在中间。
2. 32px 网格，格内 60% 像素达标才算可走格（避免把岩壁锯齿算进来）。
3. 不可走格 → 合并成矩形碰撞（逐行取连续段，再纵向合并同宽同列的段）。
4. 手写两块「装饰即障碍」：中央盘龙（连巨石，矩形 336×444）、左侧骸骨堆。

产物：assets/dragon_lair/v1/objects/props.json
  {"source": ".../scene_1x.png", "size": [960,960], "props": [{name,label,has_sprite,collision_rect}]}
格式与 mine / snow 的 props.json 完全一致，PropLayer 直接吃。

用法：python tools/make_dragon_collision.py
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/dragon_lair/v1/scene_1x.png"
OUT = ROOT / "assets/dragon_lair/v1/objects/props.json"
CELL = 32
LUM_MIN = 24
FILL_RATIO = 0.60

# 装饰即障碍（左闭右开，[x0,y0,x1,y1]）
# 盘龙按「环」挡，不按整块挡：龙身盘成一个圈，圈心的空地（x≈384-544, y≈405-540）
# 是终章几个人物站的位置，必须留空；正下方再挖一条通道（CARVE）让玩家走进圈心。
BLOCKS = [
    # 角点写法：[x0, y0, x1, y1]
    ("dragon_top", "盘龙·上", [280, 196, 604, 405]),
    ("dragon_left", "盘龙·左", [280, 405, 384, 600]),
    ("dragon_right", "盘龙·右", [544, 405, 604, 600]),
    ("dragon_bottom", "盘龙·下", [384, 540, 440, 600]),
    ("bones", "骸骨堆", [208, 288, 312, 528]),
]

# 强制可走（在 BLOCKS 之后应用）：龙身正下方那条阴影带本身被亮度判据算成岩壁，
# 但它是圈心唯一的入口，硬挖一条 64px 宽的通道出来。
CARVE = [
    [440, 540, 544, 640],
]


def _lum(c: tuple[int, int, int]) -> int:
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) // 1000


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    px = im.load()
    W, H = im.size
    cols, rows = W // CELL, H // CELL

    walk = [[False] * cols for _ in range(rows)]
    step = CELL // 8
    need = int((CELL // step) ** 2 * FILL_RATIO)
    for gy in range(rows):
        for gx in range(cols):
            hit = 0
            for y in range(gy * CELL, gy * CELL + CELL, step):
                for x in range(gx * CELL, gx * CELL + CELL, step):
                    if _lum(px[x, y]) >= LUM_MIN:
                        hit += 1
            walk[gy][gx] = hit >= need

    for _name, _label, rect in BLOCKS:
        x0, y0, x1, y1 = rect
        for gy in range(y0 // CELL, min(rows, (y1 + CELL - 1) // CELL)):
            for gx in range(x0 // CELL, min(cols, (x1 + CELL - 1) // CELL)):
                walk[gy][gx] = False

    for rect in CARVE:
        x0, y0, x1, y1 = rect
        for gy in range(y0 // CELL, min(rows, (y1 + CELL - 1) // CELL + 1)):
            for gx in range(x0 // CELL, min(cols, (x1 + CELL - 1) // CELL + 1)):
                walk[gy][gx] = True

    # 逐行连续段 → 纵向合并（同 x0、同 x1 的相邻行合并成一条）
    open_runs: dict[tuple[int, int], int] = {}  # (x0,x1) -> 起始行
    rects: list[list[int]] = []
    for gy in range(rows):
        runs: list[tuple[int, int]] = []
        gx = 0
        while gx < cols:
            if not walk[gy][gx]:
                s = gx
                while gx < cols and not walk[gy][gx]:
                    gx += 1
                runs.append((s, gx))
            else:
                gx += 1
        alive = set(runs)
        for key in list(open_runs):
            if key not in alive:
                start = open_runs.pop(key)
                rects.append([key[0] * CELL, start * CELL,
                              (key[1] - key[0]) * CELL, (gy - start) * CELL])
        for key in runs:
            open_runs.setdefault(key, gy)
    for key, start in open_runs.items():
        rects.append([key[0] * CELL, start * CELL,
                      (key[1] - key[0]) * CELL, (rows - start) * CELL])

    props: list[dict] = []
    idx = 0
    for x, y, w, h in sorted(rects, key=lambda r: (r[1], r[0])):
        props.append({
            "name": f"blk_{idx:03d}",
            "label": "岩壁",
            "has_sprite": False,
            "collision_rect": [x, y, w, h],
        })
        idx += 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "source": "assets/dragon_lair/v1/scene_1x.png",
        "size": [W, H],
        "props": props,
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    area = sum(p["collision_rect"][2] * p["collision_rect"][3] for p in props)
    print(f"底图 {W}x{H}，网格 {cols}x{rows}（{CELL}px）")
    print(f"岩壁碰撞 {len(props)} 条，覆盖 {area} px²（{area * 100 // (W * H)}%）")
    for _n, label, rect in BLOCKS:
        print(f"障碍 {label}: {rect}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
