#!/usr/bin/env python3
"""程序化绘制家具资产（逐像素可控，严格落在色板色阶上）。

直接在 1x 尺寸绘制，保证硬边；再导出 @2x。
色值全部取自 hearthvale-palette-v4.json 的木料/金属/结构族。
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw

# 色板（结构 + 木 + 金属）
OUTLINE = (0x3A, 0x2A, 0x22)   # 深褐，木制品的描边比纯黑更自然
DARK = (0x50, 0x38, 0x18)      # 深木
MID = (0x78, 0x50, 0x28)       # 中木
LIGHT = (0x90, 0x68, 0x38)     # 浅木
HI = (0xB0, 0x84, 0x50)        # 磨亮高光木（板缘受光/旧物被磨滑处）
METAL = (0x7A, 0x82, 0x90)     # 金属暗
METAL_HI = (0xC9, 0xCE, 0xD6)  # 金属亮

TILE = 32


def new(w: int, h: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def contact_shadow(im: Image.Image, x0: int, y0: int, x1: int, y1: int) -> None:
    """贴底接触阴影（垫在最底层）：淡影池 + 底缘加浓，让家具在 AI 背景木纹上"落地"。"""
    d = ImageDraw.Draw(im)
    d.rectangle([x0, y1 - 2, x1, y1 - 1], fill=(0, 0, 0, 50))    # 淡影池
    d.rectangle([x0, y1 - 1, x1, y1], fill=(0, 0, 0, 110))       # 底缘加浓


def paste_rounded(base: Image.Image, layer: Image.Image, box, radius: int) -> None:
    """把 layer 裁进一个圆角矩形区域，实现"边缘圆润"。"""
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    solid = layer.getchannel("A").point(lambda v: 255 if v > 0 else 0)
    base.paste(layer, (0, 0), ImageChops.multiply(mask, solid))


def table(w_t: int = 2, h_t: int = 1) -> Image.Image:
    """长餐桌：圆角桌面（3 条木板）+ 前沿厚度 + 两条前腿。"""
    W, H = w_t * TILE, h_t * TILE
    im, _ = new(W, H)

    # 接触阴影先垫底
    contact_shadow(im, 2, 0, W - 3, H - 1)

    # ── 桌面块画在独立图层，再用圆角遮罩裁入 ──
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle([0, 0, W - 1, 22], fill=OUTLINE)
    d.rectangle([1, 1, W - 2, 18], fill=LIGHT)   # 顶面：浅木（比 AI 地板亮一档）
    d.line([1, 19, W - 2, 19], fill=DARK)        # 顶面→前立面折痕
    d.rectangle([1, 20, W - 2, 21], fill=MID)    # 前立面 2px：中木（读出台面厚度）

    # 3 条木板：每板顶缘 1px 磨亮高光 + 板缝深线 —— 经典像素木纹节奏
    d.line([1, 7, W - 2, 7], fill=DARK)
    d.line([1, 13, W - 2, 13], fill=DARK)
    for ty in (1, 8, 14):
        d.line([1, ty, W - 2, ty], fill=HI)

    # 稀疏木纹：中木短刻（密度让位给 HI 高光线，减到 5 处）
    for gx, gy, gl in ((12, 4, 3), (34, 10, 4), (52, 5, 2), (20, 16, 3), (44, 17, 2)):
        d.line([gx, gy, gx + gl - 1, gy], fill=MID)

    # 使用痕迹：木节 + 左沿缺口
    d.rectangle([44, 4, 46, 5], fill=DARK)
    d.rectangle([1, 10, 2, 11], fill=DARK)

    paste_rounded(im, layer, (0, 0, W - 1, 22), radius=4)

    # ── 两条前腿 y23..31（中间透空，能看见地板）──
    # 腿身用中木：地板是深木，腿若也用深木会直接消失（同屏测试暴露）
    d2 = ImageDraw.Draw(im)
    for x0, x1 in ((5, 10), (53, 58)):
        d2.rectangle([x0, 23, x1, 31], fill=OUTLINE)
        d2.rectangle([x0 + 1, 23, x1 - 1, 31], fill=MID)
        d2.line([x1 - 2, 23, x1 - 2, 31], fill=DARK)   # 右侧背光
        d2.line([x0 + 1, 23, x0 + 1, 31], fill=HI)     # 左缘受光

    return im


def bench(w_t: int = 2, h_t: int = 1) -> Image.Image:
    """长凳：圆角座板（两块不同木色）+ 两条短腿。"""
    W, H = w_t * TILE, h_t * TILE
    im, _ = new(W, H)

    x0, x1 = 4, W - 5
    y0 = 14
    seat_b = 26            # 座板底边：整块 13px 高（比上一版 18px 缩了一圈）

    # 接触阴影先垫底
    contact_shadow(im, x0, 0, x1, H - 1)

    # ── 座板画在独立图层，圆角裁入 ──
    # 层序（13px 座板）：描边1 + 上板5(换过的板) + 缝1 + 下板3 + 折痕1 + 前立面1
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle([x0, y0, x1, seat_b], fill=OUTLINE)
    # 上板：颜色深一档（换过的一块板，这就是"旧"的痕迹）+ 顶缘磨亮
    d.rectangle([x0 + 1, y0 + 1, x1 - 1, y0 + 5], fill=MID)
    d.line([x0 + 1, y0 + 1, x1 - 1, y0 + 1], fill=HI)
    # 板缝（钉头后补）
    d.line([x0 + 1, y0 + 6, x1 - 1, y0 + 6], fill=DARK)
    # 下板：浅木满 3px（旧板被磨亮/受光）+ 顶缘受光
    d.rectangle([x0 + 1, y0 + 7, x1 - 1, y0 + 9], fill=LIGHT)
    d.line([x0 + 1, y0 + 7, x1 - 1, y0 + 7], fill=HI)
    # 折痕 + 前立面 1px
    d.line([x0 + 1, y0 + 10, x1 - 1, y0 + 10], fill=DARK)
    d.rectangle([x0 + 1, y0 + 11, x1 - 1, seat_b - 1], fill=MID)
    # 板缝两端的钉头
    for nx in (x0 + 4, x1 - 4):
        layer.putpixel((nx, y0 + 6), METAL)
    # 左端磨损
    for x, y in [(x0 + 1, y0 + 1), (x0 + 2, y0 + 1), (x0 + 1, y0 + 2)]:
        layer.putpixel((x, y), DARK)

    paste_rounded(im, layer, (x0, y0, x1, seat_b), radius=2)

    # ── 两条短凳腿 y27..31 ──
    d2 = ImageDraw.Draw(im)
    for lx0, lx1 in ((x0 + 7, x0 + 12), (x1 - 12, x1 - 7)):
        d2.rectangle([lx0, seat_b + 1, lx1, H - 1], fill=OUTLINE)
        d2.rectangle([lx0 + 1, seat_b + 1, lx1 - 1, H - 1], fill=MID)
        d2.line([lx0 + 1, seat_b + 1, lx0 + 1, H - 1], fill=HI)
        d2.line([lx1 - 2, seat_b + 1, lx1 - 2, H - 1], fill=DARK)

    return im


def barrel(size: int = 1) -> Image.Image:
    """酒桶（俯视）：厚桶壁 + 平行木板盖 + 上方受光的板色分带（不用金属环，避免读成盾牌）。"""
    W = H = size * TILE
    im, d = new(W, H)

    # 接触阴影先垫底（桶底椭圆淡影；后面整体下移 1px 贴底，阴影跟着走）
    d.ellipse([-1, 26, W, 31], fill=(0, 0, 0, 50))
    d.ellipse([1, 28, W - 2, 31], fill=(0, 0, 0, 110))

    # 外轮廓 → 桶壁（4px 厚环，读得出是"桶"不是"盘"）
    d.ellipse([0, 0, W - 1, H - 1], fill=OUTLINE)
    d.ellipse([1, 1, W - 2, H - 2], fill=DARK)

    lid = (5, 5, W - 6, H - 6)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse(lid, fill=255)

    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    dl.ellipse(lid, fill=LIGHT)   # 盖面提亮一档（比 AI 地板亮，避免被吞）
    # 桶盖木板：4 条等距平行横线，把盖面分成 5 条板；顶板受光 1px
    for y in (9, 13, 18, 22):
        dl.line([0, y, W, y], fill=DARK)
    dl.line([0, 6, W, 6], fill=HI)
    im.paste(layer, (0, 0), mask)

    # 盖沿一圈深色收边
    d.ellipse(lid, outline=DARK, width=1)

    return im


def export(im: Image.Image, out_dir: str, name: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    p1 = os.path.join(out_dir, f"{name}@1x.png")
    im.save(p1)
    im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(
        os.path.join(out_dir, f"{name}@2x.png"))
    print(f"  {name}: {im.width}×{im.height} → {p1}")


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/house/v3/sprites"
    print("程序化绘制：")
    export(table(), out, "table_old_2x1_down")
    export(bench(), out, "bench_old_2x1_down")
    export(barrel(), out, "barrel_1x1_down")
    return 0


if __name__ == "__main__":
    sys.exit(main())
