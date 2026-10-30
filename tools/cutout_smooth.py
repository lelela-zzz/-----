#!/usr/bin/env python3
"""平滑抠图 v2 —— 在高清母版上重新抠图（替换 obj_01..21 的坑洼边缘版本）。

旧版坑洼根因：在 640×384（NEAREST 降采样、无抗锯齿）上做 Y<60 硬阈值二值掩膜，
边缘只能是像素台阶；2x 又是 NEAREST 放大，锯齿原样保留。

本版思路：
1. 直接在 1448×935 高清母版 scene_day_clean.png（自带真实抗锯齿）上分割：
   暗轮廓更粗更连续，洪泛/连通域/描边归属与旧版同构，全部尺寸参数按缩放比换算
2. 软边 alpha：物体实心区 alpha=255（区域完整、不缺块）；边界带（外扩 3px）
   用"颜色解混"求部分覆盖度 alpha = d_bg/(d_fg+d_bg)，天然还原母版自带的抗锯齿
3. 1x 精灵 = 高清 alpha 用 BOX 面积平均聚合回 640×384（台阶被平均成平滑过渡）
4. 颜色仍取夜晚 v6（与旧版观感一致）；半透明边像素用 clean_bg 做"反解混"
   c' = (c - (1-a)·bg)/a，去掉地板色串扰 → 任意背景合成都不出暗边/亮边
5. 数学性质：a·c' + (1-a)·bg = c，重组合成可精确复原原图（自校验）

输出：
  furniture/obj_NN.png       1x 游戏用（边缘平滑）
  furniture/obj_NN_2x.png    2x（NEAREST，项目规范）
  furniture/obj_NN_hd.png    高清存档（白天色 + 软边 alpha，后续可用于高清换光）
  furniture_sheet.png / scene_night_v6_clean_bg.png / scene_night_v6_recomposed.png
  cutout_compare.png         新旧边缘对比（棋盘格底、放大）

用法：python tools/cutout_smooth.py
"""
from __future__ import annotations

import math
import os
import shutil
from collections import deque
from statistics import median

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CLEAN = "assets/house/v4/scene_day_clean.png"     # 1448×935 母版（真实抗锯齿）
NIGHT = "assets/house/v4/scene_night_v6_1x.png"   # 1x 夜晚色来源
OUT = "assets/house/v4/furniture"
SHEET = "assets/house/v4/furniture_sheet.png"
CLEAN_BG = "assets/house/v4/scene_night_v6_clean_bg.png"
RECOMP = "assets/house/v4/scene_night_v6_recomposed.png"
COMPARE = "assets/house/v4/cutout_compare.png"

CW, CH = 1448, 935
W, H = 640, 384
SX, SY = CW / W, CH / H
S = (SX + SY) / 2
THR = 60                       # 暗轮廓阈值（亮度），与旧版一致
MIN_AREA = int(150 * SX * SY)  # ≈826
BAND = 3                       # 软边外扩（高清 px）
PAD = 16                       # 分割窗口外扩（高清 px）


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def cdist(c, ref):
    return math.sqrt((c[0] - ref[0]) ** 2 + (c[1] - ref[1]) ** 2 + (c[2] - ref[2]) ** 2)


