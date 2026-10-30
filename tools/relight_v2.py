#!/usr/bin/env python3
"""换光不换图 v2：连续光照场（无光圈硬边）。

对比 v1（tools/relight.py）的八处修正：
1. 衰减不再量化成档位 → 连续高斯 exp(-k·d²)，无阶梯环
2. 不做 d>=1 硬裁断 → 高斯自然趋零，无椭圆轮廓线
3. 加色改线性软加 base + L·(255-base)/255 → 不 255 截断、无平台亮边
4. 所有灯先累加到统一光照场，再一次性合成 → 重叠处无极光边界
5. 每盏逻辑灯拆成 3 个抖动子瓣 → 打散正圆、成不规则光斑
6. 距离插值色温：核心暖白 → 外围深橙 → 不像贴片
7. 按底图亮度衰减（亮面少给光）→ 光不横跨材质断差留轮廓
8. 叠一层大半径低强度环境反弹 → 光斑嵌进连续照明，不再孤立悬浮

用法：python tools/relight_v2.py
产出：scene_dusk_v2 / scene_night_v2 的 1x + 2x，以及 v1|v2 对比图
"""
from __future__ import annotations

import colorsys
import math
import random
from PIL import Image

SRC = "assets/house/v4/scene_day_1x.png"
OUT = "assets/house/v4"
W, H = 640, 384
L_FLOOR = 4.0 / 100.0

KEY = {
    "dawn":  dict(ls=0.88, ss=0.96, anchor=(0x56, 0x69, 0x7E), w=0.10),
    "dusk":  dict(ls=0.90, ss=1.12, anchor=(0xC2, 0x70, 0x3A), w=0.12),
    "night": dict(ls=0.67, ss=0.84, anchor=(0x23, 0x2E, 0x3C), w=0.28),
}

WINDOWS = [(192, 28), (245, 28), (387, 28), (444, 28)]
HEARTH = (316, 67)
WIN_BOXES = [(180, 14, 208, 40), (232, 14, 260, 40),
             (374, 14, 402, 40), (430, 14, 458, 40)]
FIRE_BOX = (298, 53, 336, 82)
FIRE_MID = (242, 150, 50)
FIRE_CORE = (252, 210, 132)

# 色温：光是"有色的能量"，核心也不给白色，避免过曝成雾
WARM_CORE, WARM_EDGE = (255, 180, 112), (255, 112, 46)
COOL_CORE, COOL_EDGE = (168, 190, 218), (88, 110, 144)


def clamp8(v: float) -> int:
    return 0 if v < 0 else (255 if v > 255 else int(round(v)))


def grade(im: Image.Image, p: dict) -> Image.Image:
    out = im.copy()
    px = out.load()
    ar, ag, ab = p["anchor"] if p["anchor"] else (0, 0, 0)
    w, ls, ss = p["w"], p["ls"], p["ss"]
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
            l = max(l * ls, L_FLOOR)
            s = min(1.0, s * ss)
            r2, g2, b2 = colorsys.hls_to_rgb(h, l, s)
            r2 *= 255.0; g2 *= 255.0; b2 *= 255.0
            if w > 0:
                r2 = r2 * (1 - w) + ar * w
                g2 = g2 * (1 - w) + ag * w
                b2 = b2 * (1 - w) + ab * w
            px[x, y] = (clamp8(r2), clamp8(g2), clamp8(b2))
    return out


def fire_boost(im: Image.Image, boost: float) -> None:
    """火焰按火色板重绘，但保留一点原纹理（只混 65%），避免糊成一块。"""
    px = im.load()
    x0, y0, x1, y1 = FIRE_BOX
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if r > 80 and (r - b) > 28 and (r - g) > 15:
                t = min(1.0, max(0.0, (r - 80) / 120.0)) * boost
                tr = FIRE_MID[0] * (1 - t) + FIRE_CORE[0] * t
                tg = FIRE_MID[1] * (1 - t) + FIRE_CORE[1] * t
                tb = FIRE_MID[2] * (1 - t) + FIRE_CORE[2] * t
                k = 0.65
                px[x, y] = (clamp8(r * (1 - k) + tr * k),
                            clamp8(g * (1 - k) + tg * k),
                            clamp8(b * (1 - k) + tb * k))


