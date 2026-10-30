"""把用户最新反馈截图放大，并叠棋盘格底，便于定位"类矩形"。"""
from PIL import Image

SRC = "tests/rect_feedback.png"
im = Image.open(SRC).convert("RGBA")
print("size", im.size)

# 1) 6x 最近邻放大（保持像素块）
big = im.resize((im.width * 6, im.height * 6), Image.NEAREST)
big.convert("RGB").save("tests/rect_feedback_6x.png")

# 2) 棋盘格底（看透明区域）
bg = Image.new("RGBA", im.size)
cell = 8
for y in range(0, im.height, cell):
    for x in range(0, im.width, cell):
        c = (90, 90, 100, 255) if ((x // cell + y // cell) % 2 == 0) else (140, 140, 150, 255)
        bg.paste(c, (x, y, cell, cell))
chk = Image.alpha_composite(bg, im)
chk.resize((chk.width * 6, chk.height * 6), Image.NEAREST).convert("RGB").save("tests/rect_feedback_chess.png")

# 3) 统计：找出大面积"低饱和灰"连通块（疑似矩形残留）
import colorsys
from collections import deque
w, h = im.size
px = im.load()
seen = [[False] * h for _ in range(w)]


def is_gray(c):
    r, g, b, a = c
    if a < 40:
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    if mx == 0:
        return False
    sat = (mx - mn) / mx
    return sat < 0.20 and 90 < mx < 235


blocks = []
for y in range(h):
    for x in range(w):
        if seen[x][y] or not is_gray(px[x, y]):
            continue
        q = deque([(x, y)])
        seen[x][y] = True
        pts = []
        while q:
            cx, cy = q.popleft()
            pts.append((cx, cy))
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = cx + dx, cy + dy
                if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] and is_gray(px[nx, ny]):
                    seen[nx][ny] = True
                    q.append((nx, ny))
        if len(pts) > 120:
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            blocks.append((len(pts), min(xs), min(ys), max(xs), max(ys)))

blocks.sort(reverse=True)
print("灰块数量(>120px):", len(blocks))
for b in blocks[:8]:
    n, x0, y0, x1, y1 = b
    print("  area=%d bbox=(%d,%d)-(%d,%d) w=%d h=%d fill=%.2f" % (
        n, x0, y0, x1, y1, x1 - x0 + 1, y1 - y0 + 1, n / float((x1 - x0 + 1) * (y1 - y0 + 1))))
