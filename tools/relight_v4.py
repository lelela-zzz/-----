#!/usr/bin/env python3
"""换光不换图 v4：夜晚光场大范围化 + 亮度封顶（火堆为最高亮）+ 低对比。

针对夜晚三个问题：
1. 对比度过高 → 夜晚单独把中灰拉伸降到 0.06（v3 是 0.18），并用更小的归一幅度
2. 焦点从火堆变成光球 → 给光场总量设上限 MAX_LIGHT（低于火堆亮度），
   并把小核心能量摊到大半径，避免中心堆成球
3. 覆盖范围过小 → 炉火光池半径 70/50 → 190/150，另加中/大两档叠加，
   再加 520×400 的环境底光，让暗房间里有大范围柔和照度

用法：python tools/relight_v4.py
产出：scene_{dawn,dusk,night}_v4_1x/2x.png + v3|v4 对照
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

# 每时段独立：tone_s 中灰拉伸 / target_y 目标平均亮度 / max_light 光场上限 / surface_att 亮面衰减
# grad_strength 光场方向衰减 / base_grad 底图方向衰减（夜晚调低：以炉火径向为主，不要斜锥）
KEY = {
    "dawn":  dict(ls=0.88, ss=0.96, anchor=(0x56, 0x69, 0x7E), w=0.10,
                  target_y=81.0, tone_s=0.14, max_light=190.0, surface_att=0.50,
                  grad_strength=0.24, base_grad=0.09),
    "dusk":  dict(ls=0.90, ss=1.12, anchor=(0xC2, 0x70, 0x3A), w=0.12,
                  target_y=88.0, tone_s=0.16, max_light=200.0, surface_att=0.52,
                  grad_strength=0.24, base_grad=0.09),
    "night": dict(ls=0.67, ss=0.84, anchor=(0x23, 0x2E, 0x3C), w=0.28,
                  target_y=56.0, tone_s=0.06, max_light=150.0, surface_att=0.40,
                  grad_strength=0.14, base_grad=0.04),
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

LIGHT_DIR = (-0.34, -0.86, 0.38)
NORMAL_SCALE = 0.95
NORMAL_BLUR = 2
AMBIENT_SHADE = 0.70          # 背光面保底（夜晚层次不再靠压黑）
FORM_STRENGTH = 0.18
LIGHT_DIFFUSE_BIAS = 0.62
GRAD_STRENGTH = 0.24
BASE_GRAD = 0.09
CLAMP_Y = 0.18


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


_FIRE_PIXELS = None


def fire_pixels():
    """从白天原图提取火焰像素（原图火最鲜艳，检测最可靠）。"""
    global _FIRE_PIXELS
    if _FIRE_PIXELS is None:
        im0 = Image.open(SRC).convert("RGB")
        px = im0.load()
        pts = []
        for y in range(FIRE_BOX[1], FIRE_BOX[3]):
            for x in range(FIRE_BOX[0], FIRE_BOX[2]):
                r, g, b = px[x, y]
                if r > 110 and (r - b) > 45 and (r - g) > 32:
                    pts.append((x, y))
        _FIRE_PIXELS = pts
    return _FIRE_PIXELS


def paint_fire(im, boost=1.0):
    """按到火心距离重绘火焰色阶：火心亮黄 → 边缘橙，保证最高亮。"""
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
        k = 3.2                     # 比 v3 更平缓：同半径下覆盖更远
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

    def composite(self, base, nx, ny, surface_att, max_light, grad_strength, base_grad):
        out = base.copy(); px = out.load()
        Lr, Lg, Lb = self.L
        lx, ly, lz = LIGHT_DIR
        n = math.sqrt(lx * lx + ly * ly + lz * lz)
        lx, ly, lz = lx / n, ly / n, lz / n
        knee = 0.6 * max_light          # 软封顶拐点
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
                f *= (1.0 - base_grad * u)
                r *= f; g *= f; b *= f

                lr, lg, lb = Lr[i], Lg[i], Lb[i]
                if lr >= 0.5 or lg >= 0.5 or lb >= 0.5:
                    yb = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                    k = (1.0 - surface_att * yb)
                    k *= (1.0 - grad_strength * u)
                    k *= (1.0 - LIGHT_DIFFUSE_BIAS) + LIGHT_DIFFUSE_BIAS * shade
                    lr *= k; lg *= k; lb *= k
                    # ★ 软封顶：超过拐点后渐近逼近 max_light，不产生平台
                    mx = max(lr, lg, lb)
                    if mx > knee:
                        over = mx - knee
                        newmx = knee + over / (1.0 + over / (max_light - knee))
                        s = newmx / mx
                        lr *= s; lg *= s; lb *= s
                    r = r + lr * (255 - r) / 255.0
                    g = g + lg * (255 - g) / 255.0
                    b = b + lb * (255 - b) / 255.0

                px[x, y] = (clamp8(r), clamp8(g), clamp8(b))
        return out


def tone_and_normalize(im, target_y, tone_s):
    c = 1.0 + tone_s
    lut = [clamp8(255.0 * (0.5 + (v / 255.0 - 0.5) * c)) for v in range(256)]
    im = im.point(lut * 3)
    px = im.load()
    tot = 0.0
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            tot += 0.299 * r + 0.587 * g + 0.114 * b
    mean_y = tot / (W * H)
    scale = 1.0 if mean_y <= 0 else target_y / mean_y
    scale = min(1 + CLAMP_Y, max(1 - CLAMP_Y, scale))
    return im.point([clamp8(v * scale) for v in range(256)] * 3)


def build(kind):
    p = KEY[kind]
    im = grade(Image.open(SRC).convert("RGB"), p)
    lf = LightField()

    if kind == "dusk":
        lf.add(320, 250, 480, 350, 0.08, WARM_CORE, WARM_EDGE, seed=101)
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 74, 30, 82, 0.28, WARM_CORE, WARM_EDGE, seed=200 + i, squint=0.26)
        lf.add(HEARTH[0], HEARTH[1] + 20, 96, 76, 0.42, WARM_CORE, WARM_EDGE, seed=301)
        lf.add(HEARTH[0], HEARTH[1] + 6, 34, 26, 0.30, WARM_CORE, WARM_EDGE, seed=302)
    elif kind == "night":
        night_windows(im)
        # ① 环境：暖底光托住整间屋（大范围、极低强度），再叠一层冷月光
        lf.add(320, 210, 580, 430, 0.11, WARM_CORE, WARM_EDGE, seed=111)
        lf.add(320, 300, 520, 380, 0.05, COOL_CORE, COOL_EDGE, seed=112)
        # ② 炉火：径向三层，大半径为主（覆盖大半个房间），核心不再堆成球
        lf.add(HEARTH[0], HEARTH[1] + 52, 250, 195, 0.30, WARM_CORE, WARM_EDGE, seed=311)
        lf.add(HEARTH[0], HEARTH[1] + 22, 120, 92, 0.20, WARM_CORE, WARM_EDGE, seed=312)
        lf.add(HEARTH[0], HEARTH[1] + 6, 36, 28, 0.16, WARM_CORE, WARM_EDGE, seed=313)
        # ③ 月光窗
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 60, 44, 88, 0.11, COOL_CORE, COOL_EDGE, seed=210 + i, squint=0.20)
        # ④ 吧台灯与桌面烛点：范围放大、强度降低
        lf.add(120, 104, 52, 40, 0.10, WARM_CORE, WARM_EDGE, seed=320)
        for i, (tx, ty) in enumerate([(214, 152), (272, 336), (472, 214), (522, 306)]):
            lf.add(tx, ty, 26, 20, 0.09, WARM_CORE, WARM_EDGE, seed=330 + i)
    elif kind == "dawn":
        lf.add(320, 250, 480, 350, 0.08, COOL_CORE, COOL_EDGE, seed=121)
        for i, (wx, wy) in enumerate(WINDOWS):
            lf.add(wx, wy + 64, 30, 70, 0.20, COOL_CORE, COOL_EDGE, seed=220 + i, squint=0.20)
        lf.add(HEARTH[0], HEARTH[1] + 16, 72, 56, 0.26, WARM_CORE, WARM_EDGE, seed=321)

    nx, ny = build_normals(im)
    out = lf.composite(im, nx, ny, p["surface_att"], p["max_light"],
                       p["grad_strength"], p["base_grad"])
    out = tone_and_normalize(out, p["target_y"], p["tone_s"])
    # ★ 火焰最后重绘：不参与归一压暗，保证始终是画面最高亮
    paint_fire(out, 1.35 if kind == "night" else 0.95)
    return out


def main():
    for kind in ("dawn", "dusk", "night"):
        im = build(kind)
        im.save(f"{OUT}/scene_{kind}_v4_1x.png")
        im.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/scene_{kind}_v4_2x.png")
        # 峰值位置：确认落在火堆
        px = im.load()
        best = (-1, 0, 0)
        for y in range(H):
            for x in range(W):
                r, g, b = px[x, y]
                v = 0.299 * r + 0.587 * g + 0.114 * b
                if v > best[0]:
                    best = (v, x, y)
        # 对比度
        vals = []
        for y in range(0, H, 2):
            for x in range(0, W, 2):
                r, g, b = px[x, y]
                vals.append(0.299 * r + 0.587 * g + 0.114 * b)
        m = sum(vals) / len(vals)
        sd = math.sqrt(sum((v - m) ** 2 for v in vals) / len(vals))
        vals.sort()
        print(f"{kind} v4 → meanY {m:.1f} sd {sd:.1f} p10 {vals[int(len(vals)*.1)]:.0f} "
              f"p90 {vals[int(len(vals)*.9)]:.0f} 峰值 @({best[1]},{best[2]}) Y={best[0]:.0f}")

    # v3 | v4 对照（夜晚，重点）
    from PIL import ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 15)
    except OSError:
        font = ImageFont.load_default()
    pad, labh = 8, 24
    out = Image.new("RGB", (W * 2 + pad * 3, H + labh + pad * 2), (246, 243, 235))
    d = ImageDraw.Draw(out)
    d.text((pad, 4), "夜晚 v3", fill=(40, 36, 30), font=font)
    out.paste(Image.open(f"{OUT}/scene_night_v3_1x.png").convert("RGB"), (pad, labh))
    d.text((pad * 2 + W, 4), "夜晚 v4（大范围/低对比/火堆为主）", fill=(40, 36, 30), font=font)
    out.paste(Image.open(f"{OUT}/scene_night_v4_1x.png").convert("RGB"), (pad * 2 + W, labh))
    out.save(f"{OUT}/scene_night_v3_vs_v4.png")
    print(f"对照 → {OUT}/scene_night_v3_vs_v4.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