def night_windows(im: Image.Image) -> None:
    px = im.load()
    for (x0, y0, x1, y1) in WIN_BOXES:
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b = px[x, y]
                if b > r + 8 and b > 90:
                    k = 0.30 if b < 145 else 0.48
                    px[x, y] = (clamp8(r * k + 38 * (1 - k)),
                                clamp8(g * k + 52 * (1 - k)),
                                clamp8(b * k + 74 * (1 - k)))


def split_lobes(cx, cy, rx, ry, seed):
    """一盏灯 → 3 个抖动子瓣（打散正圆）。"""
    rnd = random.Random(seed)
    out = []
    for _ in range(3):
        ox = rnd.uniform(-0.22, 0.22) * rx
        oy = rnd.uniform(-0.10, 0.26) * ry
        s = rnd.uniform(0.78, 1.16)
        wgt = rnd.uniform(0.62, 1.0)
        out.append((cx + ox, cy + oy, rx * s, ry * s, wgt))
    return out


class LightField:
    """统一光照场：所有灯累加，最后一次合成。"""

    def __init__(self):
        self.L = [[0.0] * (W * H) for _ in range(3)]

    def add(self, cx, cy, rx, ry, intensity, core, edge, lobes=3, seed=0, squint=0.0):
        subs = split_lobes(cx, cy, rx, ry, seed) if lobes > 1 else [(cx, cy, rx, ry, 1.0)]
        norm = 1.0 / math.sqrt(lobes)
        for (lx, ly, lrx, lry, lwt) in subs:
            self._add_one(lx, ly, lrx, lry, intensity * lwt * norm,
                          core, edge, squint)

    def _add_one(self, cx, cy, rx, ry, inten, core, edge, squint):
        irx, iry = 1.0 / rx, 1.0 / ry
        cut = 2.0                      # 高斯尾部截断，远到已不可见
        x0 = max(0, int(cx - rx * cut)); x1 = min(W - 1, int(cx + rx * cut))
        y0 = max(0, int(cy - ry * cut)); y1 = min(H - 1, int(cy + ry * cut))
        Lr, Lg, Lb = self.L
        k = 4.0
        for y in range(y0, y1 + 1):
            dy = (y - cy) * iry
            for x in range(x0, x1 + 1):
                dx = (x - cx) * irx + dy * squint
                d2 = dx * dx + dy * dy
                g = math.exp(-k * d2)
                if g < 0.006:
                    continue
                t = min(1.0, math.sqrt(d2))
                cr = core[0] * (1 - t) + edge[0] * t
                cg = core[1] * (1 - t) + edge[1] * t
                cb = core[2] * (1 - t) + edge[2] * t
                a = inten * g
                i = y * W + x
                Lr[i] += cr * a
                Lg[i] += cg * a
                Lb[i] += cb * a

    def composite(self, base: Image.Image, surface_att: float = 0.55) -> Image.Image:
        out = base.copy()
        px = out.load()
        Lr, Lg, Lb = self.L
        for y in range(H):
            row = y * W
            for x in range(W):
                i = row + x
                lr, lg, lb = Lr[i], Lg[i], Lb[i]
                if lr < 0.5 and lg < 0.5 and lb < 0.5:
                    continue
                r, g, b = px[x, y]
                # 按底图亮度衰减：亮面少给光（0.45~1.0）
                yb = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                att = 1.0 - surface_att * yb
                lr *= att; lg *= att; lb *= att
                # 线性软加：不截断
                px[x, y] = (clamp8(r + lr * (255 - r) / 255.0),
                            clamp8(g + lg * (255 - g) / 255.0),
                            clamp8(b + lb * (255 - b) / 255.0))
        return out


