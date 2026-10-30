#!/usr/bin/env python3
"""门板裁片：把抠开的那块**门洞**从原始底图上原样裁下来，做四张。

为什么需要它：
  为了让"酒馆 ↔ 地窖"真正连通，底图上那扇门被抠成了透明
  （`tools/punch_cellar_passage.py`），底下透出地窖的楼梯。但门不能就这么消失 ——
  所以把**抠掉的那块像素原样贴回一个精灵**盖在上面：
    · 站得远 = 这一层不透明 = 和原图一模一样，就是那扇关着的门；
    · 走近   = 这一层淡出   = 门"虚化"掉，后面地窖的楼梯露出来。
  裁的是底图自己身上的像素，**没有新画任何东西**。

范围直接 import `punch_cellar_passage.HOLE` —— 抠多大就裁多大，永远不会两边对不上。
（开口 = 门扇基准 + GROW_*，所以裁片边缘会带上几像素原本的墙，远看跟原图没差别。）

四个时段各一张：门板的亮度和周围墙一致，只做一张的话夜里会是一块白天的门。
门板叠在底图之上、昼夜过渡层之下，所以黄昏/黎明的染色照样盖到它。

用法：python tools/make_door_panel.py
产物：assets/house/v4/door_panel_{dawn,day,dusk,night}_v16.png（= 门洞逻辑尺寸 × 2）
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "assets/house/v4"
PHASES = ("dawn", "day", "dusk", "night")
VERSION = "v16"

# 单一真源：抠洞的矩形与 2× 系数都从抠洞脚本拿
sys.path.insert(0, str(Path(__file__).resolve().parent))
from punch_cellar_passage import HOLE, SCALE  # noqa: E402

# 门板只取**原木门本体**（连它那圈黑框），量自底图：黑框上沿 y42、左 x110、右 x142、下 y82。
# 注意：这里**不**用放大后的 HOLE，而是用原门本身的尺寸 —— 否则裁出来门上方会带一段门楣的墙，
# 门板看着还是原来那扇小门。裁下来后再放大到「门洞」大小，关着的时候就填满整个开口、
# 看起来就是一扇**更大**的门（放大的是原图的像素，没新画任何东西）。
DOOR_SRC = (110, 42, 143, 83)


def main() -> None:
    # 源：原木门本体（2×）
    sx0, sy0, sx1, sy1 = (v * SCALE for v in DOOR_SRC)
    # 目标：门洞尺寸（2×），门板放大后正好填满开口
    tx0, ty0, tx1, ty1 = (v * SCALE for v in HOLE)
    tw, th = tx1 - tx0, ty1 - ty0
    for phase in PHASES:
        # 必须从**原始**（未抠洞）的底图裁：.bak_passage 就是抠洞前的备份
        src = SRC_DIR / f"scene_{phase}_{VERSION}_2x.png.bak_passage"
        if not src.exists():
            src = SRC_DIR / f"scene_{phase}_{VERSION}_2x.png"
            print(f"⚠ {phase}: 没有 .bak_passage，改用当前底图（门洞已是空的，裁出来会是全透明）")
        out = SRC_DIR / f"door_panel_{phase}_{VERSION}.png"
        im = Image.open(src).convert("RGBA").crop((sx0, sy0, sx1, sy1))
        im = im.resize((tw, th), Image.NEAREST)   # 放大到门洞大小，像素风用最近邻不糊
        im.save(out)
        print(f"wrote {out.name} {im.size}（原门 {sx1-sx0}×{sy1-sy0} → 门洞 {tw}×{th}）")


if __name__ == "__main__":
    main()
