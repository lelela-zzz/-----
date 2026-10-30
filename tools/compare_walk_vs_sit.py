from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]
# walk_right = 行2 (y240) col0 ; sit col1 = 行4 col1 ; sit col2 = 行4 col2
S = 4
cw, ch = 60 * S, 120 * S
pad = 14
lab = 24
rowW = (cw + pad) * 3 + pad
W = rowW
H = pad + (ch + lab + pad) * len(NAMES)
canvas = Image.new("RGB", (W, H), (30, 24, 20))
d = ImageDraw.Draw(canvas)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 15)
except Exception:
    font = ImageFont.load_default()

for r, name in enumerate(NAMES):
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    y0 = pad + r * (ch + lab + pad)
    d.text((pad, y0), name, font=font, fill=(240, 220, 180))
    cells = [
        (sheet.crop((0, 240, 60, 360)), "走路(右)"),
        (sheet.crop((60, 480, 120, 600)), "坐 col1(左)"),
        (sheet.crop((120, 480, 180, 600)), "坐 col2(右)"),
    ]
    for k, (cell, title) in enumerate(cells):
        big = cell.resize((cw, ch), Image.NEAREST)
        x0 = pad + k * (cw + pad)
        canvas.paste(big, (x0, y0 + lab), big)
        d.text((x0, y0 + lab + ch + 2), title, font=font, fill=(180, 220, 180))

canvas.save(os.path.join(ROOT, "tests", "compare_walk_vs_sit2.png"))
print("saved", canvas.size)
