from PIL import Image
ROOT = "tests"
names = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华"]
S = 4
cells = []
for n in names:
    r = Image.open(f"{ROOT}/gridsit_{n}_right.png").convert("RGBA")
    l = Image.open(f"{ROOT}/gridsit_{n}_left.png").convert("RGBA")
    cells.append((r, l))
cw, ch = 60, 120
pad = 6
# layout: each customer row: [R L] then label area
row_h = ch * S + 16
W = (cw * S) * 2 + pad + pad
H = row_h * len(names) + pad
bg = Image.new("RGBA", (W, H), (30, 24, 20, 255))
px = bg.load()
y0 = pad
for (r, l) in cells:
    # left cell (facing left) on left, right cell on right
    lr = l.resize((cw * S, ch * S), Image.NEAREST)
    rr = r.resize((cw * S, ch * S), Image.NEAREST)
    bg.alpha_composite(lr, (pad, y0))
    bg.alpha_composite(rr, (pad + cw * S + pad, y0))
    y0 += row_h
bg.convert("RGB").save(f"{ROOT}/gridsit_check.png")
print("ok", bg.size)
