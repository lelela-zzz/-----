#!/usr/bin/env python3
"""换光不换图 v5：乘性曝光 + 黑场恢复 + gamma，去雾、提亮、还原本色。

v4 发灰/雾蒙的根因是"加色合成"：base + L·(255-base)/255 相当于给全图加一层
恒定的灰白光照，黑场被抬高、饱和度被冲淡 → 雾感。v5 改为：

1. 乘性曝光：out = base · (1 + L/255 · gain)（每通道独立 → 天然带色温，且 0 仍是 0）
2. 黑场恢复：把 2% 分位映射回 0（levels），去掉残留的抬底灰雾
3. gamma 曝光：0.82 提亮中间调，不冲高光
4. 对比 1.10 + 均值归一到目标亮度

用法：python tools/relight_v5.py
产出：scene_{dawn,dusk,night}_v5_1x/2x.png + v4|v5 对照
"""
from __future__ import annotations

import colorsys
import math
import random
from PIL import Image

SRC = "assets/house/v4/scene_day_v6_1x.png"   # v6 布局修正版（4 窗 / 疏桌 / 一字吧台 / 桶靠墙）
OUT = "assets/house/v4"
W, H = 640, 384
L_FLOOR = 4.0 / 100.0

KEY = {
    "dawn":  dict(ls=0.88, ss=0.96, anchor=(0x56, 0x69, 0x7E), w=0.10,
                  target_y=86.0, light_gain=1.45, gamma=0.80, contrast=1.05, sat_boost=1.10,
                  wb=(1.0, 1.0, 1.0),
                  max_light=190.0, surface_att=0.50, grad_strength=0.18, base_grad=0.07),
    "dusk":  dict(ls=0.90, ss=1.12, anchor=(0xC2, 0x70, 0x3A), w=0.12,
                  target_y=92.0, light_gain=1.45, gamma=0.78, contrast=1.05, sat_boost=1.02,
                  wb=(1.0, 1.0, 1.0),
                  max_light=200.0, surface_att=0.50, grad_strength=0.18, base_grad=0.07),
    # v6：夜晚暖度整体提一档 —— 冷锚权重 0.28→0.22、饱和 0.84→0.90、
    # 白平衡 (1.07,1.00,0.90)、暖光强度上调；冷光（月光/冷环境）相应压低
    "night": dict(ls=0.67, ss=0.90, anchor=(0x2C, 0x33, 0x3E), w=0.22,
                  target_y=58.0, light_gain=1.62, gamma=0.76, contrast=1.06, sat_boost=1.16,
                  wb=(1.07, 1.00, 0.90),
                  max_light=150.0, surface_att=0.32, grad_strength=0.12, base_grad=0.04),
}

WINDOWS = [(109, 24), (240, 24), (388, 24), (519, 24)]   # v6 保留 4 扇
HEARTH = (325, 66)   # v6 壁炉中轴
WIN_BOXES = [(96, 23, 123, 49), (228, 23, 254, 49), (376, 23, 402, 49), (506, 23, 532, 49)]
FIRE_BOX = (298, 53, 336, 82)
FIRE_MID = (242, 150, 50)
FIRE_CORE = (252, 210, 132)

WARM_CORE, WARM_EDGE = (255, 180, 112), (255, 112, 46)
COOL_CORE, COOL_EDGE = (168, 190, 218), (88, 110, 144)

LIGHT_DIR = (-0.34, -0.86, 0.38)
NORMAL_SCALE = 0.95
NORMAL_BLUR = 2
AMBIENT_SHADE = 0.70
FORM_STRENGTH = 0.20
LIGHT_DIFFUSE_BIAS = 0.62
BLACK_RESTORE = 0.45      # 只去掉约一半抬底灰雾，避免削死暗部
CLAMP_Y = 0.40


def clamp8(v):
    return 0 if v < 0 else (255 if v > 255 else int(round(v)))


