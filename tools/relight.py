#!/usr/bin/env python3
"""换光不换图：对已验收的白天底图套用 v4 昼夜参数（结构 0 改动）。

依据 `炉火镇-昼夜与季节调色规格.md`：
- 世界材质：HSL 明度 ×ls、饱和 ×ss，再向 anchor 混 w
- 明度下限 L_FLOOR=4（防暗部压死并阶）
- 火色不服从压暗：火焰像素直接按火色板重绘，保证夜间最高亮度落在火上
- 光池用「实色多档衰减 + 棋盘抖动」，不用半透明渐变（像素风一致）

用法：python tools/relight.py
产出：scene_dawn / scene_dusk / scene_night 的 1x(640×384) + 2x(1280×768)
"""
from __future__ import annotations

import colorsys
from PIL import Image

SRC = "assets/house/v4/scene_day_1x.png"
OUT = "assets/house/v4"
W, H = 640, 384
L_FLOOR = 4.0 / 100.0

# 四个关键帧（world 层参数，取自 palette v4 keyframes）
KEY = {
    "dawn":  dict(ls=0.88, ss=0.96, anchor=(0x56, 0x69, 0x7E), w=0.10),
    "dusk":  dict(ls=0.90, ss=1.12, anchor=(0xC2, 0x70, 0x3A), w=0.12),
    "night": dict(ls=0.67, ss=0.84, anchor=(0x23, 0x2E, 0x3C), w=0.28),
}

# 窗（4 扇）与壁炉在 640×384 中的实测位置
WINDOWS = [(192, 28), (245, 28), (387, 28), (444, 28)]
HEARTH = (316, 67)          # 炉膛火心
FIRE_BOX = (298, 53, 336, 82)   # 火焰像素搜索框
FIRE_MID = (242, 150, 50)       # #F29632 夜里会再亮（此处用中间值）
FIRE_CORE = (252, 210, 132)     # #FCD284


def clamp8(v: float) -> int:
    return 0 if v < 0 else (255 if v > 255 else int(v))


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


def fire_boost(im: Image.Image, boost: float = 1.0) -> None:
    """炉膛红色像素按火色板重绘：暗红→火橙，亮红→火心黄。"""
    px = im.load()
    x0, y0, x1, y1 = FIRE_BOX
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if r > 80 and (r - b) > 28 and (r - g) > 15:
                t = min(1.0, max(0.0, (r - 80) / 120.0))
                t = min(1.0, t * boost)
                # 在 fire-mid 与 fire-core 间插值
                tr = FIRE_MID[0] * (1 - t) + FIRE_CORE[0] * t
                tg = FIRE_MID[1] * (1 - t) + FIRE_CORE[1] * t
                tb = FIRE_MID[2] * (1 - t) + FIRE_CORE[2] * t
                px[x, y] = (clamp8(tr), clamp8(tg), clamp8(tb))


WIN_BOXES = [(180, 14, 208, 40), (232, 14, 260, 40),
             (374, 14, 402, 40), (430, 14, 458, 40)]


def night_windows(im: Image.Image) -> None:
    """夜里窗外是暗的：玻璃蓝像素压成深夜蓝灰（保留一点微光）。"""
    px = im.load()
    for (x0, y0, x1, y1) in WIN_BOXES:
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b = px[x, y]
                if b > r + 8 and b > 90:
                    k = 0.30 if b < 145 else 0.48     # 越亮的格子留一点微光
                    px[x, y] = (clamp8(r * k + 38 * (1 - k)),
                                clamp8(g * k + 52 * (1 - k)),
                                clamp8(b * k + 74 * (1 - k)))


def add_pool(im: Image.Image, cx: float, cy: float, rx: float, ry: float,
             color: tuple[int, int, int], strength: float,
             levels: int = 5, squash: float = 0.0) -> None:
    """实色多档加色光池：t∈(0,1] 分 levels 档，最外两档棋盘抖动消色带。"""
    px = im.load()
    cr, cg, cb = color
    x0, x1 = max(0, int(cx - rx)), min(W - 1, int(cx + rx))
    y0, y1 = max(0, int(cy - ry)), min(H - 1, int(cy + ry))
    inv_rx, inv_ry = 1.0 / rx, 1.0 / ry
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            dx = (x - cx) * inv_rx
            dy = (y - cy) * inv_ry
            if squash:
                dx += dy * squash
            d2 = dx * dx + dy * dy
            if d2 >= 1.0:
                continue
            t = 1.0 - d2
            q = int(t * levels) / levels
            if q <= 0.0:
                continue
            if q < 2.0 / levels and (x + y) % 2:   # 外两档抖动
                continue
            amt = strength * q
            r, g, b = px[x, y]
            px[x, y] = (clamp8(r + cr * amt), clamp8(g + cg * amt), clamp8(b + cb * amt))


def relight(kind: str) -> Image.Image:
    im = grade(Image.open(SRC).convert("RGB"), KEY[kind])

    if kind == "dusk":
        fire_boost(im, 0.75)
        for (wx, wy) in WINDOWS:
            add_pool(im, wx, wy + 62, 27, 74, (250, 172, 96), 0.24, levels=6, squash=0.24)
        add_pool(im, HEARTH[0], HEARTH[1] + 14, 52, 40, (255, 150, 70), 0.20, levels=6)
        add_pool(im, HEARTH[0], HEARTH[1] + 4, 24, 18, (255, 200, 120), 0.22, levels=3)
    elif kind == "night":
        fire_boost(im, 1.0)
        night_windows(im)
        for (wx, wy) in WINDOWS:
            add_pool(im, wx, wy + 52, 22, 56, (110, 140, 178), 0.09, levels=6, squash=0.18)
        # 炉火：中心偏下（落在吧台前与地面），小半径高强度
        add_pool(im, HEARTH[0], HEARTH[1] + 16, 56, 40, (255, 132, 54), 0.24, levels=6)
        add_pool(im, HEARTH[0], HEARTH[1] + 6, 26, 19, (255, 196, 112), 0.26, levels=4)
        # 远弱的小灯（吧台/桌面），不得亮过炉火
        add_pool(im, 120, 100, 24, 18, (255, 176, 96), 0.09, levels=5)
        for (tx, ty) in [(214, 152), (272, 336), (472, 214), (522, 306)]:
            add_pool(im, tx, ty, 7, 6, (255, 186, 104), 0.10, levels=3)
    elif kind == "dawn":
        fire_boost(im, 0.6)
        for (wx, wy) in WINDOWS:
            add_pool(im, wx, wy + 54, 22, 58, (140, 164, 200), 0.11, levels=6, squash=0.18)
        add_pool(im, HEARTH[0], HEARTH[1] + 8, 42, 32, (255, 160, 92), 0.13, levels=5)
    return im


def main() -> int:
    for kind in ("dawn", "dusk", "night"):
        im = relight(kind)
        im.save(f"{OUT}/scene_{kind}_1x.png")
        im.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/scene_{kind}_2x.png")
        # 亮度统计，校验夜间峰值是否落在火区
        px = im.load()
        mx = 0; mxpos = (0, 0)
        for y in range(0, H):
            for x in range(0, W):
                r, g, b = px[x, y]
                v = r + g + b
                if v > mx:
                    mx = v; mxpos = (x, y)
        print(f"{kind}: 1x {OUT}/scene_{kind}_1x.png  峰值亮像素@{mxpos} (sum={mx})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
