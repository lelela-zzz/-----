#!/usr/bin/env python3
"""把酒馆左上角那扇门的**门洞**抠成透明，好让地窖的楼梯从门里透出来。

背景：酒馆与地窖要做成一张连续地图（地窖图在酒馆图上方），玩家从店堂走到左上角
那扇门，直接迈上地窖那段原有楼梯 —— 不再切地图。但那扇门在底图上"画死了"，
是一块不透明的门板，得先把门的像素擦掉（alpha=0），后面的地窖底图才透得出来。

**范围锁定在"门"这一块**（用户 2026-10-28："虚化只包含木门"），再由 `GROW_*`
往外扩一圈 —— 原点那扇画好的门只有 33×41，玩家走上去脚会蹭到门楣那段墙，
所以要把开口放大一点，但绝不能一路扩到墙顶（那就变成墙上挖了个方洞）。

  · 基准 = 底图上量出来的门扇（`DOOR_RECT`，连它自己那圈黑边），**锁死不动**；
  · 开口 = 基准 + `GROW_SIDE` / `GROW_TOP` 的外扩，见下面注释；
  · 门楣上沿以上的墙、扩圈以外的左右墙面，一个像素都不动。

**不是画图**：一个像素都没新增，只是把现有的门擦掉。原图另存 `*.bak_passage`，
随时可 `--restore` 还原。擦完再跑 `tools/make_door_panel.py` 把这块像素做成
可淡出的精灵盖回来（远看是门，走近淡出 → 门"虚化"）。

改完这一个文件，`make_door_panel.py` 会直接 import 这里的 `HOLE`，不会两边对不上。

用法：
  python tools/punch_cellar_passage.py            # 抠洞（幂等，总是从 .bak_passage 起步）
  python tools/punch_cellar_passage.py --restore  # 从备份还原
产物：原地修改 assets/house/v4/scene_{dawn,day,dusk,night}_v16_2x.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "assets/house/v4"
PHASES = ("dawn", "day", "dusk", "night")
VERSION = "v16"

# 底图上那扇门本身（逻辑坐标，右/下开区间）。量自 scene_day_v16_2x.png：
# 黑边上沿 y42..43、左黑边 x110..111、右黑边 x142、下沿 y82。
# **这是基准，别改** —— 改开口大小用下面的 GROW_*。
DOOR_RECT = (110, 42, 143, 83)

# 开口在基准门框外再扩多少（逻辑像素）。
GROW_SIDE = 4    # 左右各 4 → 宽度 33 → 41
GROW_TOP = 14    # 上面 14 → 高度 41 → 55（门楣以上的墙还剩 16px）
# 往下不能扩：y=83 已经是店堂地板的第一行，再往下会把地板也挖穿。

HOLE = (DOOR_RECT[0] - GROW_SIDE, DOOR_RECT[1] - GROW_TOP,
        DOOR_RECT[2] + GROW_SIDE, DOOR_RECT[3])   # x0, y0, x1, y1（右/下开区间）
SCALE = 2                                         # 底图是 2× 源


def tex_path(phase: str) -> Path:
    return SRC_DIR / f"scene_{phase}_{VERSION}_2x.png"


def backup_path(phase: str) -> Path:
    return SRC_DIR / f"scene_{phase}_{VERSION}_2x.png.bak_passage"


def punch() -> None:
    x0, y0, x1, y1 = (v * SCALE for v in HOLE)
    for phase in PHASES:
        p = tex_path(phase)
        b = backup_path(phase)
        if not p.exists():
            print("跳过（缺文件）", p.name)
            continue
        if not b.exists():
            b.write_bytes(p.read_bytes())
        im = Image.open(b).convert("RGBA")
        px = im.load()
        w, h = im.size
        cleared = 0
        for y in range(y0, min(y1, h)):
            for x in range(x0, min(x1, w)):
                if px[x, y][3] != 0:
                    px[x, y] = (0, 0, 0, 0)
                    cleared += 1
        im.save(p)
        print(f"{p.name}: 抠掉 {cleared} 个像素，门洞逻辑坐标 {HOLE}")


def restore() -> None:
    for phase in PHASES:
        p = tex_path(phase)
        b = backup_path(phase)
        if b.exists():
            p.write_bytes(b.read_bytes())
            print("已还原", p.name)
        else:
            print("没有备份，跳过", p.name)


if __name__ == "__main__":
    if "--restore" in sys.argv:
        restore()
    else:
        punch()
