#!/usr/bin/env python3
"""把 item/ 里的「酿酒锅」图标加工成场景道具贴图（空 / 有料 × 四时段）。

为什么需要单独一套：
  图标是 80×80 带留白的 UI 资产，直接摆进场景会有 10px 空边、且只有白天一种色。
  场景道具要满足项目约定 —— 贴图尺寸即屏幕尺寸、四时段各一张、跟着背景一起换。

染色怎么来的（这条最容易搞错）：
  背景的四个时段是离线重打光烘焙的，家具跟着背景换图；而**角色的环境色**
  （LightingDirector 里的 ambient 0.64/0.60/0.66）是给动态层的，直接拿来乘
  场景道具会把它压成一块黑饼。
  正确做法是测出"同一块地面在各时段相对白天暗了多少"，把这个比值套到锅上 ——
  锅就永远和它脚下那块地板同步变。所以这里从底图上实测，别写死。

  量取区域选锅左边那块纯地板 (448,120)-(472,160)：避开酒桶（右缘 446）、
  圆桌（上缘 160）和壁柜（下缘 114），取到的就是纯地面。

用法：python tools/make_brewing_pot.py
产物：assets/items/pot/pot_{empty,full}[_dawn|_dusk|_night].png
"""
from __future__ import annotations

from PIL import Image, ImageStat

SRC = {
    "empty": "item/酒/酿酒锅(空).png",
    "full": "item/酒/酿酒锅.png",
}
OUT = "assets/items/pot"
CROP = (10, 0, 70, 80)

FRAMES = {
    "dawn": "assets/house/v4/scene_dawn_v15_1x.png",
    "dusk": "assets/house/v4/scene_dusk_v15_1x.png",
    "night": "assets/house/v4/scene_night_v15_1x.png",
}
DAY = "assets/house/v4/scene_day_v15_1x.png"
PATCH = (448, 120, 472, 160)


def relight_ratio(path: str, day_mean: list[float]) -> tuple[float, float, float]:
    mean = ImageStat.Stat(Image.open(path).convert("RGB").crop(PATCH)).mean
    return tuple(mean[i] / day_mean[i] for i in range(3))


def tint(im: Image.Image, k: tuple[float, float, float]) -> Image.Image:
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = (min(255, round(r * k[0])),
                        min(255, round(g * k[1])),
                        min(255, round(b * k[2])), a)
    return im


def main() -> int:
    day_mean = ImageStat.Stat(Image.open(DAY).convert("RGB").crop(PATCH)).mean
    ratios = {key: relight_ratio(path, day_mean) for key, path in FRAMES.items()}
    for key, k in ratios.items():
        print(f"{key}: 相对白天 x({k[0]:.3f}, {k[1]:.3f}, {k[2]:.3f})")

    for state, path in SRC.items():
        day = Image.open(path).convert("RGBA").crop(CROP)
        assert day.size == (60, 80), f"{path} 裁切后尺寸异常：{day.size}"
        day.save(f"{OUT}/pot_{state}.png")
        for key in FRAMES:
            tint(day.copy(), ratios[key]).save(f"{OUT}/pot_{state}_{key}.png")
        print(f"pot_{state}: 1 张白天 + {len(FRAMES)} 张时段")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
