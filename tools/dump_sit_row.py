"""把坐姿行 4 格全导出成一张图（洋红底），并打印 col0/col3 的 ASCII，确认占位矩形。"""
from PIL import Image
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]
S = 4
CW, CH = 60 * S, 120 * S
PAD = 8

font = None
try:
    from PIL import ImageFont
    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 13)
except Exception:
    font = None

W = PAD + (CW + PAD) * 4
H = PAD + (CH + 18 + PAD) * len(NAMES)
canvas = Image.new("RGB", (W, H), (26, 22, 26))
d = ImageDraw = __import__("PIL.ImageDraw", fromlist=["Draw"]).Draw(canvas)


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


for r, name in enumerate(NAMES):
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    y0 = PAD + r * (CH + 18 + PAD)
    for c in range(4):
        cell = sheet.crop((c * 60, 480, c * 60 + 60, 600))
        x0 = PAD + c * (CW + PAD)
        bg = Image.new("RGB", (CW, CH), (255, 0, 200))
        big = cell.resize((CW, CH), Image.NEAREST)
        bg.paste(big, (0, 0), big)
        canvas.paste(bg, (x0, y0))
        if font:
            d.text((x0, y0 + CH + 2), "col%d" % c, font=font, fill=(255, 230, 160))
    if font:
        d.text((PAD, y0 - 0), name, font=font, fill=(160, 200, 255))

canvas.save(os.path.join(ROOT, "tests", "sit_row_all4.png"))
print("saved sit_row_all4.png", canvas.size)

# col0 / col3 ASCII（哈特菲利亚）
sheet = Image.open(os.path.join(NPC, NAMES[0] + ".png")).convert("RGBA")
for c in (0, 3):
    cell = sheet.crop((c * 60, 480, c * 60 + 60, 600))
    px = cell.load()
    print("---- 哈特菲利亚 col%d ----" % c)
    for y in range(0, 120, 3):
        print("  %3d %s" % (y, "".join(cls(px[x, y]) for x in range(60))))
