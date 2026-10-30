"""把滚木贴到室内白天底图上做场景验证：比例、明度、描边可读性。"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = os.path.join(ROOT, "assets/house/v4/scene_day_v15_1x.png")
PROP = os.path.join(ROOT, "assets/props/rolling_log/v1")

bg = Image.open(BG).convert("RGB")
print("底图", bg.size)

for tag in ("rolling_log_1x", "rolling_log_outline_1x"):
    prop = Image.open(os.path.join(PROP, tag + ".png")).convert("RGBA")
    canvas = bg.copy()
    # 靠火炉右前方的空地，脚底落在 y=330
    x, y = 300 - prop.size[0] // 2, 330 - prop.size[1]
    canvas.paste(prop, (x, y), prop)
    # 旁边放玩家占位体（16x48）做身高参照
    pl = Image.open(os.path.join(ROOT, "assets/actors/player_placeholder_1x.png")).convert("RGBA")
    canvas.paste(pl, (360, 330 - pl.size[1]), pl)
    canvas.resize((bg.size[0] * 2, bg.size[1] * 2), Image.NEAREST).save(
        os.path.join(ROOT, "exports/rolling_log_scene_%s.png" % tag.replace("rolling_log_", "")))
    print("场景验证 ->", tag)

# 并排对照图（局部裁切 3x）
a = Image.open(os.path.join(ROOT, "exports/rolling_log_scene_1x.png"))
b = Image.open(os.path.join(ROOT, "exports/rolling_log_scene_outline_1x.png"))
box = (460, 380, 860, 700)   # 2x 坐标下的局部
ca, cb = a.crop(box), b.crop(box)
w, h = ca.size
sheet = Image.new("RGB", (w * 2 + 24, h + 44), (30, 30, 30))
d = ImageDraw.Draw(sheet)
sheet.paste(ca, (8, 36))
sheet.paste(cb, (w + 16, 36))
d.text((8, 12), "in-scene 2x  |  left: no outline   right: 1px outline", fill=(235, 235, 235))
sheet.save(os.path.join(ROOT, "exports/rolling_log_scene_compare.png"))
print("对照 ->", os.path.join(ROOT, "exports/rolling_log_scene_compare.png"))