def grade(im, p):
    out = im.copy(); px = out.load()
    ar, ag, ab = p["anchor"] if p["anchor"] else (0, 0, 0)
    w, ls, ss = p["w"], p["ls"], p["ss"]
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
            l = max(l * ls, L_FLOOR); s = min(1.0, s * ss)
            r2, g2, b2 = colorsys.hls_to_rgb(h, l, s)
            r2 *= 255.0; g2 *= 255.0; b2 *= 255.0
            if w > 0:
                r2 = r2 * (1 - w) + ar * w
                g2 = g2 * (1 - w) + ag * w
                b2 = b2 * (1 - w) + ab * w
            px[x, y] = (clamp8(r2), clamp8(g2), clamp8(b2))
    return out


_FIRE_PIXELS = None


def fire_pixels():
    global _FIRE_PIXELS
    if _FIRE_PIXELS is None:
        im0 = Image.open(SRC).convert("RGB"); px = im0.load()
        pts = []
        for y in range(FIRE_BOX[1], FIRE_BOX[3]):
            for x in range(FIRE_BOX[0], FIRE_BOX[2]):
                r, g, b = px[x, y]
                if r > 110 and (r - b) > 45 and (r - g) > 32:
                    pts.append((x, y))
        _FIRE_PIXELS = pts
    return _FIRE_PIXELS


def paint_fire(im, boost=1.0):
    px = im.load()
    cx = (FIRE_BOX[0] + FIRE_BOX[2]) / 2.0
    cy = (FIRE_BOX[1] + FIRE_BOX[3]) / 2.0
    hw = (FIRE_BOX[2] - FIRE_BOX[0]) / 2.0
    hh = (FIRE_BOX[3] - FIRE_BOX[1]) / 2.0
    for (x, y) in fire_pixels():
        d = math.sqrt(((x - cx) / hw) ** 2 + ((y - cy) / hh) ** 2)
        t = max(0.0, min(1.0, (1.0 - d * 0.9) * boost))
        px[x, y] = (clamp8(FIRE_MID[0] * (1 - t) + FIRE_CORE[0] * t),
                    clamp8(FIRE_MID[1] * (1 - t) + FIRE_CORE[1] * t),
                    clamp8(FIRE_MID[2] * (1 - t) + FIRE_CORE[2] * t))


def night_windows(im):
    px = im.load()
    for (x0, y0, x1, y1) in WIN_BOXES:
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b = px[x, y]
                if b > r + 8 and b > 90:
                    k = 0.28 if b < 145 else 0.44
                    px[x, y] = (clamp8(r * k + 52 * (1 - k)),
                                clamp8(g * k + 66 * (1 - k)),
                                clamp8(b * k + 92 * (1 - k)))


def build_normals(im):
    px = im.load()
    Y = [0.0] * (W * H)
    for y in range(H):
        row = y * W
        for x in range(W):
            r, g, b = px[x, y]
            Y[row + x] = 0.299 * r + 0.587 * g + 0.114 * b

    def yat(x, y):
        x = 0 if x < 0 else (W - 1 if x >= W else x)
        y = 0 if y < 0 else (H - 1 if y >= H else y)
        return Y[y * W + x]

    nx = [0.0] * (W * H); ny = [0.0] * (W * H)
    s = NORMAL_SCALE / 255.0
    for y in range(H):
        row = y * W; ym1 = y - 1; yp1 = y + 1
        for x in range(W):
            gx = ((yat(x + 1, ym1) + 2 * yat(x + 1, y) + yat(x + 1, yp1))
                  - (yat(x - 1, ym1) + 2 * yat(x - 1, y) + yat(x - 1, yp1))) / 4.0
            gy = ((yat(x - 1, yp1) + 2 * yat(x, yp1) + yat(x + 1, yp1))
                  - (yat(x - 1, ym1) + 2 * yat(x, ym1) + yat(x + 1, ym1))) / 4.0
            nx[row + x] = -gx * s
            ny[row + x] = -gy * s

    for _ in range(NORMAL_BLUR):
        sx = [0.0] * (W * H); sy = [0.0] * (W * H)
        for y in range(H):
            row = y * W
            for x in range(W):
                accx = accy = 0.0
                for dy in (-1, 0, 1):
                    yy = min(H - 1, max(0, y + dy))
                    for dx in (-1, 0, 1):
                        xx = min(W - 1, max(0, x + dx))
                        accx += nx[yy * W + xx]; accy += ny[yy * W + xx]
                sx[row + x] = accx / 9.0
                sy[row + x] = accy / 9.0
        nx, ny = sx, sy
    return nx, ny


