#!/usr/bin/env python3
"""换光不换图 v3：连续光照场 + 伪法线定向着色 + 亮度层次归一。

在 v2（无光圈硬边）基础上补三件事：
1. 方向性：由底图亮度梯度求伪法线（Sobel→3×3 平滑），与统一主光 Ldir 点积得 diffuse
2. 层次：主光/次光/环境三级强度阶梯；局部光乘 diffuse，只落在受光面；外加沿主光方向的线性衰减
3. 防失衡：S 形色调曲线 + 每时段平均亮度归一（dusk 88 / dawn 81 / night 56）

用法：python tools/relight_v3.py
产出：scene_{dawn,dusk,night}_v3_1x/2x.png + v2|v3 对照图
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
    "dawn":  dict(ls=0.88, ss=0.96, anchor=(0x56, 0x69, 0x7E), w=0.10, target_y=81.0),
    "dusk":  dict(ls=0.90, ss=1.12, anchor=(0xC2, 0x70, 0x3A), w=0.12, target_y=88.0),
    "night": dict(ls=0.67, ss=0.84, anchor=(0x23, 0x2E, 0x3C), w=0.28, target_y=56.0),
}

WINDOWS = [(192, 28), (245, 28), (387, 28), (444, 28)]
HEARTH = (316, 67)
WIN_BOXES = [(180, 14, 208, 40), (232, 14, 260, 40),
             (374, 14, 402, 40), (430, 14, 458, 40)]
FIRE_BOX = (298, 53, 336, 82)
FIRE_MID = (242, 150, 50)
FIRE_CORE = (252, 210, 132)

WARM_CORE, WARM_EDGE = (255, 180, 112), (255, 112, 46)
COOL_CORE, COOL_EDGE = (168, 190, 218), (88, 110, 144)

# ── 方向与层次参数（可调） ──
LIGHT_DIR = (-0.34, -0.86, 0.38)   # 指向光源：上偏左，略高
NORMAL_SCALE = 0.95                 # 法线强度（越大明暗越明显，过大出硬边）
NORMAL_BLUR = 2                     # 法线平滑遍数（压纹理噪点）
AMBIENT_SHADE = 0.66                # 背光面保底亮度（层次下限）
FORM_STRENGTH = 0.22                # 底图形体明暗强度
LIGHT_DIFFUSE_BIAS = 0.72           # 光的定向权重（0=全向，1=只受光面）
GRAD_STRENGTH = 0.32                # 沿主光方向的整体衰减（作用于光场）
BASE_GRAD = 0.10                    # 整帧基础方向衰减（作用于底图，统一方向感）
TONE_S = 0.18                       # 中灰对比拉伸强度
CLAMP_Y = 0.45                      # 归一亮度允许的±浮动


def clamp8(v: float) -> int:
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


def fire_boost(im, boost):
    px = im.load(); x0, y0, x1, y1 = FIRE_BOX
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


def night_windows(im):
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


# ── 伪法线 ──
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
        row = y * W
        ym1 = y - 1; yp1 = y + 1
        for x in range(W):
            gx = ((yat(x + 1, ym1) + 2 * yat(x + 1, y) + yat(x + 1, yp1))
                  - (yat(x - 1, ym1) + 2 * yat(x - 1, y) + yat(x - 1, yp1))) / 4.0
            gy = ((yat(x - 1, yp1) + 2 * yat(x, yp1) + yat(x + 1, yp1))
                  - (yat(x - 1, ym1) + 2 * yat(x, ym1) + yat(x + 1, ym1))) / 4.0
            nx[row + x] = -gx * s
            ny[row + x] = -gy * s

    # 3×3 平滑，压掉像素噪点导致的法线抖动（多遍）
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
            subs = []
            for _ in range(lobes):
                subs.append((cx + rnd.uniform(-0.22, 0.22) * rx,
                             cy + rnd.uniform(-0.10, 0.26) * ry,
                             rx * rnd.uniform(0.78, 1.16),
                             ry * rnd.uniform(0.78, 1.16),
                             rnd.uniform(0.62, 1.0)))
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
                Lr[i] += cr * a; Lg[i] += cg * a; Lb[i] += cb * a

    def composite(self, base, nx, ny, surface_att=0.55):
        out = base.copy(); px = out.load()
        Lr, Lg, Lb = self.L
        lx, ly, lz = LIGHT_DIR
        n = math.sqrt(lx * lx + ly * ly + lz * lz)
        lx, ly, lz = lx / n, ly / n, lz / n
        for y in range(H):
            row = y * W
            gy = y / H
            for x in range(W):
                i = row + x
                r, g, b = px[x, y]

                # 伪法线 → diffuse
                vx, vy = nx[i], ny[i]
                nl = math.sqrt(vx * vx + vy * vy + 1.0)
                diff = (vx * lx + vy * ly + 1.0 * lz) / nl
                diff = 0.0 if diff < 0 else (1.0 if diff > 1 else diff)
                shade = AMBIENT_SHADE + (1 - AMBIENT_SHADE) * diff

                # 形体明暗（乘性，保留材质层次）
                f = 1.0 - FORM_STRENGTH * (1.0 - shade)
                # 整帧基础方向衰减：左上亮、右下暗，统一全画面方向
                u = 0.55 * (x / W) + 0.45 * gy
                f *= (1.0 - BASE_GRAD * u)
                r = r * f; g = g * f; b = b * f

                lr, lg, lb = Lr[i], Lg[i], Lb[i]
                if lr >= 0.5 or lg >= 0.5 or lb >= 0.5:
                    yb = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                    att = 1.0 - surface_att * yb
                    # 定向：只落在受光面；沿主光方向整体衰减
                    u = 0.55 * (x / W) + 0.45 * gy
                    grad = 1.0 - GRAD_STRENGTH * u
                    dirw = (1.0 - LIGHT_DIFFUSE_BIAS) + LIGHT_DIFFUSE_BIAS * shade
                    k = att * grad * dirw
                    lr *= k; lg *= k; lb *= k
                    r = r + lr * (255 - r) / 255.0
                    g = g + lg * (255 - g) / 255.0
                    b = b + lb * (255 - b) / 255.0

                px[x, y] = (clamp8(r), clamp8(g), clamp8(b))
        return out


def tone_and_normalize(im, target_y):
    # 1) 中灰对比拉伸（真正的 S 形：暗更暗、亮更亮）
    c = 1.0 + TONE_S
    lut = [clamp8(255.0 * (0.5 + (v / 255.0 - 0.5) * c)) for v in range(256)]
    im = im.point(lut * 3)

    # 2) 亮度归一：把平均 Y 拉回目标值（限制幅度，防止剧烈失真）
    px = im.load()
    tot = 0.0
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            tot += 0.299 * r + 0.587 * g + 0.114 * b
    mean_y = tot / (W * H)
    scale = 1.0 if mean_y <= 0 else target_y / mean_y
    scale = min(1 + CLAMP_Y, max(1 - CLAMP_Y, scale))
    lut2 = [clamp8(v * scale) for v in range(256)]
    return im.point(lut2 * 3)


def build(kind):
    p = KEY[kind]
    im = grade(Image.open(SRC).convert("RGB"), p)
    lf = LightField()

    if kind == "dusk":
        fire_boost(im, 0.75)
        lf.add(320, 240, 460, 330, 0.06, WARM_CORE, WARM_EDGE, seed=101)          # 环境
        for i, (wx, wy) in enumerate(WINDOWS):                                    # 次光
            lf.add(wx, wy + 70, 26, 72, 0.30, WARM_CORE, WARM_EDGE, seed=200 + i, squint=0.26)
        lf.add(HEARTH[0], HEARTH[1] + 18, 62, 46, 0.58, WARM_CORE, WARM_EDGE, seed=301)  # 主光
        lf.add(HEARTH[0], HEARTH[1] + 2, 22, 17, 0.50, WARM_CORE, WARM_EDGE, seed=302)
    elif kind == "night":
        fire_boost(im, 1.0); night_windows(im)
        lf.add(320, 240, 470, 340, 0.05, COOL_CORE, COOL_EDGE, seed=111)
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 56, 24, 58, 0.18, COOL_CORE, COOL_EDGE, seed=210 + i, squint=0.22)
        lf.add(HEARTH[0], HEARTH[1] + 20, 70, 50, 0.82, WARM_CORE, WARM_EDGE, seed=311)
        lf.add(HEARTH[0], HEARTH[1] + 4, 26, 19, 0.64, WARM_CORE, WARM_EDGE, seed=312)
        lf.add(120, 102, 28, 20, 0.22, WARM_CORE, WARM_EDGE, seed=320)
        for i, (tx, ty) in enumerate([(214, 152), (272, 336), (472, 214), (522, 306)]):
            lf.add(tx, ty, 12, 9, 0.18, WARM_CORE, WARM_EDGE, seed=330 + i)
    elif kind == "dawn":
        fire_boost(im, 0.6)
        lf.add(320, 240, 460, 330, 0.06, COOL_CORE, COOL_EDGE, seed=121)
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 62, 24, 64, 0.22, COOL_CORE, COOL_EDGE, seed=220 + i, squint=0.20)
        lf.add(HEARTH[0], HEARTH[1] + 14, 48, 36, 0.32, WARM_CORE, WARM_EDGE, seed=321)

    nx, ny = build_normals(im)
    out = lf.composite(im, nx, ny)
    out = tone_and_normalize(out, p["target_y"])
    return out


def main():
    for kind in ("dawn", "dusk", "night"):
        im = build(kind)
        im.save(f"{OUT}/scene_{kind}_v3_1x.png")
        im.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/scene_{kind}_v3_2x.png")
        # 统计
        px = im.load(); tot = 0.0; mn = 255.0; mx = 0.0
        for y in range(0, H, 2):
            for x in range(0, W, 2):
                r, g, b = px[x, y]
                v = 0.299 * r + 0.587 * g + 0.114 * b
                tot += v; mn = min(mn, v); mx = max(mx, v)
        n = (W // 2) * (H // 2)
        print(f"{kind} v3 → {OUT}/scene_{kind}_v3_1x.png  meanY {tot/n:.1f} min {mn:.0f} max {mx:.0f}")

    # v2 | v3 对照（黄昏 + 夜晚）
    from PIL import ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 15)
    except OSError:
        font = ImageFont.load_default()
    pad, labh = 8, 24
    rows = [("dusk", "黄昏"), ("night", "夜晚")]
    out = Image.new("RGB", (W * 2 + pad * 3, (H + labh) * 2 + pad * 3), (246, 243, 235))
    d = ImageDraw.Draw(out)
    for ri, (k, zh) in enumerate(rows):
        oy = pad + ri * (H + labh + pad)
        d.text((pad, oy), f"{zh} v2", fill=(40, 36, 30), font=font)
        out.paste(Image.open(f"{OUT}/scene_{k}_v2_1x.png").convert("RGB"), (pad, oy + labh))
        d.text((pad * 2 + W, oy), f"{zh} v3（定向+层次）", fill=(40, 36, 30), font=font)
        out.paste(Image.open(f"{OUT}/scene_{k}_v3_1x.png").convert("RGB"), (pad * 2 + W, oy + labh))
    out.save(f"{OUT}/scene_v2_vs_v3.png")
    print(f"对照 → {OUT}/scene_v2_vs_v3.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
