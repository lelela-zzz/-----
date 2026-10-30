#!/usr/bin/env python3
"""把场景里的桌椅拆成独立对象（精灵），并输出干净底图与分离总表。

方法（v2）：
1. 在**白天图**上分割（明暗差更大），颜色从**夜晚 v6**取 → 物件带夜晚观感
2. 暗轮廓 D（Y<60）→ 多地板种子洪水填充 → 轮廓内部 = 各物件的"肉"
3. **对内部做连通域**：描边天然是分隔线，所以长桌/长凳/椅各自独立
4. 描边区按"最近内部"归属（只在 D 上传播，不跨内部）→ 每件带回自己的描边
5. 过滤：只留餐饮区（y0>=160）、剔除墙面/薄片/超大件；按尺寸分类
6. 导出精灵（RGBA）+ 干净底图（同列上下取地板色回填）+ 分离总表（2×、带间距与标签）

用法：python tools/separate_furniture.py
"""
from __future__ import annotations

import os
from collections import deque
from PIL import Image, ImageDraw, ImageFont

DAY = "assets/house/v4/scene_day_1x.png"
NIGHT = "assets/house/v4/scene_night_v6_1x.png"
OUT = "assets/house/v4/furniture"
SHEET = "assets/house/v4/furniture_sheet.png"
CLEAN = "assets/house/v4/scene_night_v6_clean_bg.png"
RECOMP = "assets/house/v4/scene_night_v6_recomposed.png"
W, H = 640, 384
THR = 60
MIN_AREA = 150


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".png"):
            os.remove(os.path.join(OUT, f))

    day = Image.open(DAY).convert("RGB"); dp = day.load()
    night = Image.open(NIGHT).convert("RGB"); npx = night.load()

    # 1) 暗轮廓
    D = bytearray(W * H)
    for y in range(H):
        row = y * W
        for x in range(W):
            r, g, b = dp[x, y]
            if 0.299 * r + 0.587 * g + 0.114 * b < THR:
                D[row + x] = 1

    # 2) 洪水填充（地板种子，避开各家具内部）
    visited = bytearray(W * H)
    dq = deque()
    seeds = [(300, 350), (60, 220), (600, 120), (150, 300), (450, 330),
             (520, 60), (80, 60), (620, 250), (420, 300), (560, 200),
             (500, 280), (390, 300), (250, 350), (100, 350), (610, 350)]
    for (sx, sy) in seeds:
        i = sy * W + sx
        if not D[i] and not visited[i]:
            visited[i] = 1; dq.append(i)
    while dq:
        i = dq.popleft(); x = i % W; y = i // W
        for k in ((i - 1) if x > 0 else -1, (i + 1) if x < W - 1 else -1,
                  (i - W) if y > 0 else -1, (i + W) if y < H - 1 else -1):
            if k >= 0 and not visited[k] and not D[k]:
                visited[k] = 1; dq.append(k)

    interior = bytearray(W * H)
    for i in range(W * H):
        if not visited[i] and not D[i]:
            interior[i] = 1

    # 3) 内部连通域
    lab = [-1] * (W * H)
    comps = []
    for i in range(W * H):
        if interior[i] and lab[i] < 0:
            lid = len(comps)
            lab[i] = lid; q = deque([i]); pts = []
            while q:
                j = q.popleft(); pts.append(j); x = j % W; y = j // W
                for k in ((j - 1) if x > 0 else -1, (j + 1) if x < W - 1 else -1,
                          (j - W) if y > 0 else -1, (j + W) if y < H - 1 else -1):
                    if k >= 0 and interior[k] and lab[k] < 0:
                        lab[k] = lid; q.append(k)
            comps.append(pts)

    # 4) 过滤 + 分类
    def bbox_of(pts):
        xs = [p % W for p in pts]; ys = [p // W for p in pts]
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    keep = []
    for lid, pts in enumerate(comps):
        if len(pts) < MIN_AREA:
            continue
        x0, y0, x1, y1 = bbox_of(pts)
        w = x1 - x0; h = y1 - y0
        if y0 < 150:                       # 餐饮区以下（剔除后墙/窗/背柜/吧台/酒桶带）
            continue
        if w < 9 or h < 7:                 # 薄片（地板缝）
            continue
        if w > 105 or h > 62 or len(pts) > 4200:
            continue
        if x0 >= 560 and y0 >= 290:
            kind = "木箱/杂物"
        elif w >= 75 and h >= 26:
            kind = "长桌"
        elif w >= 52 and h <= 17:
            kind = "长凳"
        elif 26 <= w <= 62 and 20 <= h <= 48:
            kind = "散座桌"
        elif w < 32 and h >= 16:
            kind = "椅子"
        else:
            kind = "物件"
        keep.append(dict(lid=lid, pts=pts, bbox=(x0, y0, x1, y1), area=len(pts),
                         kind=kind, w=w, h=h))

    # 5) 在 (内部∪描边) 上做多源 BFS：每个内部当种子，各自吃下最近的描边
    objmask = bytearray(W * H)
    for i in range(W * H):
        if interior[i] or D[i]:
            objmask[i] = 1
    own = [-1] * (W * H)
    q = deque()
    for lid, pts in enumerate(comps):
        for i in pts:
            own[i] = lid
            q.append(i)
    while q:
        j = q.popleft(); x = j % W; y = j // W
        for k in ((j - 1) if x > 0 else -1, (j + 1) if x < W - 1 else -1,
                  (j - W) if y > 0 else -1, (j + W) if y < H - 1 else -1):
            if k >= 0 and objmask[k] and own[k] < 0:
                own[k] = own[j]; q.append(k)

    # 6) 合并描边到对象（并重算 bbox）
    by_lid = {o["lid"]: o for o in keep}
    for o in keep:
        o["all"] = list(o["pts"])
    for i in range(W * H):
        lb = own[i]
        if lb >= 0:
            o = by_lid.get(lb)
            if o is not None:
                o["all"].append(i)
    for o in keep:
        # bbox 内的深色像素也归该对象（椅子本体几乎全是深色，否则会缺腿/缺座）
        x0, y0, x1, y1 = o["bbox"]
        got = set(o["all"])
        for y in range(y0, y1):
            row = y * W
            for x in range(x0, x1):
                i = row + x
                if D[i]:
                    got.add(i)
        o["all"] = list(got)
        x0, y0, x1, y1 = bbox_of(o["all"])
        o["bbox"] = (x0, y0, x1, y1)
        o["w"] = x1 - x0; o["h"] = y1 - y0
        o["area"] = len(o["all"])

    keep.sort(key=lambda o: (o["bbox"][1] // 44, o["bbox"][0]))
    print(f"检出对象 {len(keep)} 个")

    # 7) 导出精灵
    for k, o in enumerate(keep):
        x0, y0, x1, y1 = o["bbox"]
        spr = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
        sp = spr.load()
        for i in o["all"]:
            x = i % W; y = i // W
            if x0 <= x < x1 and y0 <= y < y1:
                sp[x - x0, y - y0] = npx[x, y] + (255,)
        o["idx"] = k + 1
        o["file"] = f"{OUT}/obj_{k+1:02d}.png"
        spr.save(o["file"])

    # 导出元数据（供 cutout_smooth.py 新旧按 bbox 匹配对比）
    import json
    meta = {str(o["idx"]): {"kind": o["kind"], "bbox": list(o["bbox"])} for o in keep}
    with open(f"{OUT}/old_meta.json", "w", encoding="utf-8") as fj:
        json.dump(meta, fj, ensure_ascii=False, indent=1)

    alpha_all = bytearray(W * H)
    for o in keep:
        for i in o["all"]:
            alpha_all[i] = 1

    # 8) 干净底图（纵向取同列地板色，木地板是竖板不破坏纹理）
    clean = night.copy(); cp = clean.load()
    for y in range(H):
        for x in range(W):
            i = y * W + x
            if not alpha_all[i]:
                continue
            src = None
            for d in range(3, 46):
                yy = y - d
                if yy >= 0 and not alpha_all[yy * W + x]:
                    src = cp[x, yy]; break
            if src is None:
                for d in range(3, 46):
                    yy = y + d
                    if yy < H and not alpha_all[yy * W + x]:
                        src = cp[x, yy]; break
            if src is not None:
                cp[x, y] = src
    clean.save(CLEAN)
    print(f"干净底图 → {CLEAN}")

    # 9) 重组合成（验证抠图无损）
    recomp = clean.copy()
    for o in keep:
        spr = Image.open(o["file"]).convert("RGBA")
        recomp.paste(spr, (o["bbox"][0], o["bbox"][1]), spr)
    recomp.save(RECOMP)
    print(f"重组合成 → {RECOMP}")

    # 10) 分离总表
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 13)
    except OSError:
        font = ImageFont.load_default()
    maxw = max(o["w"] for o in keep) * 2
    maxh = max(o["h"] for o in keep) * 2
    cell_w = max(130, maxw + 18)
    cell_h = max(80, maxh + 30)
    cols = max(3, min(6, 1700 // (cell_w + 10)))
    rows = (len(keep) + cols - 1) // cols
    pad = 10
    Ws, Hs = cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad + 28
    sheet = Image.new("RGB", (Ws, Hs), (34, 32, 38))
    sd = ImageDraw.Draw(sheet)
    sd.text((pad, 6), f"炉火镇 · 桌椅分离总表（{len(keep)} 件 · 2× 放大 · 单元间距 {pad}px）",
            fill=(238, 232, 220), font=font)
    for k, o in enumerate(keep):
        spr = Image.open(o["file"]).convert("RGBA")
        spr = spr.resize((spr.width * 2, spr.height * 2), Image.NEAREST)
        cx = pad + (k % cols) * (cell_w + pad)
        cy = 28 + pad + (k // cols) * (cell_h + pad)
        sd.rectangle([cx, cy, cx + cell_w - 1, cy + cell_h - 1],
                     fill=(50, 47, 56) if (k // cols + k) % 2 == 0 else (44, 42, 50))
        sx = cx + (cell_w - spr.width) // 2
        sy = cy + (cell_h - 16 - spr.height) // 2 + 5
        sheet.paste(spr, (sx, sy), spr)
        sd.text((cx + 4, cy + cell_h - 14), f"#{o['idx']:02d} {o['kind']}",
                fill=(198, 194, 188), font=font)
    sheet.save(SHEET)
    print(f"总表 → {SHEET}")

    print("\n对象清单：")
    for o in keep:
        x0, y0, x1, y1 = o["bbox"]
        print(f"  #{o['idx']:02d} {o['kind']:4s} ({x0:3d},{y0:3d})-({x1:3d},{y1:3d}) "
              f"{o['w']:3d}×{o['h']:2d} area={o['area']:4d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
