#!/usr/bin/env python3
"""布局重排 + 底图清理 → 新白天地图（scene_day_v2_1x.png）。

三件事：
1. **移除左侧来源不明的软阴影**：左区（x0-150）地板低中频亮度向基准值拉平，
   强度 0.75，保留板缝（L<52 的深色缝不动）与家具接触阴影（精灵 alpha 外扩 3px 保护）
2. **去掉窗户射入的光斑**：两扇窗下方地板的暖亮梯形区域同样做亮度拉平
3. **右侧重排**：右底角木箱堆（含 #18/#21）与楼梯落地口的 #08 椅子清走，
   按竖板纹理纵向镜像补洞（同列上下取最近的"干净地板"循环填充，板缝 x 相位天然对齐），
   再把三件家具按新坐标放回不挡通道的位置

为什么不在 AI 里重生成：relight v6 的光源是对壁炉/窗口坐标硬编码的（HEARTH/WINDOWS），
重生成会漂移坐标、破坏光照系统。本脚本只动几何与低频亮度，光源系统完全不动。

用法：python tools/relayout.py
"""
from __future__ import annotations

import json
import os
import statistics

from PIL import Image, ImageDraw, ImageFilter, ImageFont

DAY = "assets/house/v4/scene_day_1x.png"
META = "assets/house/v4/furniture/obj_meta.json"
OUTDIR = "assets/house/v4/furniture"
OUT1X = "assets/house/v4/scene_day_v2_1x.png"
OUT2X = "assets/house/v4/scene_day_v2_2x.png"
COMPARE = "assets/house/v4/scene_layout_before_after.png"
W, H = 640, 384

# ---- 家具重排（idx -> 新左上角）----
MOVE = {
    8: (432, 198),    # 椅子：楼梯落地口 → 圆桌右侧空位
    18: (36, 320),    # 木箱：右底角 → 左下空角（新待整理位）
    21: (500, 294),   # 椅子：木箱堆旁 → #13 桌旁空位
}
PILE_RECT = (548, 272, 634, 372)   # 右底角木箱堆（含 #18 #21 原位）

# ---- 亮度拉平区域（左阴影 + 两处窗光 + 右底角补洞区）----
FLAT_REGIONS = [(0, 62, 150, 362), (140, 58, 300, 120), (335, 58, 505, 120), (540, 262, 638, 375)]
FLAT_STRENGTH = 0.75
FLAT_LO, FLAT_HI = 52, 210         # 只处理地板中调，深色板缝/高光不动
GAIN_MIN, GAIN_MAX = 0.72, 1.40

# ---- 保护矩形（吧台/酒桶/楼梯/门洞，不做亮度拉平、也不作为补洞来源）----
PROTECT_RECTS = [(0, 92, 338, 150), (415, 78, 545, 158), (582, 96, 640, 196), (255, 340, 345, 384)]


def rect_set(m, x0, y0, x1, y1, val=1):
    x0 = max(0, x0); y0 = max(0, y0); x1 = min(W, x1); y1 = min(H, y1)
    for y in range(y0, y1):
        row = y * W
        for x in range(x0, x1):
            m[row + x] = val


