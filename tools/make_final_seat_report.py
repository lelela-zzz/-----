"""最终报告图：真实游戏内落座截图 + 图集坐姿行四格（全是真侧面，无矩形）。

产出 tests/final_seat_report.png
"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(ROOT, "tests")
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]

font = None
for p in ("C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/msyh.ttc"):
    try:
        font = ImageFont.truetype(p, 16)
        break
    except Exception:
        pass
small = None
try:
    small = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 13)
except Exception:
    small = font

# 上半：游戏内截图 2x
game = Image.open(os.path.join(T, "shots", "seat_01_all.png")).convert("RGB")
GW, GH = game.width * 2, game.height * 2
game2 = game.resize((GW, GH), Image.NEAREST)

# 下半：每人坐姿行 4 格（洋红底）
S = 3
CW, CH = 60 * S, 120 * S
PAD = 10
ROW_H = CH + 20
sheet_w = PAD + (CW + PAD) * 4
W = max(GW + 40, sheet_w + 40)
H = 34 + GH + 16 + ROW_H * len(NAMES) + 30

canvas = Image.new("RGB", (W, H), (22, 20, 24))
d = ImageDraw.Draw(canvas)
d.text((20, 8), "游戏内实拍：四位顾客落座（左椅→朝右，右椅→朝左）", font=font, fill=(255, 220, 160))
canvas.paste(game2, (20, 34))

y = 34 + GH + 16
d.text((20, y - 20), "图集坐姿行四格（洋红底）：全是真侧面，占位矩形已清除",
       font=font, fill=(255, 220, 160))
for name in NAMES:
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    x = PAD
    for c in range(4):
        cell = sheet.crop((c * 60, 480, c * 60 + 60, 600)).resize((CW, CH), Image.NEAREST)
        bg = Image.new("RGB", (CW, CH), (255, 0, 200))
        bg.paste(cell, (0, 0), cell)
        canvas.paste(bg, (x, y))
        d.text((x, y + CH + 2), "col%d" % c, font=small, fill=(150, 220, 255))
        x += CW + PAD
    d.text((x + 4, y + CH // 2), name, font=small, fill=(200, 200, 210))
    y += ROW_H

canvas.save(os.path.join(T, "final_seat_report.png"))
print("saved", canvas.size)
