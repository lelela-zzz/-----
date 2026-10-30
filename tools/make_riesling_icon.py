"""生成「雷司令」的物品图标（64×64 深绿玻璃酒瓶）。

为什么要单独一张：爱德华的支线台词是「我带来了利塞布尔的名酒雷司令，作为等价
交换」—— 这句里的道具交换以前只是嘴上说说。要真的把酒塞进玩家背包，就得有
一个能上酒单（kind=wine）、有价、有图标的物品。现有 5 支酒图标全是木桶/酒杯，
没有瓶装的，所以照同一套配色现画一个。

配色取自 assets/items/wines/ 里的现有图标（奶白标签、近黑描边、木色高光），
保证摆进物品列表时不突兀。

跑法： python tools/make_riesling_icon.py
输出： assets/items/wines/wine_riesling.png
"""

import os

from PIL import Image

SIZE = 64
CX = 32

OUTLINE = (26, 20, 16, 255)
GLASS_DARK = (28, 50, 36, 255)
GLASS_MID = (42, 72, 50, 255)
GLASS_LIGHT = (68, 104, 74, 255)
GLASS_SHINE = (104, 142, 102, 255)
CORK_DARK = (78, 50, 30, 255)
CORK_LIGHT = (176, 138, 92, 255)
LABEL = (232, 222, 198, 255)
LABEL_TRIM = (170, 136, 78, 255)
LABEL_INK = (74, 58, 44, 255)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(ROOT, "assets", "items", "wines", "wine_riesling.png")


def half_width(y: int) -> int:
    """这一行瓶身的半宽（含描边）。0 = 这一行没有瓶身。"""
    if y < 4:
        return 0
    if y <= 8:          # 软木塞
        return 4
    if y <= 10:         # 瓶口凸边
        return 5
    if y <= 17:         # 瓶颈
        return 4
    if y <= 26:         # 溜肩：4 → 13
        t = (y - 17) / 9.0
        return int(round(4 + (13 - 4) * t))
    if y <= 58:         # 瓶身
        return 13
    return {59: 12, 60: 9, 61: 6}.get(y, 0)   # 圆底


def row_color(x: int, hw: int, y: int) -> tuple:
    left = CX - hw
    span = 2 * hw - 1
    t = (x - left) / float(max(1, span))
    if x == left or x == left + hw * 2 - 1:
        return OUTLINE
    if t < 0.16:
        return GLASS_SHINE
    if t < 0.34:
        return GLASS_LIGHT
    if t < 0.66:
        return GLASS_MID
    return GLASS_DARK


def main() -> None:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()

    for y in range(SIZE):
        hw = half_width(y)
        if hw <= 0:
            continue
        for x in range(CX - hw, CX + hw):
            if y <= 8:
                # 软木塞：左亮右暗，塞口一圈深色
                px[x, y] = OUTLINE if (x == CX - hw or x == CX + hw - 1) else \
                    (CORK_LIGHT if x < CX else CORK_DARK)
            elif y == 10:
                px[x, y] = OUTLINE if (x in (CX - hw, CX + hw - 1)) else GLASS_SHINE
            else:
                px[x, y] = row_color(x, hw, y)

    # 标签：奶白底 + 上下烫金线 + 三行参差的墨字（像印上去的小字）
    hw = 13
    top, bottom = 32, 48
    lx0, lx1 = CX - hw + 3, CX + hw - 4      # 22 .. 41
    for y in range(top, bottom + 1):
        for x in range(lx0, lx1 + 1):
            px[x, y] = LABEL_TRIM if y in (top, bottom) else LABEL

    strokes = {
        36: [(lx0 + 2, lx0 + 7), (lx0 + 9, lx1 - 2)],
        37: [(lx0 + 2, lx0 + 7), (lx0 + 9, lx1 - 2)],
        40: [(lx0 + 5, lx1 - 5)],
        41: [(lx0 + 5, lx1 - 5)],
        44: [(lx0 + 2, lx0 + 5), (lx0 + 7, lx0 + 10)],
        45: [(lx0 + 2, lx0 + 5), (lx0 + 7, lx0 + 10)],
    }
    for y, spans in strokes.items():
        for a, b in spans:
            for x in range(a, b + 1):
                px[x, y] = LABEL_INK

    img.save(OUT_PATH)
    print("saved", os.path.relpath(OUT_PATH, ROOT), img.size)


if __name__ == "__main__":
    main()
