from PIL import Image
import json
from collections import deque

ROOT = r"C:\Users\了了啦\Documents\game2"
LOGICAL = 768.0
img = Image.open(ROOT + r"\assets\spring\v1\scene_day_2x.png").convert("RGB")
IW, IH = img.size
sx, sy = LOGICAL / IW, LOGICAL / IH
P = img.load()


def rgb_at(x, y):
    ix, iy = int(x / sx), int(y / sy)
    if not (0 <= ix < IW and 0 <= iy < IH):
        return (0, 0, 0)
    return P[ix, iy]


def is_water(c):
    r, g, b = c
    return (g - r) > 25 and (b - r) > 15 and abs(g - b) < 50


print("=== water-ish grid (#=water, .=not)  24-unit cells ===")
print("      " + "".join(str((i * 24) // 100 % 10) for i in range(32)))
for gy in range(32):
    row = "".join("W" if is_water(rgb_at(gx * 24 + 12, gy * 24 + 12)) else "." for gx in range(32))
    print("%4d  %s" % (gy * 24, row))

# 找水的连通块（8 邻域，8 单位精度太慢，用 8 单位在 ROI 内）
ROI = (200, 140, 600, 460)     # x0,y0,x1,y1  圈住泉眼
step = 4
wx = (ROI[2] - ROI[0]) // step
wy = (ROI[3] - ROI[1]) // step
mask = [[is_water(rgb_at(ROI[0] + gx * step + step / 2, ROI[1] + gy * step + step / 2))
         for gx in range(wx)] for gy in range(wy)]

seen = [[False] * wx for _ in range(wy)]
blobs = []
for gy in range(wy):
    for gx in range(wx):
        if not mask[gy][gx] or seen[gy][gx]:
            continue
        q = deque([(gx, gy)])
        seen[gy][gx] = True
        cells = []
        while q:
            cx, cy = q.popleft()
            cells.append((cx, cy))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < wx and 0 <= ny < wy and not seen[ny][nx] and mask[ny][nx]:
                        seen[ny][nx] = True
                        q.append((nx, ny))
        blobs.append(cells)

blobs.sort(key=len, reverse=True)
print()
print("top water blobs in ROI (size, bbox logical):")
for b in blobs[:5]:
    xs = [ROI[0] + p[0] * step for p in b]
    ys = [ROI[1] + p[1] * step for p in b]
    print("  size=%4d  x[%d..%d] y[%d..%d]  center=(%d,%d)"
          % (len(b), min(xs), max(xs), min(ys), max(ys),
             (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2))