class LightField:
    def __init__(self):
        self.L = [[0.0] * (W * H) for _ in range(3)]

    def add(self, cx, cy, rx, ry, intensity, core, edge, lobes=3, seed=0, squint=0.0):
        if lobes > 1:
            rnd = random.Random(seed)
            subs = [(cx + rnd.uniform(-0.20, 0.20) * rx,
                     cy + rnd.uniform(-0.10, 0.24) * ry,
                     rx * rnd.uniform(0.82, 1.14),
                     ry * rnd.uniform(0.82, 1.14),
                     rnd.uniform(0.70, 1.0)) for _ in range(lobes)]
            norm = 1.0 / math.sqrt(lobes)
        else:
            subs = [(cx, cy, rx, ry, 1.0)]; norm = 1.0
        for (lx, ly, lrx, lry, lwt) in subs:
            self._add_one(lx, ly, lrx, lry, intensity * lwt * norm, core, edge, squint)

    def _add_one(self, cx, cy, rx, ry, inten, core, edge, squint):
        irx, iry = 1.0 / rx, 1.0 / ry
        cut = 2.0
        x0 = max(0, int(cx - rx * cut)); x1 = min(W - 1, int(cx + rx * cut))
        y0 = max(0, int(cy - ry * cut)); y1 = min(H - 1, int(cy + ry * cut))
        Lr, Lg, Lb = self.L
        k = 3.2
        for y in range(y0, y1 + 1):
            dy = (y - cy) * iry
            for x in range(x0, x1 + 1):
                dx = (x - cx) * irx + dy * squint
                d2 = dx * dx + dy * dy
                g = math.exp(-k * d2)
                if g < 0.004:
                    continue
                t = min(1.0, math.sqrt(d2))
                cr = core[0] * (1 - t) + edge[0] * t
                cg = core[1] * (1 - t) + edge[1] * t
                cb = core[2] * (1 - t) + edge[2] * t
                a = inten * g
                i = y * W + x
                Lr[i] += cr * a; Lg[i] += cg * a; Lb[i] += cb * a

    def composite(self, base, nx, ny, p):
        """乘性曝光：光作为每通道增益，保留黑场与饱和，不产生灰纱。"""
        out = base.copy(); px = out.load()
        Lr, Lg, Lb = self.L
        lx, ly, lz = LIGHT_DIR
        n = math.sqrt(lx * lx + ly * ly + lz * lz)
        lx, ly, lz = lx / n, ly / n, lz / n
        gain = p["light_gain"]
        max_light = p["max_light"]
        knee = 0.6 * max_light
        for y in range(H):
            row = y * W
            gy = y / H
            for x in range(W):
                i = row + x
                r, g, b = px[x, y]
                vx, vy = nx[i], ny[i]
                nl = math.sqrt(vx * vx + vy * vy + 1.0)
                diff = (vx * lx + vy * ly + lz) / nl
                diff = 0.0 if diff < 0 else (1.0 if diff > 1 else diff)
                shade = AMBIENT_SHADE + (1 - AMBIENT_SHADE) * diff

                f = 1.0 - FORM_STRENGTH * (1.0 - shade)
                u = 0.55 * (x / W) + 0.45 * gy
                f *= (1.0 - p["base_grad"] * u)
                r *= f; g *= f; b *= f

                lr, lg, lb = Lr[i], Lg[i], Lb[i]
                if lr >= 0.5 or lg >= 0.5 or lb >= 0.5:
                    yb = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                    k = (1.0 - p["surface_att"] * yb)
                    k *= (1.0 - p["grad_strength"] * u)
                    k *= (1.0 - LIGHT_DIFFUSE_BIAS) + LIGHT_DIFFUSE_BIAS * shade
                    lr *= k; lg *= k; lb *= k
                    mx = max(lr, lg, lb)
                    if mx > knee:
                        over = mx - knee
                        newmx = knee + over / (1.0 + over / (max_light - knee))
                        s = newmx / mx
                        lr *= s; lg *= s; lb *= s
                    # 乘性：每通道增益
                    r *= 1.0 + (lr / 255.0) * gain
                    g *= 1.0 + (lg / 255.0) * gain
                    b *= 1.0 + (lb / 255.0) * gain

                px[x, y] = (clamp8(r), clamp8(g), clamp8(b))
        return out


