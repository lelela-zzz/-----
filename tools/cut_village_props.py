#!/usr/bin/env python3
"""村庄地图抠件 + 四时段派生 + props.json 生成（三合一，单一数据源）。

对象表 OBJECTS 是唯一权威。掩膜种类：
  ("rowscan", (x,y,w,h), 预设名)  逐行扫描：按预设的颜色类别判「物体像素」，
                                  行内合并成段，用连续性跟踪选中物体所在段，
                                  每行取段范围填充 → 像素级轮廓（建筑用）。
  ("canopy",  (x,y,w,h))          树冠：冠层色分类 → 最大连通域 → 逐行轮廓（树用）。
  ("poly"/"circle"/"rect", ...)   手工几何，与自动掩膜求并。
  clips=[...]                     可选硬裁剪（与最终掩膜求交，如酒馆 y649 截断）。
自动取 shapes 包围盒 = sprite_rect；collision/sort_y 同表维护。

用法：
  python tools/cut_village_props.py          # 白天抠件 + 生成 props.json
  python tools/cut_village_props.py --derive # 从三张烘焙帧派生 _dawn/_dusk/_night
产物：assets/village/v1/objects/*.png + props.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/village/v1/scene_day_1x.png"
OUT = ROOT / "assets/village/v1/objects"
FRAMES = {
    "dawn": ROOT / "assets/village/v1/scene_dawn_1x.png",
    "dusk": ROOT / "assets/village/v1/scene_dusk_1x.png",
    "night": ROOT / "assets/village/v1/scene_night_1x.png",
}

# 形状语法：见文件头注释。坐标 = scene_day_1x.png 的 866x866 像素坐标。
# 铁律：sort_y = 精灵不透明底边；collision 下沿 = sort_y + 1。
OBJECTS: list[dict] = [
    # ---------- 建筑（遮挡件，rowscan 像素级抠图） ----------
    dict(name="v00_tower", label="法师塔", sort_y=338,
         shapes=[("rowscan", (40, 0, 145, 341), "tower")],
         collision=(48, 215, 132, 119)),
    dict(name="v01_redhouse", label="红顶小屋", sort_y=130,
         shapes=[("rect", (260, 0, 143, 78)),
                 ("rect", (267, 78, 134, 52))],
         collision=(267, 50, 134, 81)),
    dict(name="v02_greenhouse_n", label="北绿顶大屋", sort_y=285,
         shapes=[("rowscan", (549, 36, 166, 252), "greenhouse")],
         collision=(549, 136, 167, 150)),
    dict(name="v03_bluehouse", label="蓝顶纹章屋", sort_y=661,
         shapes=[("rowscan", (0, 414, 196, 250), "bluehouse"),
                 ("canopy", (0, 378, 74, 128))],   # 屋顶上叠的西侧树冠，保留不挖洞
         clips=[("rect", (0, 414, 196, 247))],
         collision=(26, 507, 160, 155)),
    dict(name="v04_tavern", label="炉火镇酒馆", sort_y=648,
         shapes=[("rowscan", (546, 388, 170, 268), "tavern")],
         clips=[("rect", (546, 388, 170, 260))],   # 硬裁：台阶/花槽不进精灵
         collision=(553, 515, 152, 134)),
    dict(name="v05_stall_a", label="市场木棚西", sort_y=313,
         shapes=[("rowscan", (256, 184, 84, 136), "stall")],
         collision=(263, 262, 72, 52)),
    dict(name="v06_stall_b", label="市场木棚东", sort_y=310,
         shapes=[("rowscan", (390, 190, 76, 128), "stall")],
         collision=(396, 262, 74, 49)),
    dict(name="v07_shelfstall", label="货架摊", sort_y=540,
         shapes=[("rowscan", (254, 396, 86, 152), "stall")],
         collision=(268, 492, 58, 49)),
    dict(name="v08_well", label="水井", sort_y=495,
         shapes=[("rowscan", (400, 388, 76, 110), "well")],
         collision=(406, 460, 68, 36)),
    dict(name="v09_greentable", label="绿桌面炉台", sort_y=540,
         shapes=[("rect", (336, 480, 55, 60))],
         collision=(339, 496, 49, 45)),
    dict(name="v10_canopystall", label="米色布篷摊", sort_y=843,
         shapes=[("rect", (486, 719, 93, 124))],
         collision=(490, 768, 84, 76)),
    # ---------- 树（遮挡件：canopy 树冠 + 手工树干） ----------
    dict(name="v11_tree_tl", label="树·左上角", sort_y=104,
         shapes=[("canopy", (0, 0, 60, 66)), ("rect", (24, 50, 12, 18))],
         collision=(31, 83, 16, 26)),
    dict(name="v12_tree_lm", label="树·左中", sort_y=289,
         shapes=[("canopy", (0, 146, 44, 64)), ("rect", (13, 192, 12, 21))],
         collision=(19, 269, 16, 28)),
    dict(name="v13_tree_n1", label="树·北屋左", sort_y=100,
         shapes=[("canopy", (475, 5, 94, 92)), ("rect", (514, 82, 17, 19))],
         collision=(516, 78, 22, 28)),
    dict(name="v14_tree_n2", label="树·北屋右", sort_y=97,
         shapes=[("canopy", (634, 12, 84, 80)), ("rect", (669, 74, 17, 24))],
         collision=(692, 86, 14, 12)),
    dict(name="v15_tree_shoren", label="树·北码头", sort_y=140,
         shapes=[("canopy", (652, 4, 98, 96)), ("rect", (696, 98, 17, 43))],
         collision=(698, 110, 16, 31)),
    dict(name="v16_tree_shores", label="树·南码头", sort_y=853,
         shapes=[("canopy", (664, 726, 86, 100)), ("rect", (703, 820, 20, 33))],
         collision=(697, 816, 13, 38)),
    dict(name="v17_tree_bl1", label="树·左下西", sort_y=842,
         shapes=[("canopy", (0, 732, 80, 84)), ("rect", (30, 812, 18, 30))],
         collision=(26, 818, 16, 25)),
    dict(name="v18_tree_bl2", label="树·左下东", sort_y=850,
         shapes=[("canopy", (91, 728, 99, 100)), ("rect", (128, 822, 20, 28))],
         collision=(128, 824, 28, 27)),
    # ---------- 后补（2026-10-22 用户指认漏抠） ----------
    dict(name="v20_market_booth", label="市场大摊位", sort_y=747,
         shapes=[("rowscan", (263, 590, 145, 178), "stall")],
         clips=[("rect", (263, 590, 145, 159))],   # 截掉南侧石槽
         collision=(272, 670, 124, 78)),
    # ---------- 后补（2026-10-23 用户精修图提升/新增） ----------
    # 注意：2026-10-23 起精灵以 tools/import_user_cut.py 导入的用户精修版为最终版；
    # 重跑本脚本会用算法掩膜覆盖，覆盖后必须再跑一次 import_user_cut.py。
    dict(name="w_flower_well", label="花坛·井南", sort_y=542,
         shapes=[("rect", (407, 497, 64, 46))],
         collision=(407, 497, 64, 46)),
    # ---------- 纯碰撞（无精灵） ----------
    # 水域：水线实测 x=765；栈桥木板逐行扫描 y：147-220 / 350-403 / 503-572 / 699-769
    dict(name="w_water_n1", label="水域·北1", collision=(765, 0, 101, 147)),
    dict(name="w_water_n2", label="水域·北2", collision=(765, 220, 101, 130)),
    dict(name="w_water_n3", label="水域·中1", collision=(765, 403, 101, 100)),
    dict(name="w_water_s1", label="水域·中2", collision=(765, 572, 101, 127)),
    dict(name="w_water_s2", label="水域·南", collision=(765, 769, 101, 97)),
    # 停靠船体（栈桥东侧 x>=806 的非水区域）
    dict(name="w_boat1", label="船·北1", collision=(806, 128, 47, 99)),
    dict(name="w_boat2", label="船·北2", collision=(806, 320, 47, 99)),
    dict(name="w_boat3", label="船·南1", collision=(806, 480, 48, 96)),
    dict(name="w_boat4", label="船·南2", collision=(806, 680, 48, 104)),
    # 东岸护墙 x747-760，栈桥开口处断开
    dict(name="w_parapet_e1", label="护墙·东1", collision=(747, 0, 14, 147)),
    dict(name="w_parapet_e2", label="护墙·东2", collision=(747, 220, 14, 130)),
    dict(name="w_parapet_e3", label="护墙·东3", collision=(747, 403, 14, 100)),
    dict(name="w_parapet_e4", label="护墙·东4", collision=(747, 572, 14, 127)),
    dict(name="w_parapet_e5", label="护墙·东5", collision=(747, 769, 14, 97)),
    # 塔南台地不设碰撞（用户 2026-10-22 拍板去除红框；花箱/台地可自由通行）
    dict(name="w_fence_w1", label="围栏·横段*", collision=(0, 783, 84, 34)),
    dict(name="w_fence_w3", label="围栏·纵段*", collision=(0, 817, 34, 49)),
    dict(name="w_trough", label="石槽水池*", collision=(273, 800, 127, 66)),
    dict(name="w_crates", label="市场货箱堆", collision=(568, 753, 100, 101)),
    dict(name="w_wheel", label="大木轮", collision=(475, 816, 35, 38)),
    dict(name="w_barrels_gn", label="酒桶·北屋*", collision=(688, 252, 24, 29)),
    dict(name="w_planter_gn", label="花槽·北屋*", collision=(543, 261, 16, 19)),
    dict(name="w_planter_tavern", label="花槽·酒馆西", collision=(543, 648, 42, 36)),
    dict(name="w_planter_tavern_e", label="花坛·酒馆东南", collision=(690, 641, 47, 36)),
    dict(name="w_flower_bl1", label="花坛·蓝屋西", collision=(8, 655, 68, 26)),
    dict(name="w_flower_bl2", label="花坛·蓝屋东", collision=(132, 655, 44, 26)),
    dict(name="w_barrel_bl", label="木桶·蓝屋", collision=(163, 634, 26, 28)),
    dict(name="w_sign_n", label="路牌·北", collision=(567, 79, 26, 22)),
]

# ---------------------------------------------------------------- rowscan 预设
# 每个 preset: (物体谓词(r,g,b,x,y)->bool, 行内段合并缝隙, 新段最小宽度)


def _dark(c: tuple[int, int, int]) -> bool:
    return max(c) <= 92


def _wood(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return r - b >= 40 and r >= 105 and r > g >= b - 5


def _gray_obj(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return g - r <= 6 and max(r, g, b) - min(r, g, b) <= 20 and 55 <= (r + g + b) // 3 <= 215


def _dirt(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return r - g >= 15 and r - b >= 30 and r >= 140


def _grass(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    return g - r >= 15 and g - b >= 40 and g >= 110


def _pred_tower(r: int, g: int, b: int, x: int, y: int) -> bool:
    c = (r, g, b)
    if _dark(c) or _wood(c):
        return True
    if b > g + 10 and r > 85 and b >= 125:          # 紫色锥顶/冠
        return True
    if r >= 195 and g <= 165:                        # 花丛（红黄粉）
        return True
    if y >= 280 and g - r >= 12 and g - b >= 30:     # 基部门侧花叶
        return True
    return _gray_obj(c)                              # 塔身/塔冠/水晶（中性灰）


def _pred_greenhouse(r: int, g: int, b: int, x: int, y: int) -> bool:
    c = (r, g, b)
    if _dark(c) or _wood(c):
        return True
    if g - r >= 30 and 12 <= g - b <= 62 and g >= 105:   # 青绿瓦
        return True
    if r >= 180 and r - b >= 35 and b >= 132:            # 灰泥墙（亮于泥土）
        return True
    if 552 <= x <= 714 and 218 <= y <= 268 and g - r >= 12 and g - b >= 30:
        return True                                       # 墙面藤蔓
    return _gray_obj(c)                                   # 烟囱石


def _pred_bluehouse(r: int, g: int, b: int, x: int, y: int) -> bool:
    c = (r, g, b)
    if _dark(c) or _wood(c):
        return True
    if b - r >= 18 and b >= 90 and b - g <= 45 and g >= r - 5:   # 蓝灰瓦
        return True
    if r >= 195 and g <= 165:                                    # 门前花坛
        return True
    return _gray_obj(c)                                          # 石墙


def _pred_tavern(r: int, g: int, b: int, x: int, y: int) -> bool:
    c = (r, g, b)
    if _dark(c) or _wood(c):
        return True
    if g - r >= 28 and 8 <= g - b <= 60 and g >= 100:    # 青绿瓦+烟囱
        return True
    if r >= 178 and r - b >= 32 and b >= 132:            # 灰泥墙
        return True
    if r >= 190 and g <= 150:                            # 门前花
        return True
    return False


def _pred_stall(r: int, g: int, b: int, x: int, y: int) -> bool:
    c = (r, g, b)
    if _dark(c):
        return True
    if r - g >= 22 and r - b >= 40 and r >= 105:         # 木棚（亮木）
        return True
    if 85 <= r <= 148 and r - b >= 30 and r >= g - 5 and g >= b - 5:
        return True                                       # 深橄榄木板/阴影面
    if b - r >= 18 and b >= 90 and max(c) <= 150:        # 货物蓝
        return True
    if g - r >= 20 and g - b >= 10 and max(c) <= 160:    # 货物绿
        return True
    return False


def _pred_well(r: int, g: int, b: int, x: int, y: int) -> bool:
    c = (r, g, b)
    if _dark(c) or _wood(c):
        return True
    if (r + g + b) // 3 <= 176 and _gray_obj(c):         # 石台（亮中性>176 让给广场）
        return True
    return False


PRESETS: dict[str, tuple] = {
    "tower": (_pred_tower, 14, 14),
    "greenhouse": (_pred_greenhouse, 30, 14),
    "bluehouse": (_pred_bluehouse, 14, 14),
    "tavern": (_pred_tavern, 40, 14),
    "stall": (_pred_stall, 14, 12),
    "well": (_pred_well, 12, 12),
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
        # 物体像素 → 段（合并小缝隙）
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
                chosen.append((r[0], r[1]))              # 独立新件（烟囱/木桶等）
        # 防断链：一行全空后不再恢复（物体逐行连续）
        if not chosen and prev:
            prev = []
            continue
        for a, b in chosen:
            for x in range(a, b + 1):
                opx[x, y] = 255
        prev = chosen
    return out


# ---------------------------------------------------------------- canopy（树冠）


def _canopy_color(c: tuple[int, int, int]) -> bool:
    r, g, b = c
    if g - r >= 24 and g - b >= 35 and g >= 100:          # 冠层绿（亮/中）
        return True
    if max(r, g, b) <= 100 and g >= r - 20 and g >= b - 20:  # 深影/描边（偏绿）
        return True
    return False


def canopy_mask(crop: Image.Image) -> Image.Image:
    """冠层分类 → 最大 4 邻连通域 → 逐行 min/max 填充轮廓。"""
    w, h = crop.size
    px = crop.load()
    raw = bytearray(w * h)
    for y in range(h):
        base = y * w
        for x in range(w):
            if _canopy_color(px[x, y]):
                raw[base + x] = 1
    label = bytearray(w * h)
    best_id, best_n, cur_id = 0, 0, 0
    comp: list[int] = []
    for start in range(w * h):
        if raw[start] and not label[start]:
            cur_id += 1
            n = 0
            comp.clear()
            comp.append(start)
            label[start] = cur_id
            while comp:
                i = comp.pop()
                n += 1
                x, y = i % w, i // w
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if raw[j] and not label[j]:
                            label[j] = cur_id
                            comp.append(j)
            if n > best_n:
                best_id, best_n = cur_id, n
    out = Image.new("L", (w, h), 0)
    if best_id == 0:
        return out
    opx = out.load()
    for y in range(h):
        xs = [x for x in range(w) if label[y * w + x] == best_id]
        if xs:
            for x in range(min(xs), max(xs) + 1):
                opx[x, y] = 255
    return out


# ---------------------------------------------------------------- 组装


def shapes_bbox(shapes: list[tuple]) -> tuple[int, int, int, int]:
    xs: list[float] = []
    ys: list[float] = []
    for kind, geo, *_ in shapes:
        if kind == "poly":
            xs += [p[0] for p in geo]
            ys += [p[1] for p in geo]
        elif kind == "circle":
            cx, cy, r = geo
            xs += [cx - r, cx + r]
            ys += [cy - r, cy + r]
        else:  # rect / rowscan / canopy 均为 (x,y,w,h)
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
        elif kind == "canopy":
            x, y, w, h = geo
            full = canopy_mask(crop)
            m = Image.new("L", crop.size, 0)
            m.paste(full.crop((x - ox, y - oy, x - ox + w, y - oy + h)),
                    (x - ox, y - oy))
        else:
            m = Image.new("L", crop.size, 0)
            d = ImageDraw.Draw(m)
            if kind == "poly":
                d.polygon([(x - ox, y - oy) for x, y in geo], fill=255)
            elif kind == "circle":
                cx, cy, r = geo
                d.ellipse((cx - r - ox, cy - r - oy, cx + r - ox, cy + r - oy), fill=255)
            else:
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
            item["file"] = f"res://assets/village/v1/objects/{entry['name']}.png"
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
        "source": "assets/village/v1/scene_day_1x.png",
        "size": [day.width, day.height],
        "props": props,
    }
    (OUT / "props.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    n_sprite = sum(1 for p in props if p["has_sprite"])
    print(f"抠件 {n_sprite} 张 / 纯碰撞 {len(props) - n_sprite} 条 -> {OUT}")
    if derive:
        print(f"四时段派生 x3 完成（{n_sprite * 3} 张）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
