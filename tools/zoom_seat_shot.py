"""放大游戏内落座截图的长凳区域，便于肉眼核对有无矩形残留。"""
from PIL import Image
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = Image.open(os.path.join(ROOT, "tests", "shots", "seat_01_all.png")).convert("RGB")
print("shot size", src.size)

# 座位世界坐标 s1(137,210) s2(266,210) s3(137,296) s4(266,296)
# 截图像素 = 世界坐标（viewport 640x384 与底图 1:1，相机跟玩家，玩家在 430,250）
# 先整图 3 倍存一份
src.resize((src.width * 3, src.height * 3), Image.NEAREST).save(
    os.path.join(ROOT, "tests", "seat_shot_3x.png"))

# 再裁每个座位附近 60x80 区域，8 倍放大
seats = [("s1", 137, 210), ("s2", 266, 210), ("s3", 137, 296), ("s4", 266, 296)]
tiles = []
for sid, sx, sy in seats:
    box = (max(0, sx - 34), max(0, sy - 78), sx + 34, sy + 16)
    t = src.crop(box).resize((68 * 8, 94 * 8), Image.NEAREST)
    tiles.append((sid, t))

W = sum(t.width for _, t in tiles) + 10 * (len(tiles) + 1)
H = max(t.height for _, t in tiles) + 20
canvas = Image.new("RGB", (W, H), (16, 14, 18))
x = 10
for sid, t in tiles:
    canvas.paste(t, (x, 10))
    x += t.width + 10
canvas.save(os.path.join(ROOT, "tests", "seat_shot_tiles.png"))
print("saved seat_shot_3x.png / seat_shot_tiles.png", canvas.size)
