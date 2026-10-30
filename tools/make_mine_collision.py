#!/usr/bin/env python3
"""矿井地图碰撞自动生成：从底图判「可走地形」→ 16px 瓦片 → 补小破洞 → 合并矩形
→ 写 props.json（全部 has_sprite=false，纯碰撞，交给 PropLayer）。

这张洞穴图的取色标定（RGB 取样见 tools/ 备注）：
  石地/亮面 : 平均亮度 >= 78            （可走）
  木栈道/木梁: r-b >= 22 且 亮度 >= 48    （可走）
  黑岩/深空 : 亮度 <  ~55 且 中性        （阻挡）
  灰岩壁    : 亮度 ~69-73 且 r-b 小       （阻挡）
瓦片内可走像素占比 >= WALK_RATIO 才算可走（容忍火把/碎石/苔藓等杂点）。

用法：python tools/make_mine_collision.py
产物：assets/mine/v1/objects/props.json
      tests/probe_shots/mine_walkmask.png（可行走掩膜叠图，人工核对）
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BG = ROOT / "assets/mine/v1/scene_day_1x.png"
OUT_DIR = ROOT / "assets/mine/v1/objects"
PREVIEW = ROOT / "tests/probe_shots/mine_walkmask.png"

TILE = 16
WALK_RATIO = 0.55
HOLE_NEIGHBORS = 6

# 手工强制可走区（逻辑像素）——入口走廊与门附近被杂点/拱门判成阻挡时兜底打通。
FORCE_WALKABLE: list[tuple[int, int, int, int]] = [
    (480, 0, 72, 110),   # 顶部矿洞入口走廊（回来时的传送门所在）
]

# 孤立小障碍清除（默认关闭；开矿洞时先关，只看掩膜）
ISOLATED_MAX_TILES = 0
ISOLATED_MIN_RING_WALK = 0.85


def is_walkable(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    bright = (r + g + b) / 3.0
    if bright >= 78.0:                    # 石地/亮面
        return True
    if (r - b) >= 22 and bright >= 48.0:   # 木栈道/木梁
        return True
    return False


def main() -> int:
    im = Image.open(BG).convert("RGB")
    W, H = im.size
    px = im.load()
    gw, gh = W // TILE, H // TILE

    tile = [[0.0] * gw for _ in range(gh)]
    for ty in range(gh):
        for tx in range(gw):
            n = 0
            for y in range(ty * TILE, ty * TILE + TILE):
                for x in range(tx * TILE, tx * TILE + TILE):
                    if is_walkable(px[x, y]):
                        n += 1
            tile[ty][tx] = n / float(TILE * TILE)
    walk = [[tile[ty][tx] >= WALK_RATIO for tx in range(gw)] for ty in range(gh)]

    # 填小破洞
    filled = [row[:] for row in walk]
    for ty in range(1, gh - 1):
        for tx in range(1, gw - 1):
            if walk[ty][tx]:
                continue
            nb = sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                     if not (dx == 0 and dy == 0) and walk[ty + dy][tx + dx])
            if nb >= HOLE_NEIGHBORS:
                filled[ty][tx] = True
    walk = filled

    for fx, fy, fw, fh in FORCE_WALKABLE:
        for ty in range(fy // TILE, min(gh, (fy + fh + TILE - 1) // TILE)):
            for tx in range(fx // TILE, min(gw, (fx + fw + TILE - 1) // TILE)):
                walk[ty][tx] = True

    # 阻挡瓦片 -> 矩形
    blocked = [[not walk[ty][tx] for tx in range(gw)] for ty in range(gh)]
    merged: list[tuple[int, int, int, int]] = []
    open_runs: dict[tuple[int, int], list[int]] = {}
    for ty in range(gh):
        runs: list[tuple[int, int]] = []
        tx = 0
        while tx < gw:
            if blocked[ty][tx]:
                start = tx
                while tx < gw and blocked[ty][tx]:
                    tx += 1
                runs.append((start, tx - start))
            else:
                tx += 1
        new_open: dict[tuple[int, int], list[int]] = {}
        for key in runs:
            if key in open_runs:
                open_runs[key][1] = ty
                new_open[key] = open_runs[key]
            else:
                open_runs[key] = [ty, ty]
                new_open[key] = open_runs[key]
        for key, span in list(open_runs.items()):
            if key not in new_open:
                merged.append((key[0], span[0], key[1], span[1] - span[0] + 1))
        open_runs = new_open
    for key, span in open_runs.items():
        merged.append((key[0], span[0], key[1], span[1] - span[0] + 1))

    props = []
    for i, (tx, ty, tw, th) in enumerate(merged):
        props.append({
            "name": f"blk_{i:03d}",
            "label": "岩壁",
            "has_sprite": False,
            "collision_rect": [tx * TILE, ty * TILE, tw * TILE, th * TILE],
        })
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    data = {"source": "assets/mine/v1/scene_day_1x.png", "size": [W, H], "props": props}
    (OUT_DIR / "props.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    prev = im.convert("RGBA")
    layer = Image.new("RGBA", prev.size, (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    for ty in range(gh):
        for tx in range(gw):
            col = (40, 220, 90, 90) if walk[ty][tx] else (230, 40, 40, 90)
            dl.rectangle((tx * TILE, ty * TILE, tx * TILE + TILE - 1, ty * TILE + TILE - 1),
                         fill=col)
    prev = Image.alpha_composite(prev, layer).convert("RGB")
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    prev.save(PREVIEW)
    walk_ct = sum(1 for ty in range(gh) for tx in range(gw) if walk[ty][tx])
    print(f"可走瓦片 {walk_ct}/{gw * gh}  阻挡矩形 {len(props)} 条 -> {OUT_DIR / 'props.json'}")
    print(f"掩膜预览 -> {PREVIEW}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
