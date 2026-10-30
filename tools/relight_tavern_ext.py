#!/usr/bin/env python3
"""酒馆外观四时段烘焙（v15/村庄同参换图版）：乘性曝光 + 黑场恢复 + gamma。

与 tools/relight_village.py 的 grade / LightField / composite / post_process
逐字节同参数（KEY 完全一致），只有两处不同：
  1. SRC 换成酒馆外观 1x 底图（512x512，tools/make_tavern_ext_maps.py 产出）
  2. 光源布局换成「酒馆正面」语义：正门暖光池 / 三个二楼窗 / 一楼小窗

用法：python tools/relight_tavern_ext.py
产出：assets/tavern_exterior/v1/scene_{dawn,dusk,night}_1x.png
之后跑：python tools/cut_tavern_ext_props.py --derive
"""
from __future__ import annotations

import math
import random
import sys

from PIL import Image

SRC = "assets/tavern_exterior/v1/scene_day_1x.png"
OUT = "assets/tavern_exterior/v1"
W, H = 512, 512
L_FLOOR = 4.0 / 100.0

# 与 relight_village.KEY 逐字节一致
KEY = {
    "dawn":  dict(ls=0.88, ss=0.96, anchor=(0x56, 0x69, 0x7E), w=0.10,
                  target_y=86.0, light_gain=1.45, gamma=0.80, contrast=1.05, sat_boost=1.10,
                  wb=(1.0, 1.0, 1.0),
                  max_light=190.0, surface_att=0.50, grad_strength=0.18, base_grad=0.07),
    "dusk":  dict(ls=0.90, ss=1.12, anchor=(0xC2, 0x70, 0x3A), w=0.12,
                  target_y=92.0, light_gain=1.45, gamma=0.78, contrast=1.05, sat_boost=1.02,
                  wb=(1.0, 1.0, 1.0),
                  max_light=200.0, surface_att=0.50, grad_strength=0.18, base_grad=0.07),
    "night": dict(ls=0.67, ss=0.90, anchor=(0x2C, 0x33, 0x3E), w=0.22,
                  target_y=58.0, light_gain=1.62, gamma=0.76, contrast=1.06, sat_boost=1.16,
                  wb=(1.07, 1.00, 0.90),
                  max_light=150.0, surface_att=0.32, grad_strength=0.12, base_grad=0.04),
}

WARM_CORE, WARM_EDGE = (255, 180, 112), (255, 112, 46)
COOL_CORE, COOL_EDGE = (168, 190, 218), (88, 110, 144)

LIGHT_DIR = (-0.34, -0.86, 0.38)
NORMAL_SCALE = 0.95
NORMAL_BLUR = 2
AMBIENT_SHADE = 0.70
FORM_STRENGTH = 0.20
LIGHT_DIFFUSE_BIAS = 0.62
BLACK_RESTORE = 0.45
CLAMP_Y = 0.40

# 酒馆正面光源（512 坐标，658 版 ×0.778）：正门 (230,339) / 二楼窗 (143,194)
# (227,194)(308,194) / 一楼小窗 (145,265)； Broad=整幅环境洗光。
LIGHTS = {
    "dusk": [
        (256, 233, 436, 327, 0.08, "warm", 231),
        (230, 339, 62, 39, 0.30, "warm", 232),
        (230, 323, 35, 25, 0.18, "warm", 233),
        (143, 194, 31, 22, 0.13, "warm", 234),
        (227, 194, 31, 22, 0.13, "warm", 235),
        (308, 194, 31, 22, 0.13, "warm", 236),
    ],
    "night": [
        (256, 233, 498, 389, 0.08, "warm", 241),
        (256, 311, 436, 327, 0.03, "cool", 242),
        (230, 334, 86, 62, 0.40, "warm", 243),
        (230, 321, 43, 31, 0.30, "warm", 244),
        (143, 194, 33, 23, 0.16, "warm", 245),
        (227, 194, 33, 23, 0.16, "warm", 246),
        (308, 194, 33, 23, 0.16, "warm", 247),
        (145, 265, 27, 20, 0.14, "warm", 248),
    ],
    "dawn": [
        (256, 249, 467, 358, 0.08, "cool", 251),
        (230, 339, 47, 34, 0.18, "warm", 252),
    ],
}


def clamp8(v):
    return 0 if v < 0 else (255 if v > 255 else int(round(v)))


def grade(im, p):
    import colorsys
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
                    r *= 1.0 + (lr / 255.0) * gain
                    g *= 1.0 + (lg / 255.0) * gain
                    b *= 1.0 + (lb / 255.0) * gain

                px[x, y] = (clamp8(r), clamp8(g), clamp8(b))
        return out


def post_process(im, p):
    px = im.load()
    vals = [0.0] * (W * H)
    for y in range(H):
        row = y * W
        for x in range(W):
            r, g, b = px[x, y]
            vals[row + x] = 0.299 * r + 0.587 * g + 0.114 * b
    vals.sort()
    p02 = vals[int(len(vals) * 0.02)] / 255.0 * BLACK_RESTORE
    lo = min(0.35, max(0.0, p02))

    gamma, contrast = p["gamma"], p["contrast"]
    lut = []
    for v in range(256):
        t = v / 255.0
        t = (t - lo) / (1.0 - lo) if lo < 1 else t
        t = 0.0 if t < 0 else t
        t = t ** gamma
        t = 0.5 + (t - 0.5) * contrast
        lut.append(clamp8(t * 255.0))
    im = im.point(lut * 3)

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
    palette = {"warm": (WARM_CORE, WARM_EDGE), "cool": (COOL_CORE, COOL_EDGE)}
    for (cx, cy, rx, ry, inten, tone, seed) in LIGHTS[kind]:
        core, edge = palette[tone]
        lf.add(cx, cy, rx, ry, inten, core, edge, seed=seed)

    nx, ny = build_normals(im)
    out = lf.composite(im, nx, ny, p)
    return post_process(out, p)


def main():
    kinds = ("dawn", "dusk", "night")
    for kind in kinds:
        if len(sys.argv) > 1 and sys.argv[1] != kind:
            continue
        im = build(kind)
        im.save(f"{OUT}/scene_{kind}_1x.png")
        px = im.load()
        vals = []
        for y in range(0, H, 4):
            for x in range(0, W, 4):
                r, g, b = px[x, y]
                vals.append(0.299 * r + 0.587 * g + 0.114 * b)
        m = sum(vals) / len(vals)
        vals.sort()
        p05 = vals[int(len(vals) * 0.05)]
        warm = 0
        for y in range(0, H, 4):
            for x in range(0, W, 4):
                r, g, b = px[x, y]
                warm += r - b
        print(f"{kind} tavern_ext -> meanY {m:.1f} p05 {p05:.0f} 暖度R-B {warm / len(vals):.0f}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
