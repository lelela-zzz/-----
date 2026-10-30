from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]
S = 6
cw, ch = 60 * S, 120 * S
pad = 14
lab = 22
W = pad + (cw + pad) * 4
H = ch + lab + pad * 2
canvas = Image.new("RGB", (W, H), (255, 0, 255))  # 品红：透明=品红，不透明色清晰可见
d = ImageDraw.Draw(canvas)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 15)
except Exception:
    font = ImageFont.load_default()
for i, name in enumerate(NAMES):
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    cell = sheet.crop((120, 480, 180, 600))  # col2 右向
    big = cell.resize((cw, ch), Image.NEAREST)
    x0 = pad + i * (cw + pad)
    canvas.paste(big, (x0, pad), big)
    d.text((x0, pad + ch + 3), name, font=font, fill=(0, 0, 0))
canvas.save(os.path.join(ROOT, "tests", "final_check_v3.png"))
print("saved", canvas.size)
