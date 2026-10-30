"""NPC 行走图集 -> 可入游戏的美术件（阴影残留清理 + 归档）。

背景
----
character/人物行走/*图集.png 是 240x480 = 4 列 x 4 行、单格 60x120 的行走图集。
这批图有两个客观特征（tools/probe_npc_sheets.py 量过）：

  1. alpha 只有 0 / 255，没有半透明像素 —— 背景是被硬抠掉的；
  2. 脚下没有独立的投影块（最底几行的像素范围就是鞋底本身）。

真正看得见的毛病是**轮廓边缘的灰雾**：脚踝、鞋侧、下摆外沿常挂着一圈
去饱和的中性灰像素，压在地板色上就像一圈脏影子，和角色本身的暖色调不一致。
本脚本就干这一件事：把「灰雾」按邻近本体的颜色重新上色（保持明度），
而不是抠掉 —— 抠掉会在剪影上开洞，重新上色只改色不改形。

判定条件（三条同时成立才算灰雾）
  · 去饱和：sat = (max-min)/max <= 0.18
  · 中低明度：40 <= max <= 175（排除纯黑描边与高光）
  · 贴边：4 邻域里有透明像素（内部像素不动）
  · 参照够艳：邻近 3px 内非灰雾像素的 sat 至少高出 0.15（否则本体就是灰的，别碰）

输出
----
  assets/actors/npc/<slug>.png   成品（游戏直接用这张）
  assets/actors/npc/_report.json 每个角色改了多少像素，便于复核

用法
----
  python tools/clean_npc_shadow.py             # 全量处理
  python tools/clean_npc_shadow.py --dry-run   # 只统计不改图
"""
from __future__ import annotations

import argparse
import json
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "character", "人物行走")
OUT_DIR = os.path.join(ROOT, "assets", "actors", "npc")
REPORT = os.path.join(OUT_DIR, "_report.json")

CELL_W, CELL_H = 60, 120
COLS, ROWS = 4, 4
# 只在这个高度以下找灰雾（角色高 120，脚在 119 附近）
FEET_TOP = 88

SAT_MAX = 0.18
VAL_MIN, VAL_MAX = 40, 175
SAT_GAP = 0.15       # 参照像素必须比灰雾艳这么多
BLEND = 0.95         # 重新上色的强度（1.0 = 完全换成参照色）
RADIUS = 3
ISLAND_MAX = 12      # 孤立的灰色小岛（<= 这个像素数）直接抹掉


def sat_of(c) -> float:
    r, g, b = c[0], c[1], c[2]
    mx, mn = max(r, g, b), min(r, g, b)
    return 0.0 if mx == 0 else (mx - mn) / mx


def slug_of(path: str) -> str:
    """人类骑士_林格_行走图集.png -> ringer 这种纯 ASCII 文件名不好维护，
    这里用「拼音无关」的稳定编号 + 中文名，游戏里按 JSON 引用，不靠文件名猜。"""
    base = os.path.basename(path).replace("_行走图集.png", "").replace("-行走图集.png", "")
    return base


def touches_clear(alpha, x: int, y: int) -> bool:
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if not (0 <= nx < CELL_W and 0 <= ny < CELL_H):
            return True
        if alpha[(nx, ny)] < 200:
            return True
    return False


