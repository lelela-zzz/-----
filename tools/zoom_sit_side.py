from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]
S = 4  # 60x120 -> 240x480
cw, ch = 60 * S, 120 * S
pad = 10
lab = 22
W = pad + (cw + pad) * 2
H = pad + (ch + lab + pad) * len(NAMES)
canvas = Image.new("RGB", (W, H), (28, 22, 18))
d = ImageDraw.Draw(canvas)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 16)
except Exception:
    font = ImageFont.load_default()
for r, name in enumerate(NAMES):
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    y0 = pad + r * (ch + lab + pad)
    d.text((pad, y0), name, font=font, fill=(240, 220, 180))
    for k, col in enumerate((1, 2)):  # col1 左, col2 右
        cell = sheet.crop((col * 60, 480, col * 60 + 60, 600)).resize((cw, ch), Image.NEAREST)
        x0 = pad + k * (cw + pad)
        # 棋盘底，便于看透明与矩形
        for by in range(0, ch, 20):
            for bx in range(0, cw, 20):
                c = (44, 36, 30) if ((bx // 20 + by // 20) % 2 == 0) else (58, 48, 40)
                d.rectangle([x0 + bx, y0 + lab + by, x0 + bx + 19, y0 + lab + by + 19], fill=c)
        canvas.paste(cell, (x0, y0 + lab), cell)
        d.text((x0 + 4, y0 + lab + ch + 2), "col%d %s" % (col, "左" if col == 1 else "右"),
               font=font, fill=(180, 220, 180))
canvas.save(os.path.join(ROOT, "tests", "sit_side_zoom_v2.png"))
print("saved", canvas.size)
