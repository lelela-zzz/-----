#!/usr/bin/env python3
"""纯裁切：raw AI 原图 → 640×384 蓝本图。无任何后处理（用户要求去除管线效果）。"""
from PIL import Image, ImageDraw

RAW = "assets/house/v3/raw/Pixel_art_game_background__the_2026-10-18T09-36-01.png"
OUT1 = "assets/house/v3/scene_ai_1x_nopalette.png"
OUT2 = "assets/house/v3/scene_ai_2x.png"
CROP = (106, 40, 1386, 808)   # 1280×768 = 640×384 的整 2 倍


def main() -> int:
    raw = Image.open(RAW).convert("RGB")
    ImageDraw.Draw(raw).rectangle([1380, 930, 1536, 1024], fill=(30, 30, 32))
    small = raw.crop(CROP).resize((640, 384), Image.NEAREST)
    small.save(OUT1)
    small.resize((1280, 768), Image.NEAREST).save(OUT2)
    print("纯蓝本已重切 →", OUT1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