def local_reference(get_rgb, alpha, fog, x: int, y: int):
    """邻近 3px 内、不是灰雾的像素，取中位数颜色（稳健，抗单个高光）。"""
    cols = []
    for dy in range(-RADIUS, RADIUS + 1):
        for dx in range(-RADIUS, RADIUS + 1):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < CELL_W and 0 <= ny < CELL_H):
                continue
            if fog.get((nx, ny)) or alpha[(nx, ny)] < 200:
                continue
            cols.append(get_rgb(nx, ny))
    if not cols:
        return None
    cols.sort(key=lambda c: c[0] + c[1] + c[2])
    mid = cols[len(cols) // 2]
    if sat_of(mid) < SAT_MAX + SAT_GAP:
        return None
    return mid


def retint(src, ref, blend: float):
    """把 src 换成 ref 的色相，明度仍用 src 的 —— 不改变像素图的明暗结构。"""
    smax = max(src[0], src[1], src[2]) or 1
    rmax = max(ref[0], ref[1], ref[2]) or 1
    target = tuple(min(255, int(round(ch * smax / rmax))) for ch in ref)
    return tuple(int(round(src[i] + (target[i] - src[i]) * blend)) for i in range(3))


def clean_cell(img: Image.Image, cx: int, cy: int, dry: bool) -> int:
    px = img.load()
    alpha = {(x, y): px[cx + x, cy + y][3] for y in range(CELL_H) for x in range(CELL_W)}

    def get_rgb(x: int, y: int):
        return px[cx + x, cy + y][:3]

    fog = {}
    for y in range(FEET_TOP, CELL_H):
        for x in range(CELL_W):
            if alpha[(x, y)] < 200:
                continue
            if not (VAL_MIN <= max(px[cx + x, cy + y][:3]) <= VAL_MAX):
                continue
            if sat_of(px[cx + x, cy + y][:3]) > SAT_MAX:
                continue
            if not touches_clear(alpha, x, y):
                continue
            fog[(x, y)] = True

    # 真正脱离本体的灰色小碎块（按 alpha 连通域判断，<= ISLAND_MAX 且全是灰雾）才删。
    # 注意：不能按「灰雾集合内部的连通性」判断 —— 边缘灰雾天然是一圈细链，
    # 那样会把合法的灰色铠甲边一并删掉。
    removed = 0
    if not dry and fog:
        seen = set()
        for y in range(CELL_H):
            for x in range(CELL_W):
                if alpha[(x, y)] < 200 or (x, y) in seen:
                    continue
                q = deque([(x, y)])
                seen.add((x, y))
                comp = []
                all_fog = True
                while q:
                    p = q.popleft()
                    comp.append(p)
                    if p not in fog:
                        all_fog = False
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        n = (p[0] + dx, p[1] + dy)
                        if not (0 <= n[0] < CELL_W and 0 <= n[1] < CELL_H):
                            continue
                        if alpha[n] >= 200 and n not in seen:
                            seen.add(n)
                            q.append(n)
                if all_fog and len(comp) <= ISLAND_MAX:
                    for (ix, iy) in comp:
                        px[cx + ix, cy + iy] = (0, 0, 0, 0)
                        fog.pop((ix, iy), None)
                        removed += 1

    changed = 0
    for (x, y), _ in fog.items():
        ref = local_reference(get_rgb, alpha, fog, x, y)
        if ref is None:
            continue
        if dry:
            changed += 1
            continue
        src = px[cx + x, cy + y][:3]
        new = retint(src, ref, BLEND)
        px[cx + x, cy + y] = (new[0], new[1], new[2], 255)
        changed += 1
    return changed + removed


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    files = sorted(
        f for f in os.listdir(SRC_DIR)
        if f.endswith("图集.png") and "总览" not in f
    )
    report = {}
    for name in files:
        src = os.path.join(SRC_DIR, name)
        img = Image.open(src).convert("RGBA")
        total = 0
        for r in range(ROWS):
            for c in range(COLS):
                total += clean_cell(img, c * CELL_W, r * CELL_H, args.dry_run)
        key = slug_of(src)
        report[key] = {"src": os.path.relpath(src, ROOT).replace("\\", "/"),
                       "pixels_touched": total}
        if not args.dry_run:
            img.save(os.path.join(OUT_DIR, key + ".png"))
        print(f"{'[dry] ' if args.dry_run else ''}{key}: {total}")

    if not args.dry_run:
        with open(REPORT, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print("report ->", os.path.relpath(REPORT, ROOT))


if __name__ == "__main__":
    main()