def post_process(im, p):
    """黑场恢复 → gamma 曝光 → 对比 → 均值归一。"""
    px = im.load()
    vals = [0.0] * (W * H)
    for y in range(H):
        row = y * W
        for x in range(W):
            r, g, b = px[x, y]
            vals[row + x] = 0.299 * r + 0.587 * g + 0.114 * b
    vals.sort()
    p02 = vals[int(len(vals) * 0.02)] / 255.0 * BLACK_RESTORE
    lo = min(0.35, max(0.0, p02))        # 黑场起点（限制幅度防死黑）

    gamma, contrast = p["gamma"], p["contrast"]
    lut = []
    for v in range(256):
        t = v / 255.0
        t = (t - lo) / (1.0 - lo) if lo < 1 else t
        t = 0.0 if t < 0 else t
        t = t ** gamma                    # 提亮中间调，不冲高光
        t = 0.5 + (t - 0.5) * contrast    # 对比
        lut.append(clamp8(t * 255.0))
    im = im.point(lut * 3)

    # 均值归一
    px = im.load()
    tot = 0.0
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            tot += 0.299 * r + 0.587 * g + 0.114 * b
    mean_y = tot / (W * H)
    scale = p["target_y"] / mean_y if mean_y > 0 else 1.0
    scale = min(1 + CLAMP_Y, max(1 - CLAMP_Y, scale))
    im = im.point([clamp8(v * scale) for v in range(256)] * 3)

    # 饱和度补偿：抵消冷锚混色造成的发灰
    f = p.get("sat_boost", 1.0)
    if abs(f - 1.0) > 1e-3:
        px = im.load()
        for y in range(H):
            for x in range(W):
                r, g, b = px[x, y]
                yy = 0.299 * r + 0.587 * g + 0.114 * b
                px[x, y] = (clamp8(yy + (r - yy) * f),
                            clamp8(yy + (g - yy) * f),
                            clamp8(yy + (b - yy) * f))

    # 白平衡：整体暖度微调（材质与光照同步偏暖）
    wr, wg, wbk = p.get("wb", (1.0, 1.0, 1.0))
    if (wr, wg, wbk) != (1.0, 1.0, 1.0):
        px = im.load()
        for y in range(H):
            for x in range(W):
                r, g, b = px[x, y]
                px[x, y] = (clamp8(r * wr), clamp8(g * wg), clamp8(b * wbk))
    return im


