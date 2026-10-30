#!/usr/bin/env python3
"""把 v15 底图里的家具逐件拆出来，导出成可以手工修改的独立 PNG。

为什么按"家具框"而不是按连通域拆：
  连通域会拆出 86 块碎片（椅腿、瓶盖、台阶各自成块），既不是"一件家具"，
  也没法跟碰撞框一一对应。这里以已量好的 17 个家具框为**种子**：
  盒子只用来找"哪些像素属于这件东西"，最终精灵尺寸按实际不透明范围收紧。

三道保底（都是"宁可多留"）：
  1. **窗口外扩 12px**：手量的框经常切掉一点（椅背、栏板端头），先扩再取，
     最后按不透明范围收紧，所以外扩不会让精灵变大
  2. **描边/接触阴影保底**：暗像素、以及离暗像素 2px 内的像素一律保留
     （木纹缝、落地阴影都在里面；否则桌腿看着悬空）
  3. **补洞**：只保留与窗口边界连通的透明区，被包住的小洞一律填实
     （桌面高光被误擦出的"裂缝"必须补，否则角色会从缝里透出来）

只有"确定是空地"的像素才透明：属于地板连通域 + 颜色接近局部地板中位色 +
不是暗像素 + 离暗像素超过 2px。

导出（assets/house/v4/objects/）：
  prop_NN_<slug>.png / _2x.png   独立精灵，RGBA，透明底，尺寸按实际内容收紧
  props.json                      sprite_rect（摆放）/ sort_y（排序）/ collision_rect（碰撞）
  _preview_sheet.png              2× 总览：原图 + 精灵取景框（青）+ 碰撞框（黄）
  _alpha_check.png                2× 棋盘底，检查透明区
  _contact_sheet.png              2× 逐件对照表
用法：python tools/export_props_v15.py
"""
from __future__ import annotations

import json
import os
from collections import deque

from PIL import Image, ImageDraw, ImageFont

SRC = "assets/house/v4/scene_day_v15_1x.png"
OUT = "assets/house/v4/objects"
W, H = 640, 384
DARK = 70          # 描边阈值（亮度）
FLOOR_MIN = 20000  # 面积超过它 = 地板整块
COLOR_TOL = 18     # 与地板中位色的通道差，小于它才算"地板色"
NEAR_DARK = 2      # 离暗像素这么近的像素保底保留
WALL_TOP = 82      # 种子框顶在这条线以上 = 贴墙件，排序点取精灵顶边
# 取景窗外扩量：按相邻家具的间距给，长桌之间只有 16px 所以给小值
MARGIN = {"long_table": 6, "round_table": 12}
MARGIN_DEFAULT = 10      # 种子框顶在这条线以上 = 贴墙件，排序点取精灵顶边

# (slug, 中文名, x, y, w, h[, 取景窗]) —— 前 5 项是手量框，同时作为碰撞框；
# 第 6 项（可选）= 精灵取景窗：手量框切到东西、或者框本身漏了部件（如右边椅背）时给。
PROPS: list[tuple] = [
    ("left_shelf", "左后墙酒架", 4, 4, 64, 104),
    ("bar_top", "吧台顶条", 70, 98, 202, 26, (56, 88, 220, 44)),
    ("bar_column", "吧台立柱", 70, 98, 28, 122, (56, 88, 48, 142)),
    ("bar_return", "吧台回折", 70, 194, 82, 26, (10, 186, 94, 48)),
    ("crates", "左侧箱桶堆", 16, 220, 64, 104),
    ("hearth", "壁炉", 288, 58, 66, 48, (282, 52, 78, 60)),
    ("barrels", "酒桶", 354, 88, 88, 56, (350, 82, 96, 66)),
    ("right_shelf", "右背柜", 482, 58, 116, 50, (476, 52, 128, 62)),
    ("stairs", "楼梯", 594, 4, 46, 168, (588, 0, 52, 178)),
    ("long_table_1", "长桌 1", 126, 130, 70, 90, (118, 132, 90, 88)),
    ("long_table_2", "长桌 2", 212, 130, 70, 90, (204, 132, 90, 88)),
    ("long_table_3", "长桌 3", 126, 226, 70, 90, (118, 218, 90, 90)),
    ("long_table_4", "长桌 4", 212, 226, 70, 90, (204, 218, 90, 90)),
    ("round_table_1", "圆桌 1", 386, 166, 78, 68, (376, 160, 100, 72)),
    ("round_table_2", "圆桌 2", 494, 166, 78, 68, (484, 160, 92, 72)),
    ("round_table_3", "圆桌 3", 386, 232, 78, 68, (380, 226, 112, 74)),
    ("round_table_4", "圆桌 4", 494, 232, 78, 68, (486, 226, 96, 74)),
]