def med_color(pixels, px):
    """像素索引列表的中位色。"""
    if not pixels:
        return None
    rs = sorted(px[i % CW, i // CW][0] for i in pixels)
    gs = sorted(px[i % CW, i // CW][1] for i in pixels)
    bs = sorted(px[i % CW, i // CW][2] for i in pixels)
    n = len(pixels)
    return (rs[n // 2], gs[n // 2], bs[n // 2])


def main():
    os.makedirs(OUT, exist_ok=True)

    # 0) 备份旧精灵用于新旧对比（prev_XX.png），再清空旧产物
    have_prev = os.path.exists(f"{OUT}/obj_01.png")
    print(f"旧精灵备份：{'有' if have_prev else '无（跳过新旧对比）'}")
    if have_prev:
        for f in sorted(os.listdir(OUT)):
            if f.startswith("obj_") and f.endswith(".png"):
                shutil.copy(f"{OUT}/{f}", f"{OUT}/prev_{f}")
    for f in os.listdir(OUT):
        if f.endswith(".png") and not f.startswith("prev_"):
            os.remove(os.path.join(OUT, f))

    clean = Image.open(CLEAN).convert("RGB")
    cp = clean.load()
    night = Image.open(NIGHT).convert("RGB")
    npx = night.load()

    # ---- 1) 高清暗轮廓 ----
    N = CW * CH
    D = bytearray(N)
    for y in range(CH):
        row = y * CW
        for x in range(CW):
            r, g, b = cp[x, y]
            if 0.299 * r + 0.587 * g + 0.114 * b < THR:
                D[row + x] = 1

    # ---- 2) 地板洪泛（种子坐标按缩放比映射）----
    visited = bytearray(N)
    dq = deque()
    seeds1x = [(300, 350), (60, 220), (600, 120), (150, 300), (450, 330),
               (520, 60), (80, 60), (620, 250), (420, 300), (560, 200),
               (500, 280), (390, 300), (250, 350), (100, 350), (610, 350)]
    for (sx1, sy1) in seeds1x:
        i = int(sy1 * SY) * CW + int(sx1 * SX)
        if not D[i] and not visited[i]:
            visited[i] = 1
            dq.append(i)
    while dq:
        i = dq.popleft()
        x = i % CW
        y = i // CW
        for k in ((i - 1) if x > 0 else -1, (i + 1) if x < CW - 1 else -1,
                  (i - CW) if y > 0 else -1, (i + CW) if y < CH - 1 else -1):
            if k >= 0 and not visited[k] and not D[k]:
                visited[k] = 1
                dq.append(k)
    interior = bytearray(N)
    for i in range(N):
        if not visited[i] and not D[i]:
            interior[i] = 1

    # ---- 3) 内部连通域 ----
    lab = [-1] * N
    comps = []
    for i0 in range(N):
        if interior[i0] and lab[i0] < 0:
            lid = len(comps)
            lab[i0] = lid
            q = deque([i0])
            pts = []
            while q:
                j = q.popleft()
                pts.append(j)
                x = j % CW
                y = j // CW
                for k in ((j - 1) if x > 0 else -1, (j + 1) if x < CW - 1 else -1,
                          (j - CW) if y > 0 else -1, (j + CW) if y < CH - 1 else -1):
                    if k >= 0 and interior[k] and lab[k] < 0:
                        lab[k] = lid
                        q.append(k)
            comps.append(pts)

    def bbox_of(pts):
        xs = [p % CW for p in pts]
        ys = [p // CW for p in pts]
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    # ---- 4) 过滤 + 分类（阈值全部按缩放比换算）----
    keep = []
    for lid, pts in enumerate(comps):
        if len(pts) < MIN_AREA:
            continue
        x0, y0, x1, y1 = bbox_of(pts)
        w, h = x1 - x0, y1 - y0
        if y0 < 150 * SY:
            continue
        if w < 9 * SX or h < 7 * SY:
            continue
        if w > 105 * SX or h > 62 * SY or len(pts) > 4200 * SX * SY:
            continue
        if x0 >= 560 * SX and y0 >= 290 * SY:
            kind = "木箱/杂物"
        elif w >= 75 * S and h >= 26 * S:
            kind = "长桌"
        elif w >= 52 * S and h <= 17 * S:
            kind = "长凳"
        elif 26 * S <= w <= 62 * S and 20 * S <= h <= 48 * S:
            kind = "散座桌"
        elif w < 32 * S and h >= 16 * S:
            kind = "椅子"
        else:
            kind = "物件"
        keep.append(dict(lid=lid, pts=pts, bbox=(x0, y0, x1, y1),
                         area=len(pts), kind=kind, w=w, h=h))

    # ---- 5) 描边归属：所有内部当种子的多源 BFS（含被剔除件，防污染）----
    objmask = bytearray(N)
    for i in range(N):
        if interior[i] or D[i]:
            objmask[i] = 1
    own = [-1] * N
    q = deque()
    for lid, pts in enumerate(comps):
        for i in pts:
            own[i] = lid
            q.append(i)
    while q:
        j = q.popleft()
        x = j % CW
        y = j // CW
        for k in ((j - 1) if x > 0 else -1, (j + 1) if x < CW - 1 else -1,
                  (j - CW) if y > 0 else -1, (j + CW) if y < CH - 1 else -1):
            if k >= 0 and objmask[k] and own[k] < 0:
                own[k] = own[j]
                q.append(k)

    # ---- 6) 合并描边 + bbox 深色像素补全（椅子几乎全是深色）----
    by_lid = {o["lid"]: o for o in keep}
    for o in keep:
        o["all"] = list(o["pts"])
    for i in range(N):
        lb = own[i]
        if lb >= 0:
            o = by_lid.get(lb)
            if o is not None:
                o["all"].append(i)
    for o in keep:
        x0, y0, x1, y1 = o["bbox"]
        got = set(o["all"])
        for y in range(y0, y1):
            row = y * CW
            for x in range(x0, x1):
                i = row + x
                if D[i]:
                    got.add(i)
        o["all"] = list(got)
        x0, y0, x1, y1 = bbox_of(o["all"])
        o["bbox"] = (x0, y0, x1, y1)
        o["w"] = x1 - x0
        o["h"] = y1 - y0
        o["area"] = len(o["all"])

    keep.sort(key=lambda o: (int(o["bbox"][1] // (44 * SY)), o["bbox"][0]))
    kinds = {}
    for o in keep:
        kinds[o["kind"]] = kinds.get(o["kind"], 0) + 1
    print(f"检出对象 {len(keep)} 个：{kinds}")

    # ---- 7) 软边 alpha（高清）----
    for k, o in enumerate(keep):
        o["idx"] = k + 1
        x0, y0, x1, y1 = o["bbox"]
        wx0, wy0 = max(0, x0 - PAD), max(0, y0 - PAD)
        wx1, wy1 = min(CW, x1 + PAD), min(CH, y1 + PAD)
        o["win"] = (wx0, wy0, wx1, wy1)
        ww, wh = wx1 - wx0, wy1 - wy0

        m = Image.new("L", (ww, wh), 0)
        mp = m.load()
        for i in o["all"]:
            x = i % CW
            y = i // CW
            if wx0 <= x < wx1 and wy0 <= y < wy1:
                mp[x - wx0, y - wy0] = 255

        er3 = m.filter(ImageFilter.MinFilter(7))    # 腐蚀 3：实心核心
        di2 = m.filter(ImageFilter.MaxFilter(5))    # 膨胀 2
        di5 = m.filter(ImageFilter.MaxFilter(11))   # 膨胀 5：外环
        er3p, di2p, di5p = er3.load(), di2.load(), di5.load()

        # fg 参考色：区域边界带（m - er3）中位色；退化时用全域
        bpts = []
        for yy in range(wh):
            for xx in range(ww):
                if mp[xx, yy] and not er3p[xx, yy]:
                    bpts.append((wy0 + yy) * CW + (wx0 + xx))
        fg = med_color(bpts, cp) or med_color(list(o["all"]), cp)
        # bg 参考色：外环（di5-di2）中亮度 >= THR 的地板中位色
        gpts = []
        for yy in range(wh):
            for xx in range(ww):
                if di5p[xx, yy] and not di2p[xx, yy]:
                    i = (wy0 + yy) * CW + (wx0 + xx)
                    if lum(cp[i % CW, i // CW]) >= THR:
                        gpts.append(i)
        if len(gpts) < 20:
            gpts = []
            for yy in range(wh):
                for xx in range(ww):
                    if di5p[xx, yy] and not di2p[xx, yy]:
                        gpts.append((wy0 + yy) * CW + (wx0 + xx))
        bg = med_color(gpts, cp) or fg

        a = Image.new("L", (ww, wh), 0)
        ap = a.load()
        for yy in range(wh):
            for xx in range(ww):
                if mp[xx, yy]:
                    ap[xx, yy] = 255        # 实心区不透明，保证不缺块
                elif di2p[xx, yy]:
                    c = cp[wx0 + xx, wy0 + yy]
                    dfg = cdist(c, fg)
                    dbg = cdist(c, bg)
                    ap[xx, yy] = int(round(255 * dbg / (dfg + dbg))) if dfg + dbg > 1e-6 else 0

        o["alpha"] = a
        o["win"] = (wx0, wy0, wx1, wy1)

        # 高清存档（白天色 + 软边）
        spr_hd = Image.new("RGBA", (ww, wh), (0, 0, 0, 0))
        hp = spr_hd.load()
        for yy in range(wh):
            for xx in range(ww):
                av = ap[xx, yy]
                if av:
                    hp[xx, yy] = cp[wx0 + xx, wy0 + yy] + (av,)
        spr_hd.save(f"{OUT}/obj_{o['idx']:02d}_hd.png")

    # ---- 8) 高清 alpha 聚合回 1x（BOX 面积平均 → 台阶变平滑过渡）----
    alpha_hd = Image.new("L", (CW, CH), 0)
    for o in keep:
        wx0, wy0, wx1, wy1 = o["win"]
        alpha_hd.paste(o["alpha"], (wx0, wy0))
    alpha_1x = alpha_hd.resize((W, H), Image.BOX)
    a1p = alpha_1x.load()

    # ---- 9) 干净底图（a<8 视为背景，纵向取地板色回填）----
    clean_bg = night.copy()
    cbp = clean_bg.load()
    is_bg = bytearray(W * H)
    for y in range(H):
        for x in range(W):
            if a1p[x, y] < 8:
                is_bg[y * W + x] = 1
    for y in range(H):
        for x in range(W):
            if is_bg[y * W + x]:
                continue
            src = None
            for d in range(3, 60):
                yy = y - d
                if yy >= 0 and is_bg[yy * W + x]:
                    src = cbp[x, yy]
                    break
            if src is None:
                for d in range(3, 60):
                    yy = y + d
                    if yy < H and is_bg[yy * W + x]:
                        src = cbp[x, yy]
                        break
            if src is not None:
                cbp[x, y] = src
    clean_bg.save(CLEAN_BG)
    print(f"干净底图 → {CLEAN_BG}")

    # ---- 10) 1x 精灵（夜晚色 + 边缘反解混去地板串扰）----
    for o in keep:
        x0, y0, x1, y1 = o["bbox"]
        rx0 = max(0, int(x0 / SX) - 2)
        ry0 = max(0, int(y0 / SY) - 2)
        rx1 = min(W, int(math.ceil(x1 / SX)) + 2)
        ry1 = min(H, int(math.ceil(y1 / SY)) + 2)
        # 收缩到有内容的最小框
        bx0, by0, bx1, by1 = rx1, ry1, rx0, ry0
        for y in range(ry0, ry1):
            for x in range(rx0, rx1):
                if a1p[x, y] > 2:
                    bx0 = min(bx0, x); by0 = min(by0, y)
                    bx1 = max(bx1, x + 1); by1 = max(by1, y + 1)
        o["bbox1x"] = (bx0, by0, bx1, by1)
        spr = Image.new("RGBA", (bx1 - bx0, by1 - by0), (0, 0, 0, 0))
        sp = spr.load()
        for y in range(by0, by1):
            for x in range(bx0, bx1):
                av = a1p[x, y]
                if av == 0:
                    continue
                r, g, b = npx[x, y]
                if 8 < av < 250:
                    t = av / 255.0
                    br, bgc, bb = cbp[x, y]
                    r = min(255, max(0, int(round((r - (1 - t) * br) / t))))
                    g = min(255, max(0, int(round((g - (1 - t) * bgc) / t))))
                    b = min(255, max(0, int(round((b - (1 - t) * bb) / t))))
                sp[x - bx0, y - by0] = (r, g, b, av)
        o["file"] = f"{OUT}/obj_{o['idx']:02d}.png"
        spr.save(o["file"])
        spr.resize((spr.width * 2, spr.height * 2), Image.NEAREST).save(
            f"{OUT}/obj_{o['idx']:02d}_2x.png")
        o["w1x"] = bx1 - bx0
        o["h1x"] = by1 - by0

    # ---- 11) 导出 1x 坐标元数据（供 relayout.py 重排家具）----
    import json
    meta = {str(o["idx"]): {"kind": o["kind"], "bbox": list(o["bbox1x"])} for o in keep}
    with open(f"{OUT}/obj_meta.json", "w", encoding="utf-8") as fj:
        json.dump(meta, fj, ensure_ascii=False, indent=1)
    print(f"坐标元数据 → {OUT}/obj_meta.json")

    # ---- 11b) 重组合成（数学自校验：应 ≈ 原夜晚图）----
    recomp = clean_bg.copy()
    for o in keep:
        spr = Image.open(o["file"]).convert("RGBA")
        recomp.paste(spr, o["bbox1x"][:2], spr)
    recomp.save(RECOMP)
    diff_sum = diff_max = 0
    npx2 = recomp.load()
    for y in range(H):
        for x in range(W):
            d = sum(abs(a - b) for a, b in zip(npx[x, y], npx2[x, y]))
            diff_sum += d
            diff_max = max(diff_max, d)
    print(f"重组合成 → {RECOMP}（与原图平均偏差 {diff_sum / (W * H * 3):.3f} /255，"
          f"单通道最大 {diff_max // 3}）")

    # ---- 12) 分离总表 ----
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 13)
    except OSError:
        font = ImageFont.load_default()
    maxw = max(o["w1x"] for o in keep) * 2
    maxh = max(o["h1x"] for o in keep) * 2
    cell_w = max(130, maxw + 18)
    cell_h = max(80, maxh + 30)
    cols = max(3, min(6, 1700 // (cell_w + 10)))
    rows = (len(keep) + cols - 1) // cols
    pad = 10
    Ws, Hs = cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad + 28
    sheet = Image.new("RGB", (Ws, Hs), (34, 32, 38))
    sd = ImageDraw.Draw(sheet)
    sd.text((pad, 6), f"炉火镇 · 桌椅分离总表（{len(keep)} 件 · 高清软边抠图 · 2× 放大）",
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

    # ---- 13) 新旧边缘对比（棋盘格底、5× 放大；按 bbox IoU 匹配新旧同一件）----
    if have_prev:
        old_meta = None
        meta_path = f"{OUT}/old_meta.json"
        if os.path.exists(meta_path):
            import json
            with open(meta_path, encoding="utf-8") as fh:
                old_meta = {int(k): v for k, v in json.load(fh).items()}

        def iou(a, b):
            ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
            iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
            inter = ix * iy
            ua = ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter)
            return inter / ua if ua else 0.0

        rep_kind = ["长桌", "长凳", "散座桌", "椅子", "木箱/杂物"]
        picks = []
        for kd in rep_kind:
            for o in keep:
                if o["kind"] == kd:
                    picks.append(o)
                    break
        Z = 5
        cells = []
        for o in picks:
            newp = f"{OUT}/obj_{o['idx']:02d}.png"
            oldp, tag = None, ""
            if old_meta:
                best, bi = 0.0, None
                for oi, mv in old_meta.items():
                    t = iou(o["bbox1x"], tuple(mv["bbox"]))
                    if t > best:
                        best, bi = t, oi
                if bi is not None and best > 0.25:
                    oldp = f"{OUT}/prev_obj_{bi:02d}.png"
                    tag = f"（旧#{bi:02d}）"
            if oldp is None or not os.path.exists(oldp):
                continue
            pair = []
            for p in (oldp, newp):
                if os.path.exists(p):
                    s2 = Image.open(p).convert("RGBA")
                    s2 = s2.resize((s2.width * Z, s2.height * Z), Image.NEAREST)
                    bgim = Image.new("RGB", (s2.width, s2.height))
                    bp = bgim.load()
                    for yy in range(s2.height):
                        for xx in range(s2.width):
                            bp[xx, yy] = (122, 122, 130) if ((xx // 10 + yy // 10) % 2 == 0) else (88, 88, 96)
                    bgim.paste(s2, (0, 0), s2)
                    pair.append(bgim)
            if len(pair) == 2:
                cells.append((o, pair))
        if cells:
            cw2 = max(max(p.width for p in c[1]) for c in cells) + 24
            ch2 = max(max(p.height for p in c[1]) for c in cells) + 40
            cw2 = max(cw2, 260)
            Wc, Hc = cw2 * 2 + 30, (ch2 + 14) * len(cells) + 44
            comp = Image.new("RGB", (Wc, Hc), (28, 26, 32))
            cd = ImageDraw.Draw(comp)
            try:
                sd2 = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 15)
            except OSError:
                sd2 = font
            cd.text((14, 10), "抠图边缘对比 · 左：旧（1x 硬阈值，坑洼）  右：新（高清软边）· 5× 棋盘格底",
                    fill=(238, 232, 220), font=sd2)
            for r, (o, pair) in enumerate(cells):
                ty = 40 + r * (ch2 + 14)
                cd.text((14, ty), f"#{o['idx']:02d} {o['kind']}{tag}", fill=(180, 176, 170), font=font)
                for c, im in enumerate(pair):
                    x = 14 + c * (cw2 + 2)
                    comp.paste(im, (x + (cw2 - 24 - im.width) // 2, ty + 18))
            comp.save(COMPARE)
            print(f"新旧对比 → {COMPARE}")
        # 清理备份
        for f in os.listdir(OUT):
            if f.startswith("prev_"):
                os.remove(os.path.join(OUT, f))

    # ---- 清单 ----
    print("\n对象清单（1x）：")
    for o in keep:
        bx0, by0, bx1, by1 = o["bbox1x"]
        print(f"  #{o['idx']:02d} {o['kind']:4s} ({bx0:3d},{by0:3d})-({bx1:3d},{by1:3d}) "
              f"{o['w1x']:3d}×{o['h1x']:2d} hd_area={o['area']:5d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