def build(kind):
    p = KEY[kind]
    im = grade(Image.open(SRC).convert("RGB"), p)
    lf = LightField()

    if kind == "dusk":
        lf.add(320, 260, 500, 360, 0.09, WARM_CORE, WARM_EDGE, seed=101)
        # 窗光灯关闭：按用户要求"去掉窗户射入的光线"；其余光源与 v6 完全一致
        # for i, (wx, wy) in enumerate(WINDOWS):
        #     lf.add(wx, wy + 74, 30, 82, 0.30, WARM_CORE, WARM_EDGE, seed=200 + i, squint=0.26)
        lf.add(HEARTH[0], HEARTH[1] + 22, 110, 86, 0.46, WARM_CORE, WARM_EDGE, seed=301)
        lf.add(HEARTH[0], HEARTH[1] + 6, 36, 28, 0.32, WARM_CORE, WARM_EDGE, seed=302)
    elif kind == "night":
        night_windows(im)
        lf.add(320, 210, 580, 430, 0.09, WARM_CORE, WARM_EDGE, seed=111)      # 暖环境 +12%
        lf.add(320, 300, 520, 380, 0.02, COOL_CORE, COOL_EDGE, seed=112)      # 冷环境压低
        lf.add(HEARTH[0], HEARTH[1] + 52, 250, 195, 0.52, WARM_CORE, WARM_EDGE, seed=311)  # +13%
        lf.add(HEARTH[0], HEARTH[1] + 22, 120, 92, 0.36, WARM_CORE, WARM_EDGE, seed=312)
        lf.add(HEARTH[0], HEARTH[1] + 6, 36, 28, 0.27, WARM_CORE, WARM_EDGE, seed=313)
        # 窗光灯关闭（同上）
        # for i, (wx, wy) in enumerate(WINDOWS):
        #     lf.add(wx, wy + 60, 44, 88, 0.08, COOL_CORE, COOL_EDGE, seed=210 + i, squint=0.20)
        lf.add(120, 104, 52, 40, 0.11, WARM_CORE, WARM_EDGE, seed=320)
        for i, (tx, ty) in enumerate([(214, 152), (272, 336), (472, 214), (522, 306)]):
            lf.add(tx, ty, 26, 20, 0.09, WARM_CORE, WARM_EDGE, seed=330 + i)
    elif kind == "dawn":
        lf.add(320, 260, 500, 360, 0.08, COOL_CORE, COOL_EDGE, seed=121)
        # 窗光灯关闭（同上）
        # for i, (wx, wy) in enumerate(WINDOWS):
        #     lf.add(wx, wy + 64, 30, 70, 0.22, COOL_CORE, COOL_EDGE, seed=220 + i, squint=0.20)
        lf.add(HEARTH[0], HEARTH[1] + 18, 84, 64, 0.28, WARM_CORE, WARM_EDGE, seed=321)

    nx, ny = build_normals(im)
    out = lf.composite(im, nx, ny, p)
    out = post_process(out, p)
    paint_fire(out, 1.30 if kind == "night" else 0.95)
    return out


def main():
    for kind in ("dawn", "dusk", "night"):
        im = build(kind)
        im.save(f"{OUT}/scene_{kind}_v11_1x.png")
        im.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/scene_{kind}_v11_2x.png")
        px = im.load(); best = (-1, 0, 0); vals = []
        for y in range(H):
            for x in range(W):
                r, g, b = px[x, y]
                v = 0.299 * r + 0.587 * g + 0.114 * b
                if v > best[0]:
                    best = (v, x, y)
                vals.append(v)
        vals.sort()
        m = sum(vals) / len(vals)
        sd = math.sqrt(sum((v - m) ** 2 for v in vals) / len(vals))
        p05 = vals[int(len(vals) * 0.05)]
        sat = 0
        for y in range(0, H, 4):
            for x in range(0, W, 4):
                r, g, b = px[x, y]
                mx = max(r, g, b); mn = min(r, g, b)
                sat += (mx - mn) / mx if mx else 0
        sn = len(range(0, H, 4)) * len(range(0, W, 4))
        # 暖度指标：R-B 平均差
        warm = 0
        for y in range(0, H, 4):
            for x in range(0, W, 4):
                r, g, b = px[x, y]
                warm += r - b
        print(f"{kind} v11 → meanY {m:.1f} sd {sd:.1f} p05 {p05:.0f} "
              f"峰值@({best[1]},{best[2]}) Y={best[0]:.0f} 饱和 {sat/sn:.2f} 暖度R-B {warm/sn:.0f}")

    from PIL import ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 15)
    except OSError:
        font = ImageFont.load_default()
    pad, labh = 8, 24
    out = Image.new("RGB", (W * 2 + pad * 3, (H + labh) * 2 + pad * 3), (246, 243, 235))
    d = ImageDraw.Draw(out)
    oy = pad
    d.text((pad, oy), "旧图（v2 程序化 · v6 夜）", fill=(40, 36, 30), font=font)
    out.paste(Image.open(f"{OUT}/scene_night_v6_1x.png").convert("RGB"), (pad, oy + labh))
    d.text((pad * 2 + W, oy), "v6 布局修正版（v11 夜，同光源参数）", fill=(40, 36, 30), font=font)
    out.paste(Image.open(f"{OUT}/scene_night_v11_1x.png").convert("RGB"), (pad * 2 + W, oy + labh))
    out.save(f"{OUT}/scene_night_v11_compare.png")
    print(f"对照 → {OUT}/scene_night_v11_compare.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
