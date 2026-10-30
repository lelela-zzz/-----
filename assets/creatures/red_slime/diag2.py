import sys
from PIL import Image

src = sys.argv[1]
img = Image.open(src).convert("RGB")
W, H = img.size
px = img.load()

def is_red(r, g, b):
    return r > b + 35 and r > 90

# Watermark/halo pixels: non-red and green high
wm = []
# Dark purple block: blue > red, red low, green low (candidate shadow)
dp = []
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        if (not is_red(r, g, b)) and g > 80:
            wm.append((x, y))
        if b > r + 30 and r < 150 and g < 80:
            dp.append((x, y))

def bbox(pts):
    if not pts:
        return None
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys), len(pts))

print("watermark-like bbox (x0,y0,x1,y1,count):", bbox(wm))
print("dark-purple bbox:", bbox(dp))
