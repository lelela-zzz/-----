#!/usr/bin/env python3
"""矿道入口地图碰撞自动生成：从底图判「可走地形」（草地/森林/土路）→ 16px 瓦片
→ 补小破洞 → 把阻挡瓦片合并成矩形 → 写 props.json（全部 has_sprite=false，
纯碰撞，交给 PropLayer 复用同一套管线）。

判定规则（对这张图的采样标定）：
  土路/泥地 : r >= g 且 r-b >= 30 且 r >= 105
  草地/森林 : g >= r + 14 且 g >= b - 6 且 g >= 55
  亮雪     : 亮度 >= 200 且 (max-min) <= 42 —— 路上的雪斑必须可走，
             崖上的雪斑会被周围岩壁围死，不影响可达性
  其余（岩壁/洞口/巨石）一律算阻挡

用法：python tools/make_mine_entrance_collision.py
产物：assets/mine_entrance/v1/objects/props.json
      tests/probe_shots/mine_entrance_walkmask.png（可行走掩膜叠图，人工核对用）
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BG = ROOT / "assets/mine_entrance/v1/scene_day_1x.png"
OUT_DIR = ROOT / "assets/mine_entrance/v1/objects"
PREVIEW = ROOT / "tests/probe_shots/mine_entrance_walkmask.png"

TILE = 16
WALK_RATIO = 0.55      # 瓦片内可走像素占比超过它才算可走
HOLE_NEIGHBORS = 6     # 被 6 个以上可走瓦片包围的阻挡瓦片 -> 填成可走

# 手工强制可走区（逻辑像素）：入口走廊——美术上土路确实通到上边缘，
# 但边缘常被雪/暗边判成岩壁，这里兜底打通（也是回村庄的传送口所在）
FORCE_WALKABLE = [
    (838, 0, 84, 80),      # 入口走廊
    # C4 那棵树：用户指定放行 B+C+D+E+F，单独保留 A（464,656,16,16）作障碍
    (496, 656, 16, 16),    # B
    (464, 672, 80, 16),    # C
    (496, 688, 48, 16),    # D
    (512, 704, 16, 16),    # E
    (512, 720, 32, 16),    # F
]

# 孤立小障碍清除：4 连通阻挡块 ≤14 瓦片、且外圈 ≥85% 可走 → 判为路边矮树/碎石，
# 改为可走（否则一棵树就能把整条路掐断）。岩壁、洞口这类大连通块不受影响。
ISOLATED_MAX_TILES = 0      # 0 = 关闭（用户反馈：只改指定那棵）
ISOLATED_MIN_RING_WALK = 0.85


def is_walkable(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    if r >= g and r - b >= 30 and r >= 105:      # 土路
        return True
    if g >= r + 14 and g >= b - 6 and g >= 55:   # 草地/森林
        return True
    mx = max(r, g, b)
    if (r + g + b) / 3.0 >= 200 and mx - min(r, g, b) <= 42:   # 亮雪
        return True
    return False


def main() -> int:
    im = Image.open(BG).convert("RGB")
    W, H = im.size
    px = im.load()
    gw, gh = W // TILE, H // TILE

    # 1) 瓦片可走率
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

    # 2) 填小破洞（路中间的雪斑/树影）
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

    # 2.5) 手工强制可走区
    for fx, fy, fw, fh in FORCE_WALKABLE:
        for ty in range(fy // TILE, min(gh, (fy + fh + TILE - 1) // TILE)):
            for tx in range(fx // TILE, min(gw, (fx + fw + TILE - 1) // TILE)):
                walk[ty][tx] = True

    # 2.6) 清掉孤立小障碍（路边矮树 / 碎石）
    seen = [[False] * gw for _ in range(gh)]
    cleared: list[tuple[int, int, int, int]] = []
    for ty in range(gh):
        for tx in range(gw):
            if walk[ty][tx] or seen[ty][tx]:
                continue
            stack = [(tx, ty)]
            seen[ty][tx] = True
            cells: list[tuple[int, int]] = []
            while stack:
                x, y = stack.pop()
                cells.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < gw and 0 <= ny < gh and not walk[ny][nx] \
                            and not seen[ny][nx]:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            if len(cells) > ISOLATED_MAX_TILES:
                continue
            ring: set[tuple[int, int]] = set()
            for (x, y) in cells:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < gw and 0 <= ny < gh and (nx, ny) not in cells:
                            ring.add((nx, ny))
            if not ring:
                continue
            ratio = sum(1 for (nx, ny) in ring if walk[ny][nx]) / len(ring)
            if ratio < ISOLATED_MIN_RING_WALK:
                continue
            for (x, y) in cells:
                walk[y][x] = True
            xs_ = [c[0] for c in cells]
            ys_ = [c[1] for c in cells]
            cleared.append((min(xs_) * TILE, min(ys_) * TILE,
                            (max(xs_) - min(xs_) + 1) * TILE,
                            (max(ys_) - min(ys_) + 1) * TILE))

    # 3) 阻挡瓦片 -> 矩形（按行合并连续段，再纵向合并同段）
    blocked = [[not walk[ty][tx] for tx in range(gw)] for ty in range(gh)]
    merged: list[tuple[int, int, int, int]] = []      # (tx, ty, tw, th)
    open_runs: dict[tuple[int, int], list[int]] = {}  # (tx, tw) -> [ty_start, ty_end]
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
    data = {
        "source": "assets/mine_entrance/v1/scene_day_1x.png",
        "size": [W, H],
        "props": props,
    }
    (OUT_DIR / "props.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    # 4) 预览：整块瓦片半透明着色（绿=可走 / 红=阻挡），叠在原图上
    from PIL import ImageDraw
    prev = im.convert("RGBA")
    layer = Image.new("RGBA", prev.size, (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    for ty in range(gh):
        for tx in range(gw):
            col = (40, 220, 90, 90) if walk[ty][tx] else (230, 40, 40, 90)
            dl.rectangle((tx * TILE, ty * TILE,
                          tx * TILE + TILE - 1, ty * TILE + TILE - 1), fill=col)
    prev = Image.alpha_composite(prev, layer).convert("RGB")
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    prev.save(PREVIEW)
    print(f"清掉孤立小障碍 {len(cleared)} 处: " + ", ".join(
        f"({c[0]},{c[1]}) {c[2]}x{c[3]}" for c in cleared))
    print(f"阻挡矩形 {len(props)} 条 -> {OUT_DIR / 'props.json'}")
    print(f"掩膜预览 -> {PREVIEW}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
