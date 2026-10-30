import sys
from PIL import Image
from collections import Counter

src = sys.argv[1]
img = Image.open(src).convert("RGB")
W, H = img.size
px = img.load()

# Background sample (top-left)
bg = px[5, 5]
print("top-left bg:", bg)

# Look at bottom-right 260x200 corner, find pixels clearly different from bg
region_x0 = W - 260
region_y0 = H - 200
diff = Counter()
for y in range(region_y0, H):
    for x in range(region_x0, W):
        r, g, b = px[x, y]
        dr = abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])
        if dr > 40:
            diff[(r, g, b)] += 1

print("distinct off-bg colors in corner (top 15):")
for col, cnt in diff.most_common(15):
    print(col, cnt)
print("total off-bg pixels:", sum(diff.values()))
