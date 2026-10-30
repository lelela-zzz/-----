#!/usr/bin/env python3
"""酒馆外观抠件 + 四时段派生 + props.json 生成（单一数据源）。

与 tools/cut_village_props.py 同一套语法/铁律，只保留本场景需要的单一对象：
  t00_tavern  酒馆建筑（rowscan 像素级抠图：红瓦/木构/灰泥/石材/窗玻璃谓词）
  铁律：sort_y = 精灵不透明底边；collision 下沿 = sort_y + 1。
碰撞从 y=0 顶到基线：建筑北侧到地图边没有可行走空间，防止玩家绕到
"屋顶后面"被整片建筑 prop 盖住（sort 语义只对基线以下的玩家成立）。

用法：
  python tools/cut_tavern_ext_props.py          # 白天抠件 + 生成 props.json
  python tools/cut_tavern_ext_props.py --derive # 从三张烘焙帧派生 _dawn/_dusk/_night
产物：assets/tavern_exterior/v1/objects/*.png + props.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/tavern_exterior/v1/scene_day_1x.png"
OUT = ROOT / "assets/tavern_exterior/v1/objects"
FRAMES = {
    "dawn": ROOT / "assets/tavern_exterior/v1/scene_dawn_1x.png",
    "dusk": ROOT / "assets/tavern_exterior/v1/scene_dusk_1x.png",
    "night": ROOT / "assets/tavern_exterior/v1/scene_night_1x.png",
}

# 形状语法与坐标 = scene_day_1x.png 的 512x512 像素坐标。
# 2026-10-30 换新底图（新酒馆外部概念图：居中裁 1024 方 → 0.5x 降到 512）。
# 实测新图：赤陶瓦屋顶 x≈36-492 / y≈32-211；墙脚基线 y≈320；正门中心 x≈237；
# 门前草地 y320-404，横贯石板路 y404-512。
# 碰撞仍从 y=0 顶到基线：建筑顶到地图边没有可行走空间，防玩家绕到屋顶后面。
OBJECTS: list[dict] = [
    dict(name="t00_tavern", label="炉火镇酒馆·正面", sort_y=320,
         shapes=[("rowscan", (34, 0, 462, 322), "tavern_ext")],
         collision=(34, 0, 462, 321)),
]

# ---------------------------------------------------------------- rowscan 预设


def _dark(c: tuple[int, int, int]) -> bool:
    return max(c) <= 92


def _wood(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return r - b >= 40 and r >= 105 and r > g >= b - 5


def _gray_obj(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return g - r <= 6 and max(r, g, b) - min(r, g, b) <= 24 and 55 <= (r + g + b) // 3 <= 240


def _glass(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return b - r >= 15 and b >= 95


def _veg(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return g > r + 6 and g > b + 6


def _pred_tavern_ext(r: int, g: int, b: int, x: int, y: int) -> bool:
    c = (r, g, b)
    if _veg(c):
        return False          # 绿色主导 = 草丛/灌木（左翼深色灌木会骗过 _dark）
    if _dark(c) or _wood(c) or _glass(c):
        return True
    return _gray_obj(c)          # 烟囱石 / 石材墙基 / 阳台白布


PRESETS: dict[str, tuple] = {
    "tavern_ext": (_pred_tavern_ext, 24, 14),
}


def rowscan_mask(crop: Image.Image, ox: int, oy: int, preset: str) -> Image.Image:
    """逐行物体段扫描 + 连续性跟踪 → 行填充掩膜（crop 坐标系）。"""
    pred, merge_gap, seed_min = PRESETS[preset]
    w, h = crop.size
    px = crop.load()
    out = Image.new("L", (w, h), 0)
    opx = out.load()
    prev: list[tuple[int, int]] = []   # 上一行选中的段
    for y in range(h):
        ay = oy + y
        runs: list[list[int]] = []
        for x in range(w):
            if pred(*px[x, y], ox + x, ay):
                if runs and x - runs[-1][1] <= merge_gap + 1:
                    runs[-1][1] = x
                else:
                    runs.append([x, x])
        runs = [r for r in runs if r[1] - r[0] + 1 >= 3]
        chosen: list[tuple[int, int]] = []
        for r in runs:
            if any(a - 8 <= r[1] and r[0] <= b + 8 for a, b in prev):
                chosen.append((r[0], r[1]))              # 与上一行连续
            elif not prev:
                chosen.append((r[0], r[1]))              # 物体首行
            elif r[1] - r[0] + 1 >= seed_min and all(
                    r[0] > b + 8 or r[1] < a - 8 for a, b in prev):
                chosen.append((r[0], r[1]))              # 独立新件（烟囱等）
        if not chosen and prev:
            prev = []
            continue
        for a, b in chosen:
            for x in range(a, b + 1):
                opx[x, y] = 255
        prev = chosen
    return out


# ---------------------------------------------------------------- 组装


def shapes_bbox(shapes: list[tuple]) -> tuple[int, int, int, int]:
    xs: list[float] = []
    ys: list[float] = []
    for kind, geo, *_ in shapes:
        if kind == "poly":
            xs += [p[0] for p in geo]
            ys += [p[1] for p in geo]
        else:  # rect / rowscan 均为 (x,y,w,h)
            x, y, w, h = geo
            xs += [x, x + w]
            ys += [y, y + h]
    x0, y0 = int(min(xs)), int(min(ys))
    x1, y1 = int(max(xs)) + 1, int(max(ys)) + 1
    return x0, y0, x1 - x0, y1 - y0


def build_mask(day: Image.Image, entry: dict) -> tuple[Image.Image, tuple[int, int, int, int]]:
    rect = shapes_bbox(entry["shapes"])
    box = (rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3])
    crop = day.crop(box)
    ox, oy = rect[0], rect[1]

    allow: Image.Image | None = None
    for kind, geo, *extra in entry["shapes"]:
        if kind == "rowscan":
            m = rowscan_mask(crop, ox, oy, extra[0])
        else:
            m = Image.new("L", crop.size, 0)
            d = ImageDraw.Draw(m)
            x, y, w, h = geo
            d.rectangle((x - ox, y - oy, x + w - ox, y + h - oy), fill=255)
        allow = m if allow is None else ImageChops.lighter(allow, m)

    keep = allow
    for kind, geo in entry.get("clips", []):
        m = Image.new("L", crop.size, 0)
        d = ImageDraw.Draw(m)
        if kind == "poly":
            d.polygon([(x - ox, y - oy) for x, y in geo], fill=255)
        else:
            x, y, w, h = geo
            d.rectangle((x - ox, y - oy, x + w - ox, y + h - oy), fill=255)
        keep = ImageChops.darker(keep, m)

    cut = day.crop(box).convert("RGBA")
    cut.putalpha(keep)
    return cut, rect


def main() -> int:
    derive = "--derive" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    day = Image.open(SRC).convert("RGB")

    props: list[dict] = []
    frames = {k: Image.open(v).convert("RGB") for k, v in FRAMES.items()} if derive else {}

    for entry in OBJECTS:
        has_sprite = "shapes" in entry
        item: dict = {
            "name": entry["name"],
            "label": entry["label"],
            "has_sprite": has_sprite,
            "collision_rect": list(entry["collision"]),
        }
        if has_sprite:
            cut, rect = build_mask(day, entry)
            cut.save(OUT / f"{entry['name']}.png")
            item["file"] = f"res://assets/tavern_exterior/v1/objects/{entry['name']}.png"
            item["sprite_rect"] = list(rect)
            item["sort_y"] = entry["sort_y"]
            if derive:
                alpha = cut.getchannel("A")
                for phase, frame in frames.items():
                    color = frame.crop((rect[0], rect[1],
                                        rect[0] + rect[2], rect[1] + rect[3])).convert("RGBA")
                    color.putalpha(alpha)
                    color.save(OUT / f"{entry['name']}_{phase}.png")
            props.append(item)
        else:
            props.append(item)

    data = {
        "source": "assets/tavern_exterior/v1/scene_day_1x.png",
        "size": [day.width, day.height],
        "props": props,
    }
    (OUT / "props.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    n_sprite = sum(1 for p in props if p["has_sprite"])
    print(f"抠件 {n_sprite} 张 -> {OUT}")
    if derive:
        print(f"四时段派生 x3 完成（{n_sprite * 3} 张）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
