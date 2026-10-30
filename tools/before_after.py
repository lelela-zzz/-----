from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
name = "雪山探险家_哈特菲利亚"
sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
S = 4
cw, ch = 60 * S, 120 * S
pad = 16
lab = 26
W = pad * 3 + cw * 2
H = ch + lab + pad * 2
canvas = Image.new("RGB", (W, H), (28, 22, 18))
d = ImageDraw.Draw(canvas)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 16)
except Exception:
    font = ImageFont.load_default()

# 修复前：col0 正面占位稿（游戏因 play_pose bug 一直显示它，带奶油色矩形）
before = sheet.crop((0, 480, 60, 600))
# 修复后：col2 右侧真坐姿
after = sheet.crop((120, 480, 180, 600))

for i, (cell, title, col) in enumerate([(before, "修复前（正面占位稿·带矩形）", (240, 150, 150)),
                                        (after, "修复后（侧面坐姿·无矩形）", (150, 235, 150))]):
    big = cell.resize((cw, ch), Image.NEAREST)
    x0 = pad + i * (cw + pad)
    canvas.paste(big, (x0, pad + lab), big)
    d.text((x0, pad), title, font=font, fill=col)

canvas.save(os.path.join(ROOT, "tests", "before_after_lucy.png"))
print("saved", canvas.size)