def lum(c: tuple[int, int, int]) -> float:
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def median_color(samples: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    if not samples:
        return (0, 0, 0)
    chans = list(zip(*samples))
    return tuple(sorted(c)[len(c) // 2] for c in chans)  # type: ignore[return-value]


def analyse(im: Image.Image):
    """返回 (像素, 暗掩膜, 连通域标号, 地板标号, 地板参考色, 暗膨胀掩膜)。"""
    px = im.load()
    dark = bytearray(W * H)
    for y in range(H):
        row = y * W
        for x in range(W):
            if lum(px[x, y]) < DARK:
                dark[row + x] = 1

    label = [-1] * (W * H)
    sizes: list[int] = []
    for y in range(H):
        for x in range(W):
            start = y * W + x
            if dark[start] or label[start] >= 0:
                continue
            idx = len(sizes)
            q = deque([start])
            label[start] = idx
            count = 0
            while q:
                p = q.popleft()
                count += 1
                cy, cx = divmod(p, W)
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if 0 <= nx < W and 0 <= ny < H:
                        n = ny * W + nx
                        if not dark[n] and label[n] < 0:
                            label[n] = idx
                            q.append(n)
            sizes.append(count)

    floor_idx = max(range(len(sizes)), key=lambda i: sizes[i]) if sizes else -1
    floor_px = [i for i in range(W * H) if label[i] == floor_idx]
    floor_ref = median_color([px[i % W, i // W] for i in floor_px[::37]])

    # 暗像素膨胀 NEAR_DARK 圈：木纹缝、描边、接触阴影都靠它保底
    near_dark = bytearray(dark)
    for _ in range(NEAR_DARK):
        grown = bytearray(near_dark)
        for i, v in enumerate(near_dark):
            if not v:
                continue
            cy, cx = divmod(i, W)
            for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                if 0 <= nx < W and 0 <= ny < H:
                    grown[ny * W + nx] = 1
        near_dark = grown
    return px, dark, label, floor_idx, floor_ref, near_dark


def build_alpha(px, dark, label, floor_idx, floor_ref, near_dark) -> bytearray:
    """alpha = 描边 ∪ 描边 2px 内 ∪ 非地板连通域。

    这版是逐件肉眼比对选出来的：家具的亮面（桌面、椅面）常常和地板同色，
    按颜色区分会漏；但它们的描边一定是暗的，所以"暗像素 + 暗像素外 2px"最稳，
    连带把木纹缝和椅面填实。地板上散落的落地阴影**不收**（离家具主体远，
    而且它不该参与遮挡：角色站到家具后面时影子盖住角色是错的；影子仍在背景里）。
    """
    alpha = bytearray(W * H)
    for i in range(W * H):
        if dark[i] or near_dark[i] or label[i] != floor_idx:
            alpha[i] = 255
    return alpha


def structural_components(alpha: bytearray):
    """把结构剪影拆成连通域（供“这件东西到底到哪儿为止”用）。"""
    seen = bytearray(W * H)
    comps = []
    for start in range(W * H):
        if not alpha[start] or seen[start]:
            continue
        q = deque([start])
        seen[start] = 1
        pixels = []
        while q:
            i = q.popleft()
            pixels.append(i)
            cy, cx = divmod(i, W)
            for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                if 0 <= nx < W and 0 <= ny < H:
                    n = ny * W + nx
                    if alpha[n] and not seen[n]:
                        seen[n] = 1
                        q.append(n)
        xs = [i % W for i in pixels]
        ys = [i // W for i in pixels]
        comps.append({
            "pixels": pixels,
            "x0": min(xs), "x1": max(xs), "y0": min(ys), "y1": max(ys),
        })
    return comps


def pick_window(comps, rect: tuple[int, int, int, int]) -> tuple[int, int, int, int] | None:
    """挑出“属于这件家具”的连通域，返回它们的并集 bbox。

    判据：连通域里 ≥30% 的像素落在手量框内。邻桌的连通域落在框内的比例接近 0，
    所以不会被吃进来；椅背/长凳这类超出框的部件因为主体在框内，会被带上。
    再加两道保险：bbox 不许超出 手量框±24，面积不许超过 框面积×3。
    """
    rx, ry, rw, rh = rect
    sel = []
    for c in comps:
        inside = 0
        for i in c["pixels"]:
            x, y = i % W, i // W
            if rx <= x < rx + rw and ry <= y < ry + rh:
                inside += 1
        if inside / len(c["pixels"]) < 0.30:
            continue
        if len(c["pixels"]) > rw * rh * 3:
            continue
        if (c["x0"] < rx - 24 or c["y0"] < ry - 24
                or c["x1"] > rx + rw + 23 or c["y1"] > ry + rh + 23):
            continue
        sel.append(c)
    if not sel:
        return None
    x0 = min(c["x0"] for c in sel)
    y0 = min(c["y0"] for c in sel)
    x1 = max(c["x1"] for c in sel)
    y1 = max(c["y1"] for c in sel)
    return (max(0, x0 - 2), max(0, y0 - 2), min(W - 1, x1 + 2) - max(0, x0 - 2) + 1,
            min(H - 1, y1 + 2) - max(0, y0 - 2) + 1)



def gap_to_neighbors(rect, others) -> dict:
    """四条边到最近邻居的距离（没有邻居就是 999）。"""
    rx, ry, rw, rh = rect
    left, right, top, bottom = 999, 999, 999, 999
    for (ox, oy, ow, oh) in others:
        if oy < ry + rh and oy + oh > ry:          # 纵向有重叠才构成左右邻居
            if ox + ow <= rx:
                left = min(left, rx - (ox + ow))
            elif ox >= rx + rw:
                right = min(right, ox - (rx + rw))
        if ox < rx + rw and ox + ow > rx:          # 横向有重叠才构成上下邻居
            if oy + oh <= ry:
                top = min(top, ry - (oy + oh))
            elif oy >= ry + rh:
                bottom = min(bottom, oy - (ry + rh))
    return {"L": left, "R": right, "T": top, "B": bottom}


def fit_window(px, alpha, rect, others, max_grow: int = 14) -> tuple[int, int, int, int]:
    """从手量框出发，把"被切断"的边一点点往外撑，直到四条边的边缘像素都不是亮面。

    "亮面"= 亮度 > 100 的不透明像素：家具表面被切开会长出这种像素，
    而描边/阴影（暗）不算。每轮只长 3px，并受两个上限约束：
      · max_grow（默认 14）
      · 与邻居的间距 − 1（长桌之间只有 16px，最多只能长 15，否则会吃到邻桌）
    """
    rx, ry, rw, rh = rect
    gaps = gap_to_neighbors(rect, others)
    grow = {"L": 0, "R": 0, "T": 0, "B": 0}

    for _ in range(12):
        x0 = max(0, rx - grow["L"])
        y0 = max(0, ry - grow["T"])
        x1 = min(W, rx + rw + grow["R"])
        y1 = min(H, ry + rh + grow["B"])
        need = []
        for side in ("L", "R", "T", "B"):
            pixels = []
            if side == "L":
                pixels = [(x0, y) for y in range(y0, y1)]
            elif side == "R":
                pixels = [(x1 - 1, y) for y in range(y0, y1)]
            elif side == "T":
                pixels = [(x, y0) for x in range(x0, x1)]
            else:
                pixels = [(x, y1 - 1) for x in range(x0, x1)]
            if any(alpha[y * W + x] and lum(px[x, y]) > 100 for x, y in pixels):
                need.append(side)
        if not need:
            break
        moved = False
        for side in need:
            limit = min(max_grow, max(0, gaps[side] - 1))
            if grow[side] + 3 <= limit:
                grow[side] += 3
                moved = True
        if not moved:
            break

    x0 = max(0, rx - grow["L"])
    y0 = max(0, ry - grow["T"])
    x1 = min(W, rx + rw + grow["R"])
    y1 = min(H, ry + rh + grow["B"])
    return (x0, y0, x1 - x0, y1 - y0)


def fill_holes(keep: bytearray, w: int, h: int) -> None:
    """只保留与窗口边界连通的透明区，被包住的小洞全部填实。"""
    seen = bytearray(w * h)
    q = deque()
    for xx in range(w):
        for yy in (0, h - 1):
            i = yy * w + xx
            if not keep[i] and not seen[i]:
                seen[i] = 1
                q.append(i)
    for yy in range(h):
        for xx in (0, w - 1):
            i = yy * w + xx
            if not keep[i] and not seen[i]:
                seen[i] = 1
                q.append(i)
    while q:
        i = q.popleft()
        cy, cx = divmod(i, w)
        for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                nb = ny * w + nx
                if not keep[nb] and not seen[nb]:
                    seen[nb] = 1
                    q.append(nb)
    for i in range(w * h):
        if not keep[i] and not seen[i]:
            keep[i] = 1


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".png"):
            os.remove(os.path.join(OUT, f))

    px, dark, label, floor_idx, floor_ref, near_dark = analyse(im)
    alpha = build_alpha(px, dark, label, floor_idx, floor_ref, near_dark)
    comps = structural_components(alpha)
    print(f"地板连通域 {floor_idx}，地板中位色 {floor_ref}，不透明 {sum(1 for a in alpha if a)} px，结构连通域 {len(comps)} 个")

    entries: list[dict] = []
    for n, item in enumerate(PROPS):
        slug, text, cx, cy, cw, ch = item[:6]
        bx0, by0, bw, bh = item[6] if len(item) > 6 else (cx, cy, cw, ch)
        bx1, by1 = bx0 + bw, by0 + bh

        keep = bytearray(bw * bh)
        for yy in range(by0, by1):
            for xx in range(bx0, bx1):
                keep[(yy - by0) * bw + (xx - bx0)] = 1 if alpha[yy * W + xx] else 0
        fill_holes(keep, bw, bh)

        sw, sh = bw, bh
        sx, sy = bx0, by0
        sprite = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        sp = sprite.load()
        filled = 0
        for yy in range(sh):
            for xx in range(sw):
                on = keep[yy * bw + xx]
                sp[xx, yy] = (*px[sx + xx, sy + yy], 255 if on else 0)
                filled += on

        name = f"prop_{n:02d}_{slug}"
        sprite.save(f"{OUT}/{name}.png")
        sprite.resize((sw * 2, sh * 2), Image.NEAREST).save(f"{OUT}/{name}_2x.png")

        wall = cy < WALL_TOP
        filled = sum(1 for yy in range(sh) for xx in range(sw) if sprite.getpixel((xx, yy))[3])
        entries.append({
            "name": name,
            "label": text,
            "file": f"res://assets/house/v4/objects/{name}.png",
            "sprite_rect": [sx, sy, sw, sh],
            "sort_y": sy if wall else sy + sh,
            "collision_rect": [cx, cy, cw, ch],
            "wall": wall,
            "coverage": round(filled / float(sw * sh), 3),
        })
        grew = ""
        if sx < cx or sy < cy or sx + sw > cx + cw or sy + sh > cy + ch:
            grew = "  ← 补齐 %d,%d,%d,%d" % (cx - sx, cy - sy, sx + sw - (cx + cw), sy + sh - (cy + ch))
        print(f"  {name:26s} {text:6s} 精灵 {sw:3d}x{sh:3d} @({sx},{sy})  "
              f"覆盖 {filled / (sw * sh):5.1%} {'贴墙' if wall else '地面'}{grew}")

    with open(f"{OUT}/props.json", "w", encoding="utf-8") as f:
        json.dump({"source": SRC, "size": [W, H], "props": entries}, f, ensure_ascii=False, indent=1)

    # 总览：原图 + 精灵取景框（青）+ 碰撞框（黄）
    sheet = im.copy()
    d = ImageDraw.Draw(sheet)
    for e in entries:
        rx, ry, rw, rh = e["sprite_rect"]
        d.rectangle([rx, ry, rx + rw - 1, ry + rh - 1], outline=(0, 255, 255))
        bx, by, bw, bh = e["collision_rect"]
        d.rectangle([bx, by, bx + bw - 1, by + bh - 1], outline=(255, 215, 0))
        d.text((rx + 2, ry + 1), e["name"][5:7], fill=(255, 255, 0))
    sheet.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/_preview_sheet.png")

    # 叠回原位：棋盘底
    check = Image.new("RGB", (W, H), (200, 200, 200))
    cd = ImageDraw.Draw(check)
    for cy_ in range(0, H, 8):
        for cx_ in range(0, W, 8):
            if ((cx_ // 8) + (cy_ // 8)) % 2 == 0:
                cd.rectangle([cx_, cy_, cx_ + 7, cy_ + 7], fill=(150, 150, 150))
    for e in entries:
        part = Image.open(f"{OUT}/{e['name']}.png")
        check.paste(part, (e["sprite_rect"][0], e["sprite_rect"][1]), part)
    check.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/_alpha_check.png")

    # 逐件对照表
    cols, cell_w, cell_h, pad, lab = 4, 430, 380, 10, 30
    rows = (len(entries) + cols - 1) // cols
    cs = Image.new("RGB", (cols * cell_w + pad, rows * cell_h + pad), (246, 243, 235))
    cdraw = ImageDraw.Draw(cs)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
    except OSError:
        font = ImageFont.load_default()
    for i, e in enumerate(entries):
        cell_x = pad + (i % cols) * cell_w
        cell_y = pad + (i // cols) * cell_h
        sw, sh = e["sprite_rect"][2], e["sprite_rect"][3]
        board = Image.new("RGB", (sw * 2, sh * 2), (205, 205, 205))
        bd = ImageDraw.Draw(board)
        for yy in range(0, sh * 2, 12):
            for xx in range(0, sw * 2, 12):
                if ((xx // 12) + (yy // 12)) % 2 == 0:
                    bd.rectangle([xx, yy, xx + 11, yy + 11], fill=(160, 160, 160))
        part = Image.open(f"{OUT}/{e['name']}.png").resize((sw * 2, sh * 2), Image.NEAREST)
        board.paste(part, (0, 0), part)
        cs.paste(board, (cell_x, cell_y + lab))
        tag = "%02d %s  %dx%d%s" % (int(e["name"][5:7]), e["label"], sw, sh, "  [贴墙]" if e["wall"] else "")
        cdraw.text((cell_x, cell_y + 6), tag, fill=(40, 36, 30), font=font)
        cdraw.rectangle([cell_x, cell_y + lab, cell_x + sw * 2 - 1, cell_y + lab + sh * 2 - 1],
                        outline=(120, 120, 120))
    cs.save(f"{OUT}/_contact_sheet.png")

    print(f"共 {len(entries)} 件 → {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
