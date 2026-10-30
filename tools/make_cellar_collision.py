#!/usr/bin/env python3
"""地窖碰撞可视化：解析 scenes/cellar.tscn + scenes/brewing_pot.tscn 的
RectangleShape2D 与节点位置，把全部碰撞/触发框画在地窖底图上。

颜色约定：
  红   实心碰撞（墙 / 木桶 / 货架 / 木箱 / 锅体）
  橙   传送触发区（楼梯）
  青   交互触发区（锅的 [E] 酿造范围）
  绿   可行走矩形（MapBounds.walkable）

用法：python tools/make_cellar_collision.py
产物：tests/probe_shots/cellar_collision.png（2x）
"""
from __future__ import annotations

import re
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CELLAR = ROOT / "scenes/cellar.tscn"
POT = ROOT / "scenes/brewing_pot.tscn"
BG = ROOT / "assets/cellar/v1/scene_day_1x.png"
OUT = ROOT / "tests/probe_shots/cellar_collision.png"
Z = 2


def _shape_sizes(text: str) -> dict[str, tuple[float, float]]:
    sizes: dict[str, tuple[float, float]] = {}
    for m in re.finditer(
            r'\[sub_resource type="RectangleShape2D" id="([^"]+)"\]\s*size = Vector2\(([\d.]+), ([\d.]+)\)',
            text):
        sizes[m.group(1)] = (float(m.group(2)), float(m.group(3)))
    return sizes


def _nodes(text: str) -> list[dict]:
    """粗解析节点块：name / parent / position / shape / 自定义导出字段。"""
    blocks: list[dict] = []
    parts = re.split(r'(?=\n\[node )', "\n" + text)
    for part in parts:
        m = re.match(r'\s*\[node name="([^"]+)"', part)
        if not m:
            continue
        node: dict = {"name": m.group(1)}
        for key, pat in (
                ("parent", r'parent="([^"]+)"'),
                ("position", r'\nposition = Vector2\(([-\d.]+), ([-\d.]+)\)'),
                ("shape", r'shape = SubResource\("([^"]+)"\)'),
                ("walkable", r'\nwalkable = Rect2\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)'),
                ("thickness", r'\nthickness = ([-\d.]+)'),
        ):
            mm = re.search(pat, part)
            if mm:
                node[key] = mm.groups() if len(mm.groups()) > 1 else mm.group(1)
        node["parent"] = node.get("parent", "")
        blocks.append(node)
    return blocks


def _xy(node: dict) -> tuple[float, float]:
    p = node.get("position")
    return (float(p[0]), float(p[1])) if p else (0.0, 0.0)


def main() -> int:
    cellar = CELLAR.read_text(encoding="utf-8")
    pot = POT.read_text(encoding="utf-8")
    sizes = {**_shape_sizes(cellar), **_shape_sizes(pot)}
    pot_nodes = {n["name"]: n for n in _nodes(pot)}

    im = Image.open(BG).convert("RGB")
    big = im.resize((im.width * Z, im.height * Z), Image.NEAREST).convert("RGBA")

    # 先把锅的贴图按它在场景里的实际摆放贴进图里（判碰撞时看得到本体）
    pot_tex = ROOT / "assets/items/pot/pot_empty.png"
    pot_node = next((n for n in _nodes(cellar)
                     if n["name"] == "BrewingPot" and n.get("parent") == "Sorted"), None)
    if pot_node is not None and pot_tex.exists():
        sprite_offset = None
        mm = re.search(r'\nsprite_offset = Vector2\(([-\d.]+), ([-\d.]+)\)', pot)
        sprite_offset = (float(mm.group(1)), float(mm.group(2))) if mm else (0.0, -80.0)
        pot_xy = _xy(pot_node)
        deco = Image.open(pot_tex).convert("RGBA")
        deco = deco.resize((deco.width * Z, deco.height * Z), Image.NEAREST)
        big.alpha_composite(deco, (int((pot_xy[0] + sprite_offset[0]) * Z),
                                   int((pot_xy[1] + sprite_offset[1]) * Z)))

    d = ImageDraw.Draw(big, "RGBA")

    def rect_box(x: float, y: float, w: float, h: float) -> list[float]:
        return [(x * Z), (y * Z), ((x + w) * Z), ((y + h) * Z)]

    rows: list[str] = []
    for node in _nodes(cellar):
        name = node["name"]
        parent = node["parent"]
        if "walkable" in node:
            wx, wy, ww, wh = (float(v) for v in node["walkable"])
            t = float(node.get("thickness", 64.0))
            d.rectangle(rect_box(wx, wy, ww, wh), outline=(60, 220, 120, 255), width=1)
            rows.append(f"walkable  ({wx:.0f},{wy:.0f}) {ww:.0f}x{wh:.0f}")
            for rx, ry, rw, rh in (
                    (wx - t, wy - t, ww + t * 2, t),
                    (wx - t, wy + wh, ww + t * 2, t),
                    (wx - t, wy, t, wh),
                    (wx + ww, wy, t, wh)):
                d.rectangle(rect_box(rx, ry, rw, rh), outline=(230, 60, 60, 255), width=1)
            continue
        if "shape" not in node:
            continue
        sw, sh = sizes[node["shape"]]
        cx, cy = _xy(node)
        left, top = cx - sw / 2.0, cy - sh / 2.0
        color = (230, 60, 60, 255)          # 实心碰撞
        if parent.startswith("Doors"):
            color = (255, 150, 40, 255)     # 传送触发
        if parent == "Sorted/BrewingPot/Zone":
            color = (60, 200, 255, 255)     # 交互触发
        d.rectangle(rect_box(left, top, sw, sh), outline=color, width=1)
        rows.append(f"{name:14s} ({left:.1f},{top:.1f}) {sw:.0f}x{sh:.0f}")

    # 锅体碰撞与交互区：pot 场景里的 Body/Collision、Zone/Shape（相对锅原点）+ 地窖里的锅位置
    pot_pos = next((_xy(n) for n in _nodes(cellar)
                    if n["name"] == "BrewingPot" and n.get("parent") == "Sorted"), None)
    if pot_pos and pot_nodes:
        for label, node_name, color in (
                ("PotBody", "Collision", (230, 60, 60, 255)),
                ("PotZone", "Shape", (60, 200, 255, 255))):
            node = pot_nodes.get(node_name)
            if node is None or "shape" not in node:
                continue
            sw, sh = sizes[node["shape"]]
            ox, oy = _xy(node)
            # Zone/Shape 是 Zone 的子节点，实际中心 = 锅位 + Zone.position + Shape.position
            if node_name == "Shape":
                zone = pot_nodes.get("Zone")
                zx, zy = _xy(zone) if zone else (0.0, 0.0)
                ox += zx
                oy += zy
            left = pot_pos[0] + ox - sw / 2.0
            top = pot_pos[1] + oy - sh / 2.0
            d.rectangle(rect_box(left, top, sw, sh), outline=color, width=1)
            rows.append(f"{label:14s} ({left:.1f},{top:.1f}) {sw:.0f}x{sh:.0f}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    big.save(OUT)
    print(f"地窖碰撞图 -> {OUT}")
    for r in rows:
        print("  ", r)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
