"""坐姿帧 vs 行走帧 放大对比（洋红底，暴露所有非透明残留）。
输出 tests/sit_vs_walk_zoom.png：每人一行 = [走路右 | 坐col1 | 坐col2]。"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]
S = 5
CW, CH = 60 * S, 120 * S
PAD = 10
LAB = 20

font = None
for p in ("C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/msyh.ttc"):
    try:
        font = ImageFont.truetype(p, 14)
        break
    except Exception:
        pass
if font is None:
    font = ImageFont.load_default()

W = PAD + (CW + PAD) * 3
H = PAD + (CH + LAB + PAD) * len(NAMES)
canvas = Image.new("RGB", (W, H), (24, 20, 28))
d = ImageDraw.Draw(canvas)

for r, name in enumerate(NAMES):
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    y0 = PAD + r * (CH + LAB + PAD)
    d.text((PAD, y0), name, font=font, fill=(255, 220, 160))
    cells = [
        (sheet.crop((0, 240, 60, 360)), "走路(右)"),
        (sheet.crop((60, 480, 120, 600)), "坐 col1(左)"),
        (sheet.crop((120, 480, 180, 600)), "坐 col2(右)"),
    ]
    for k, (cell, title) in enumerate(cells):
        x0 = PAD + k * (CW + PAD)
        # 洋红底：任何没被抠干净的底色都会立刻显形
        bg = Image.new("RGB", (CW, CH), (255, 0, 200))
        bg.paste(cell.resize((CW, CH), Image.NEAREST), (0, 0), cell.resize((CW, CH), Image.NEAREST))
        canvas.paste(bg, (x0, y0 + LAB))
        d.text((x0, y0 + LAB + CH + 2), title, font=font, fill=(170, 230, 255))

canvas.save(os.path.join(ROOT, "tests", "sit_vs_walk_zoom.png"))
print("saved", canvas.size)
