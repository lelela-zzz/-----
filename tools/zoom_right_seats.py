"""裁出右侧两张长桌的落座区（6 倍放大），并标出旧 x=266 与新 x=272 的座位竖线。

world.tscn 相机被 limit 夹死在 (320,192)，屏幕坐标 == 世界坐标，可直接按座位坐标裁。
"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = Image.open(os.path.join(ROOT, "tests", "shots", "seat_01_all.png")).convert("RGB")

S = 6
# 右侧长凳贴图 x=204..294（长桌2 y132..220 / 长桌4 y218..308）
BOXES = [("s2 长桌2·凳 (y=210)", (200, 150, 310, 232)),
         ("s4 长桌4·凳 (y=296)", (200, 236, 310, 318))]

font = None
try:
    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 14)
except Exception:
    font = ImageFont.load_default()

tiles = []
for tag, box in BOXES:
    crop = src.crop(box)
    t = crop.resize((crop.width * S, crop.height * S), Image.NEAREST)
    d = ImageDraw.Draw(t)
    # 旧位置 266（黄）/ 新位置 272（青）
    for wx, col, lab in ((266, (255, 210, 60), "旧 x=266"), (272, (80, 235, 255), "新 x=272")):
        sx = int((wx - box[0]) * S)
        d.line([(sx, 0), (sx, t.height)], fill=col, width=1)
        d.text((sx + 2, 2), lab, font=font, fill=col)
    d.text((4, t.height - 18), tag, font=font, fill=(230, 230, 230))
    tiles.append(t)

W = sum(t.width for t in tiles) + 12 * (len(tiles) + 1)
H = max(t.height for t in tiles) + 24
canvas = Image.new("RGB", (W, H), (18, 16, 20))
x = 12
for t in tiles:
    canvas.paste(t, (x, 12))
    x += t.width + 12
canvas.save(os.path.join(ROOT, "tests", "right_seats_zoom.png"))
print("saved", canvas.size)

# 顺便打印两张右座位在新截图里的水平像素范围（角色非底图差异法太脆，直接看列亮度即可）
