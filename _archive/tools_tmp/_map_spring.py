from PIL import Image
import json

ROOT = r"C:\Users\了了啦\Documents\game2"
LOGICAL = 768.0

img = Image.open(ROOT + r"\assets\spring\v1\scene_day_2x.png").convert("RGB")
IW, IH = img.size
sx = LOGICAL / IW          # 图像 -> 逻辑坐标
sy = LOGICAL / IH
px = img.load()

props = json.load(open(ROOT + r"\assets\spring\v1\objects\props.json", encoding="utf-8"))["props"]
rects = [tuple(p["collision_rect"]) for p in props if p.get("collision_rect")]


def in_obstacle(x, y):
    for (rx, ry, rw, rh) in rects:
        if rx <= x < rx + rw and ry <= y < ry + rh:
            return True
    return False


def is_water(x, y):
    ix, iy = int(x / sx), int(y / sy)
    if not (0 <= ix < IW and 0 <= iy < IH):
        return False
    r, g, b = px[ix, iy]
    return b > r + 25 and b > 60


N = 64
step = LOGICAL / N
water_pts = []
for gy in range(N):
    row = []
    for gx in range(N):
        x = (gx + 0.5) * step
        y = (gy + 0.5) * step
        if is_water(x, y):
            row.append("W")
            water_pts.append((x, y))
        elif in_obstacle(x, y):
            row.append("#")
        else:
            row.append(".")
    print("%3d | %s" % (int(gy * step), "".join(row)))
print("     " + "".join(str((i // 10) % 10) if i % 10 == 0 else " " for i in range(N)))
print("      " + "".join(str((int(i * step) // 10) % 10) if int(i * step) % 100 < 12 else " " for i in range(N)))

if water_pts:
    xs = [p[0] for p in water_pts]
    ys = [p[1] for p in water_pts]
    print()
    print("water bbox: x[%d..%d]  y[%d..%d]" % (min(xs), max(xs), min(ys), max(ys)))
    print("water centroid: (%.0f, %.0f)" % (sum(xs) / len(xs), sum(ys) / len(ys)))
    print("water samples: %d" % len(water_pts))
