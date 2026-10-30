#!/usr/bin/env python3
"""雪山地图碰撞自动生成：从底图判「可走地形」→ 16px 瓦片 → 补小破洞 → 合并矩形
→ 写 props.json（全部 has_sprite=false，纯碰撞，交给 PropLayer）。

取色标定（对这张图多次采样定档）：
  可走  雪地/冰面 : 亮度 >= 200 且 (max-min) <= 42
  可走  木桥/木构 : r-b >= 25 且 亮度 >= 95
  阻挡  未冻深水  : b-r >= 50            （冰湖/未结冰的池水）
  阻挡  其余      : 暗岩壁 / 云杉林 / 阴影
小屋是地标，整块强制阻挡（FORCE_BLOCK），免得玩家爬上屋顶。

用法：python tools/make_snow_collision.py
产物：assets/snow/v1/objects/props.json
      tests/probe_shots/snow_walkmask.png（可行走掩膜叠图，人工核对）
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BG = ROOT / "assets/snow/v1/scene_day_1x.png"
OUT_DIR = ROOT / "assets/snow/v1/objects"
PREVIEW = ROOT / "tests/probe_shots/snow_walkmask.png"

TILE = 16
WALK_RATIO = 0.55
HOLE_NEIGHBORS = 6

# 孤立小障碍清除：小片树影/碎石若四周几乎都可走 -> 允许从旁穿过
ISOLATED_MAX_TILES = 24
ISOLATED_MIN_RING_WALK = 0.75

# 木桥：本版图桥体是横向木带（x672-808 / y680-760），横跨一条纵向小溪
# 西岸是雪地（可落脚），东端接岩石、其下方是东侧雪地
FORCE_WALKABLE: list[tuple[int, int, int, int]] = [
    (668, 676, 148, 92),    # 桥面+护栏
    (808, 744, 96, 48),    # 东端岩石打通，接到东侧雪地（让桥可两端通行）
]

# 木桥走廊，用于"过桥是否落在实地"的防线校验
BRIDGE_RECT: tuple[int, int, int, int] = (668, 676, 148, 92)
# 桥的长轴方向：'x' = 桥沿 X 轴（横向），小溪在其上下两侧流过
BRIDGE_AXIS: str = "x"

# 强制阻挡（逻辑像素）：这一版是营地帐篷/木箱，不整块封，交给自动判
FORCE_BLOCK: list[tuple[int, int, int, int]] = []


def is_walkable(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    if (b - r) >= 50:                             # 未冻深水
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    bright = (r + g + b) / 3.0
    if bright >= 200.0 and (mx - mn) <= 42:        # 雪地 / 冰面
        return True
    if bright >= 165.0 and (mx - mn) <= 50:        # 稍暗的雪地 / 树影
        return True
    if (r - b) >= 25 and bright >= 95.0:           # 木桥 / 木构
        return True
    if (g - r) >= 8 and (g - b) >= 8 and 50 <= g <= 150:   # 云杉（可从树下穿过）
        return True
    return False


def _clear_isolated(walk: list[list[bool]], gw: int, gh: int) -> list[list[bool]]:
    if ISOLATED_MAX_TILES <= 0:
        return walk
    seen = [[False] * gw for _ in range(gh)]
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
                    if 0 <= nx < gw and 0 <= ny < gh and not walk[ny][nx] and not seen[ny][nx]:
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
            if ratio >= ISOLATED_MIN_RING_WALK:
                for (x, y) in cells:
                    walk[y][x] = True
    return walk


def _keep_largest_component(walk: list[list[bool]], gw: int, gh: int) -> list[list[bool]]:
    """只保留最大连通块：地图必须一整块能走通，孤立的雪窝一律封掉。"""
    seen = [[False] * gw for _ in range(gh)]
    best: list[tuple[int, int]] = []
    for ty in range(gh):
        for tx in range(gw):
            if not walk[ty][tx] or seen[ty][tx]:
                continue
            stack = [(tx, ty)]
            seen[ty][tx] = True
            cells: list[tuple[int, int]] = []
            while stack:
                x, y = stack.pop()
                cells.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < gw and 0 <= ny < gh and walk[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            if len(cells) > len(best):
                best = cells
    out = [[False] * gw for _ in range(gh)]
    for (x, y) in best:
        out[y][x] = True
    print(f"  连通块：保留最大 {len(best)} 瓦片")
    return out


BANK_MARGIN = 28      # 桥两端各往外查这么宽，必须是"可走的实地"


def _is_water_px(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return (b - r) >= 50


def _sample(x0: int, y0: int, x1: int, y1: int, px, walk) -> tuple[float, float]:
    """返回 (可走占比, 水像素占比)"""
    total = walk_ct = water_ct = 0
    for y in range(max(0, y0), min(1024, y1), 8):
        for x in range(max(0, x0), min(1024, x1), 8):
            total += 1
            if walk[y // TILE][x // TILE]:
                walk_ct += 1
            if _is_water_px(px[x, y]):
                water_ct += 1
    if total == 0:
        return 0.0, 0.0
    return walk_ct / total, water_ct / total


def _validate_bridge(walk: list[list[bool]], gw: int, gh: int, im: Image.Image) -> bool:
    """防线（关键在 ③）：一座**正确**的桥必须同时满足
      ① 桥面整条可走
      ② 沿桥长轴的两端是实地（河岸）—— 走过去不会掉水里
      ③ 垂直桥长轴的两侧都有水 —— 证明水道真的从桥下穿过
    只满足 ①② 而缺 ③，说明桥是**顺河平行**画的（就是"过桥走到水里"那次事故的根因）。
    任一条不满足就报错并不写盘。"""
    px = im.load()
    bx, by, bw, bh = BRIDGE_RECT
    M = BANK_MARGIN
    bad: list[str] = []

    for ty in range(by // TILE, min(gh, (by + bh + TILE - 1) // TILE)):
        for tx in range(bx // TILE, min(gw, (bx + bw + TILE - 1) // TILE)):
            if not walk[ty][tx]:
                bad.append(f"桥面瓦片({tx * TILE},{ty * TILE})不可走")

    if BRIDGE_AXIS == "x":
        ends = (("西岸", (bx - M, by, bx, by + bh)), ("东岸", (bx + bw, by, bx + bw + M, by + bh)))
        sides = (("上游侧", (bx, by - M, bx + bw, by)), ("下游侧", (bx, by + bh, bx + bw, by + bh + M)))
    else:
        ends = (("北岸", (bx, by - M, bx + bw, by)), ("南岸", (bx, by + bh, bx + bw, by + bh + M)))
        sides = (("西侧", (bx - M, by, bx, by + bh)), ("东侧", (bx + bw, by, bx + bw + M, by + bh)))

    end_reports: list[tuple[str, float, float]] = []
    for name, band in ends:
        walk_r, water_r = _sample(*band, px, walk)
        end_reports.append((name, walk_r, water_r))
    # 关键修正：桥必须"至少一端"落在实地（不是水），才能保证过桥不落水。
    # 单端的"水占比偏高"只是提示，真正致命的是"两端都不是实地"。
    walkable_ends = [(n, wr, wtr) for (n, wr, wtr) in end_reports if wr >= 0.60 and wtr <= 0.10]
    if not walkable_ends:
        bad.append("桥两端都没有可走的实地（落水风险）: " +
                   "; ".join(f"{n}可走{wr:.0%}/水{wtr:.0%}" for n, wr, wtr in end_reports))
    else:
        for n, wr, wtr in end_reports:
            if not (wr >= 0.60 and wtr <= 0.10):
                print(f"  提示：{n} 可走{wr:.0%}/水{wtr:.0%}（非致命，另一端是实地即可）")

    for name, band in sides:
        walk_r, water_r = _sample(*band, px, walk)
        if water_r < 0.15:
            bad.append(f"{name}没有水({water_r:.0%})——桥没有真的横跨水道，是顺河平行的")

    if bad:
        print("  [桥校验失败] " + "; ".join(bad))
        return False
    print("  桥校验通过：桥面可走、两端是河岸、且上下游都有水（确实横跨）")
    return True


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

    for bx, by, bw, bh in FORCE_BLOCK:
        for ty in range(by // TILE, min(gh, (by + bh + TILE - 1) // TILE)):
            for tx in range(bx // TILE, min(gw, (bx + bw + TILE - 1) // TILE)):
                walk[ty][tx] = False

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

    walk = _clear_isolated(walk, gw, gh)
    walk = _keep_largest_component(walk, gw, gh)

    # 防线：桥必须真的能把两岸连起来，否则不写盘并报错
    if not _validate_bridge(walk, gw, gh, im):
        print("未写出 props.json（桥校验未通过），先修底图或 BRIDGE_RECT/BRIDGE_AXIS")
        return 1

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
    data = {"source": "assets/snow/v1/scene_day_1x.png", "size": [W, H], "props": props}
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
