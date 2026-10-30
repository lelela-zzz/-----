import sys
from collections import deque
from PIL import Image


def key_bg(src, dst):
    img = Image.open(src).convert("RGBA")
    W, H = img.size
    px = img.load()

    # Sample border color from the four corners
    pts = [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)]
    rs = sum(px[p][0] for p in pts) // 4
    gs = sum(px[p][1] for p in pts) // 4
    bs = sum(px[p][2] for p in pts) // 4
    tol = 30

    def near(x, y):
        r, g, b, a = px[x, y]
        return abs(r - rs) <= tol and abs(g - gs) <= tol and abs(b - bs) <= tol

    seen = [[False] * W for _ in range(H)]
    dq = deque()
    for x in range(W):
        for y in (0, H - 1):
            if near(x, y) and not seen[y][x]:
                seen[y][x] = True
                dq.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            if near(x, y) and not seen[y][x]:
                seen[y][x] = True
                dq.append((x, y))

    removed = 0
    while dq:
        x, y = dq.popleft()
        px[x, y] = (255, 255, 255, 0)
        removed += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and near(nx, ny):
                seen[ny][nx] = True
                dq.append((nx, ny))

    # Trim to alpha bbox with a small margin
    bbox = img.getbbox()
    if bbox:
        l, t, r, b = bbox
        pad = 2
        l = max(0, l - pad)
        t = max(0, t - pad)
        r = min(W, r + pad)
        b = min(H, b + pad)
        img = img.crop((l, t, r, b))

    img.save(dst)
    print("bg=%s removed=%d out_size=%s -> %s" % ((rs, gs, bs), removed, img.size, dst))


if __name__ == "__main__":
    key_bg(sys.argv[1], sys.argv[2])