def build(kind: str) -> Image.Image:
    im = grade(Image.open(SRC).convert("RGB"), KEY[kind])
    lf = LightField()

    if kind == "dusk":
        fire_boost(im, 0.75)
        # 环境反弹：只给一点点，保证光斑嵌进连续照明又不糊雾
        lf.add(320, 240, 460, 330, 0.07, WARM_CORE, WARM_EDGE, seed=101)
        # 窗光：斜长、窄一些
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 70, 26, 72, 0.30, WARM_CORE, WARM_EDGE,
                   seed=200 + i, squint=0.26)
        # 炉火
        lf.add(HEARTH[0], HEARTH[1] + 18, 62, 46, 0.55, WARM_CORE, WARM_EDGE, seed=301)
        lf.add(HEARTH[0], HEARTH[1] + 2, 22, 17, 0.48, WARM_CORE, WARM_EDGE, seed=302)
    elif kind == "night":
        fire_boost(im, 1.0)
        night_windows(im)
        # 冷环境
        lf.add(320, 240, 470, 340, 0.05, COOL_CORE, COOL_EDGE, seed=111)
        # 月光窗
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 56, 24, 58, 0.18, COOL_CORE, COOL_EDGE,
                   seed=210 + i, squint=0.22)
        # 炉火（全场最亮）
        lf.add(HEARTH[0], HEARTH[1] + 20, 70, 50, 0.80, WARM_CORE, WARM_EDGE, seed=311)
        lf.add(HEARTH[0], HEARTH[1] + 4, 26, 19, 0.62, WARM_CORE, WARM_EDGE, seed=312)
        # 吧台小灯 + 桌面烛点（远弱于炉火）
        lf.add(120, 102, 28, 20, 0.22, WARM_CORE, WARM_EDGE, seed=320)
        for i, (tx, ty) in enumerate([(214, 152), (272, 336), (472, 214), (522, 306)]):
            lf.add(tx, ty, 12, 9, 0.18, WARM_CORE, WARM_EDGE, seed=330 + i)
    elif kind == "dawn":
        fire_boost(im, 0.6)
        lf.add(320, 240, 460, 330, 0.06, COOL_CORE, COOL_EDGE, seed=121)
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 62, 24, 64, 0.20, COOL_CORE, COOL_EDGE,
                   seed=220 + i, squint=0.20)
        lf.add(HEARTH[0], HEARTH[1] + 14, 48, 36, 0.30, WARM_CORE, WARM_EDGE, seed=321)
    return lf.composite(im)


def main() -> int:
    for kind in ("dawn", "dusk", "night"):
        im = build(kind)
        im.save(f"{OUT}/scene_{kind}_v2_1x.png")
        im.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/scene_{kind}_v2_2x.png")
        print(f"{kind} v2 → {OUT}/scene_{kind}_v2_1x.png")

    # v1 | v2 对照：上排整图，下排壁炉放大（最能看出光圈）
    from PIL import ImageDraw, ImageFont
    pad, labh = 8, 26
    cw, ch = W, H
    zw, zh = 150 * 3, 110 * 3          # 放大后的壁炉裁剪
    out = Image.new("RGB", (cw * 2 + pad * 3, ch + zh + labh * 2 + pad * 3), (246, 243, 235))
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 16)
    except OSError:
        font = ImageFont.load_default()
    d = ImageDraw.Draw(out)
    cols = [("assets/house/v4/scene_dusk_1x.png", "v1 叠加光圈"),
            ("assets/house/v4/scene_dusk_v2_1x.png", "v2 连续光照场")]
    for i, (path, lab) in enumerate(cols):
        x = pad + i * (cw + pad)
        d.text((x + 4, 6), lab, fill=(40, 36, 30), font=font)
        src = Image.open(path).convert("RGB")
        out.paste(src, (x, labh + pad))
        z = src.crop((250, 40, 400, 150)).resize((zw, zh), Image.NEAREST)
        zy = labh + pad + ch + pad + labh
        d.text((x + 4, labh + pad + ch + pad), "壁炉区 3× 放大", fill=(90, 84, 74), font=font)
        out.paste(z, (x, zy))
    out.save("assets/house/v4/scene_dusk_v1_vs_v2.png")
    print("对照 → assets/house/v4/scene_dusk_v1_vs_v2.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
