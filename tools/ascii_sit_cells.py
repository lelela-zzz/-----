"""逐个打印 4 位顾客的坐姿帧（行4 的 col1/col2），ASCII 色类图，找浅灰矩形残留。"""
from PIL import Image
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]


def cls(p):
    r, g, b, a = p
    if a < 30:
        return "."
    mx, mn = max(r, g, b), min(r, g, b)
    sat = 0 if mx == 0 else (mx - mn) / mx
    if sat > 0.28:
        return "C"
    if mx < 70:
        return "#"
    if mx < 130:
        return "o"
    if mx < 200:
        return "O"
    return "*"


for name in NAMES:
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    print("=" * 70)
    print(name, sheet.size)
    for col, tag in ((1, "col1 朝左"), (2, "col2 朝右")):
        cell = sheet.crop((col * 60, 480, col * 60 + 60, 600))
        px = cell.load()
        print("-" * 70)
        print("  %s  (x=%d..%d)" % (tag, col * 60, col * 60 + 60))
        for y in range(0, 120, 2):
            print("  %3d %s" % (y, "".join(cls(px[x, y]) for x in range(60))))
