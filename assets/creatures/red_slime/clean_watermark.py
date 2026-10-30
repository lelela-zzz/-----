import sys
from PIL import Image

src = sys.argv[1]
dst = sys.argv[2]

img = Image.open(src).convert("RGB")
W, H = img.size
spx = img.load()
out = img.copy()
opx = out.load()

def is_red(r, g, b):
    return r > b + 35 and r > 90

# Background color sampled from a clean top-left block (always background)
rs = gs = bs = 0
for y in range(20):
    for x in range(20):
        r, g, b = spx[x, y]
        rs += r; gs += g; bs += b
bg = (rs // 400, gs // 400, bs // 400)
bg_bright = (bg[0] + bg[1] + bg[2]) / 3.0

# Replace every non-red pixel in the bottom-right region that is not darker
# than the background (i.e. watermark text + all its halo). Darker pixels
# (contact shadow) and red slime pixels are preserved.
y0 = int(H * 0.74)
x0 = int(W * 0.40)
count = 0
for y in range(y0, H):
    for x in range(x0, W):
        r, g, b = spx[x, y]
        if (not is_red(r, g, b)) and ((r + g + b) / 3.0) >= bg_bright - 2:
            opx[x, y] = bg
            count += 1

print("bg color:", bg, "bg_bright:", round(bg_bright, 1), "replaced pixels:", count)
out.save(dst)
print("saved", dst)
