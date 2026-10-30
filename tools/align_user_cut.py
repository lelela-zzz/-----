#!/usr/bin/env python3
"""把用户精修 alpha 配准回背景，重建与背景逐像素一致的精灵。

用户精修图经过 1.18x 重采样往返，逐件有 1-2px 漂移 → 游戏里"图层没对齐"。
本脚本对每件精灵：
  1. 在 ±4px 范围内搜索使 |背景 - 用户图| 最小的平移（只统计不透明像素）
  2. alpha 平移对齐后，RGB 一律取背景原图像素 —— 抠图层与背景层逐像素一致
  3. 用对齐后的 alpha 重派生 dawn/dusk/night 三张时段贴图

用法：python tools/align_user_cut.py
产物：assets/village/v1/objects/*.png（重写）+ exports/user_cut_preview.png
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
OBJ_DIR = ROOT / "assets/village/v1/objects"
SRC = ROOT / "assets/village/v1/scene_day_1x.png"
FRAMES = {
    "dawn": ROOT / "assets/village/v1/scene_dawn_1x.png",
    "dusk": ROOT / "assets/village/v1/scene_dusk_1x.png",
    "night": ROOT / "assets/village/v1/scene_night_1x.png",
}
SEARCH = 4  # 配准搜索半径（px）


def best_shift(bg: Image.Image, user: Image.Image) -> tuple[int, int, float]:
    """搜索 (sx,sy)：user(x,y) 对齐到 bg(x+sx, y+sy)。返回 (sx, sy, 平均差)。"""
    w, h = user.size
    best = (0, 0, 1e9)
    for sy in range(-SEARCH, SEARCH + 1):
        for sx in range(-SEARCH, SEARCH + 1):
            # 用户图与平移后背景的有效交集
            bx0, by0 = max(0, sx), max(0, sy)
            bx1, by1 = min(w, w + sx), min(h, h + sy)
            if bx1 - bx0 < w * 0.5 or by1 - by0 < h * 0.5:
                continue
            bg_crop = bg.crop((bx0, by0, bx1, by1))
            us_crop = user.crop((bx0 - sx, by0 - sy, bx1 - sx, by1 - sy))
            a = us_crop.getchannel("A")
            diff = ImageChops.difference(bg_crop, us_crop.convert("RGB")).convert("L")
            masked = ImageChops.multiply(diff, a)
            st = ImageStat.Stat(masked)
            score = st.mean[0] + st.stddev[0] * 0.25
            if score < best[2]:
                best = (sx, sy, score)
    return best


def main() -> int:
    day = Image.open(SRC).convert("RGB")
    frames = {k: Image.open(v).convert("RGB") for k, v in FRAMES.items()}
    props = json.loads((OBJ_DIR / "props.json").read_text(encoding="utf-8"))["props"]

    canvas = Image.new("RGBA", day.size, (24, 26, 32, 255))
    for p in props:
        if not p.get("has_sprite"):
            continue
        name = p["name"]
        rect = p["sprite_rect"]
        x, y, w, h = rect
        user = Image.open(OBJ_DIR / f"{name}.png").convert("RGBA")
        bg = day.crop((x, y, x + w, y + h))

        sx, sy, score = best_shift(bg, user)
        if (sx, sy) != (0, 0):
            print(f"{name}: 平移 ({sx:+d},{sy:+d}) 残差 {score:.1f}")
        else:
            print(f"{name}: 已对齐 (0,0) 残差 {score:.1f}")

        # alpha 平移对齐（新 alpha(x,y) = 旧 alpha(x - sx, y - sy)）
        a = user.getchannel("A")
        na = Image.new("L", (w, h), 0)
        na.paste(a, (sx, sy))
        out = bg.convert("RGBA")
        out.putalpha(na)
        out.save(OBJ_DIR / f"{name}.png")

        for phase, frame in frames.items():
            color = frame.crop((x, y, x + w, y + h)).convert("RGBA")
            color.putalpha(na)
            color.save(OBJ_DIR / f"{name}_{phase}.png")

        canvas.alpha_composite(out, (x, y))

    out_png = ROOT / "exports/user_cut_preview.png"
    canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST).save(out_png)
    print(f"预览 -> {out_png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