def main():
    meta = json.load(open(META, encoding="utf-8"))
    day = Image.open(DAY).convert("RGB")
    px = day.load()

    # ---- 0) 提取被移动家具的白天色 RGBA（必须在补洞前取原像素）----
    moved = {}
    for idx, (nx0, ny0) in MOVE.items():
        info = meta[str(idx)]
        bx0, by0, bx1, by1 = info["bbox"]
        spr = Image.open(f"{OUTDIR}/obj_{idx:02d}.png").convert("RGBA")
        a = spr.getchannel("A")
        rgb = day.crop((bx0, by0, bx1, by1))
        m = Image.new("RGBA", rgb.size, (0, 0, 0, 0))
        m.paste(rgb, (0, 0), a)
        moved[idx] = dict(rgba=m, alpha=a, obbox=(bx0, by0, bx1, by1),
                          npos=(nx0, ny0), kind=info["kind"])
        print(f"  取出 #{idx:02d} {info['kind']} {bx1-bx0}×{by1-by0} → 新位 ({nx0},{ny0})")

    # ---- 1) 构建掩膜 ----
    FILL = bytearray(W * H)     # 需要补洞的像素
    EXCL = bytearray(W * H)     # 不可作为补洞来源的像素（家具/墙体/建筑）

    for idx, mv in moved.items():
        a = mv["alpha"]; bx0, by0, bx1, by1 = mv["obbox"]
        ap = a.load()
        for y in range(by0, by1):
            row = y * W
            for x in range(bx0, bx1):
                if ap[x - bx0, y - by0] > 0:
                    FILL[row + x] = 1
    rect_set(FILL, *PILE_RECT)

    # 所有家具都有 alpha → 外扩 3px 作为排除区
    for k in meta:
        bx0, by0, bx1, by1 = meta[k]["bbox"]
        a = Image.open(f"{OUTDIR}/obj_{int(k):02d}.png").convert("RGBA").getchannel("A")
        a = a.filter(ImageFilter.MaxFilter(7))
        ap = a.load()
        for y in range(by0, by1):
            row = y * W
            for x in range(bx0, bx1):
                if ap[x - bx0, y - by0] > 0:
                    EXCL[row + x] = 1
    for r in PROTECT_RECTS:
        rect_set(EXCL, *r)
    rect_set(EXCL, 0, 0, W, 58)      # 后墙
    rect_set(EXCL, 0, 370, W, H)     # 底部墙基
    rect_set(EXCL, 0, 0, 10, H)      # 左墙边
    rect_set(EXCL, 630, 0, W, H)     # 右墙边

    # ---- 2) 纵向镜像补洞（同列上下找"干净且明亮"的地板，循环填充，板缝相位对齐）----
    src = [[px[x, y] for x in range(W)] for y in range(H)]   # 原始色快照

    def Lc(c):
        return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]

    SRC_OK = bytearray(W * H)   # 可作补洞来源：地板 + 足够亮（排除阴影/家具）
    for y in range(H):
        for x in range(W):
            i = y * W + x
            if not FILL[i] and not EXCL[i] and Lc(src[y][x]) >= 72:
                SRC_OK[i] = 1

    out = day.copy()
    op = out.load()
    filled = 0
    for x in range(W):
        y = 0
        while y < H:
            if not FILL[y * W + x]:
                y += 1
                continue
            ya = y
            while y < H and FILL[y * W + x]:
                y += 1
            yb = y  # 掩膜段 [ya, yb)
            # 上方连续可用长度
            La = 0
            yy = ya - 1
            while yy >= 0 and SRC_OK[yy * W + x]:
                La += 1; yy -= 1
            # 下方连续可用长度
            Lb = 0
            yy = yb
            while yy < H and SRC_OK[yy * W + x]:
                Lb += 1; yy += 1
            for yy in range(ya, yb):
                s1 = s2 = None
                if La >= Lb and La > 0:
                    d = yy - (ya - 1)          # >=1
                    s1 = ya - 1 - ((d - 1) % La)
                    s2 = ya - 1 - ((d - 1 + La // 2) % La)   # 第二个采样偏移半个周期
                elif Lb > 0:
                    d = yb - yy
                    s1 = yb + ((d - 1) % Lb)
                    s2 = yb + ((d - 1 + Lb // 2) % Lb)
                else:
                    # 兜底：同行向左右找干净地板（极少发生）
                    for dx in range(1, 80):
                        for xx in (x - dx, x + dx):
                            if 0 <= xx < W and SRC_OK[yy * W + xx]:
                                op[x, yy] = px[xx, yy]
                                filled += 1
                                break
                        else:
                            continue
                        break
                    continue
                # 双采样平均：保留板缝相位，同时打散镜像对称的纹理痕迹
                c1 = src[s1][x]; c2 = src[s2][x]
                op[x, yy] = ((c1[0] + c2[0] + 1) // 2,
                             (c1[1] + c2[1] + 1) // 2,
                             (c1[2] + c2[2] + 1) // 2)
                filled += 1
    print(f"补洞像素 {filled} 个")

    # 补洞后的"干净地板"快照（用于精灵边缘反解混）
    clean_pre = out.copy()
    cpp = clean_pre.load()

    # ---- 3) 亮度拉平（左阴影 + 窗光）----
    def L(c):
        return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]

    # 基准亮度：取中央竖通道（干净地板）的中位
    ref = [L(op[x, y]) for y in range(150, 260) for x in range(300, 380)]
    REF = statistics.median(ref)
    print(f"地板基准亮度 REF = {REF:.1f}")

    flat = 0
    for (rx0, ry0, rx1, ry1) in FLAT_REGIONS:
        for y in range(max(0, ry0), min(H, ry1)):
            row = y * W
            for x in range(max(0, rx0), min(W, rx1)):
                i = row + x
                if EXCL[i]:          # 只保护家具/建筑；补洞后的地板参与拉平
                    continue
                c = op[x, y]
                lv = L(c)
                if lv < FLAT_LO or lv > FLAT_HI:
                    continue
                gain = 1.0 + FLAT_STRENGTH * (REF / lv - 1.0)
                gain = max(GAIN_MIN, min(GAIN_MAX, gain))
                op[x, y] = (min(255, int(c[0] * gain + 0.5)),
                            min(255, int(c[1] * gain + 0.5)),
                            min(255, int(c[2] * gain + 0.5)))
                flat += 1
    print(f"亮度拉平像素 {flat} 个（左阴影 + 窗光）")

    # ---- 4) 家具放回新位置（边缘用补洞后地板反解混，避免二次混色光晕）----
    for idx, mv in moved.items():
        rgba = mv["rgba"]; a = mv["alpha"]; nx0, ny0 = mv["npos"]
        bx0, by0, bx1, by1 = mv["obbox"]
        w, h = rgba.size
        rp = rgba.load(); ap = a.load()
        for dy in range(h):
            for dx in range(w):
                av = ap[dx, dy]
                if av == 0:
                    continue
                r, g, b, _ = rp[dx, dy]
                if 10 < av < 250:   # 软边反解混：c' = (c-(1-a)·bg)/a，bg 取原位置补齐后的地板
                    t = av / 255.0
                    bgc = cpp[bx0 + dx, by0 + dy]
                    r = min(255, max(0, int(round((r - (1 - t) * bgc[0]) / t))))
                    g = min(255, max(0, int(round((g - (1 - t) * bgc[1]) / t))))
                    b = min(255, max(0, int(round((b - (1 - t) * bgc[2]) / t))))
                rp[dx, dy] = (r, g, b, av)
        out.paste(rgba, (nx0, ny0), rgba)
        print(f"  放回 #{idx:02d} {mv['kind']} @ ({nx0},{ny0})")

    out.save(OUT1X)
    out.resize((W * 2, H * 2), Image.NEAREST).save(OUT2X)
    print(f"新白天地图 → {OUT1X} / {OUT2X}")

    # ---- 5) 前后对比图 ----
    try:
        f_big = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 16)
        f_sm = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
    except OSError:
        f_big = f_sm = ImageFont.load_default()
    a2 = day.resize((W * 2, H * 2), Image.NEAREST)
    b2 = out.resize((W * 2, H * 2), Image.NEAREST)
    pad, top = 14, 54
    cmp_img = Image.new("RGB", (W * 2 + pad * 3, H * 2 * 2 + top + pad * 2 + 30), (26, 24, 30))
    cd = ImageDraw.Draw(cmp_img)
    cd.text((pad, 12), "酒馆布局重排 · 前（上）/ 后（下）—— 左阴影已去、窗光已去、右下木箱堆清走、楼梯口让开",
            fill=(238, 232, 220), font=f_big)
    cmp_img.paste(a2, (pad, top))
    cmp_img.paste(b2, (pad, top + H * 2 + 28))
    cd.text((pad + 4, top + 6), "BEFORE", fill=(255, 210, 120), font=f_sm)
    cd.text((pad + 4, top + H * 2 + 34), "AFTER", fill=(140, 230, 150), font=f_sm)
    cmp_img.save(COMPARE)
    print(f"前后对比 → {COMPARE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
