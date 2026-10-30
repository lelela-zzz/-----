import sys
from PIL import Image

src = sys.argv[1]
img = Image.open(src).convert("RGB")
W, H = img.size
px = img.load()

def is_white(r, g, b):
    return r > 240 and g > 240 and b > 240

def is_red(r, g, b):
    return r > b + 30 and r > 90

# Look for non-white, non-red pixels in the bottom-right corner (potential watermark)
x0, y0 = int(W * 0.6), int(H * 0.8)
pts = []
for y in range(y0, H):
    for x in range(x0, W):
        r, g, b = px[x, y]
        if not (is_white(r, g, b) or is_red(r, g, b)):
            pts.append((x, y, r, g, b))

print("corner non-white/non-red pixels:", len(pts))
if pts:
    cols = [(p[2], p[3], p[4]) for p in pts]
    from collections import Counter
    for c, n in Counter(cols).most_common(8):
        print(c, n)
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    print("bbox:", min(xs), min(ys), max(xs), max(ys))
