"""扫描 tests/ 下所有报告图，找出仍然带"占位矩形"的图（好删掉/重生成）。

矩形特征：低饱和 + 高填充率（>=0.80）的实心浅色块，面积 >=150，最长横边 >=28。
"""
from PIL import Image
import os
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGETS = [os.path.join(ROOT, "tests"), os.path.join(ROOT, "tests", "shots"),
           os.path.join(ROOT, "tests", "prologue_shots")]


def is_pale(c):
    if len(c) == 4:
        r, g, b, a = c
        if a < 40:
            return False
    else:
        r, g, b = c
    mx, mn = max(r, g, b), min(r, g, b)
    sat = 0 if mx == 0 else (mx - mn) / mx
    return sat < 0.30 and 100 < mx < 245


def has_rect(im):
    im = im.convert("RGBA")
    if im.width > 1400 or im.height > 2600:
        return None  # 太大，跳过（性能）
    w, h = im.size
    px = im.load()
    seen = [[False] * h for _ in range(w)]
    for y in range(h):
        for x in range(w):
            if seen[x][y] or not is_pale(px[x, y]):
                continue
            q = deque([(x, y)])
            seen[x][y] = True
            pts = []
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] and is_pale(px[nx, ny]):
                        seen[nx][ny] = True
                        q.append((nx, ny))
            if len(pts) < 150:
                continue
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
            bw, bh = x1 - x0 + 1, y1 - y0 + 1
            fill = len(pts) / float(bw * bh)
            pset = set(pts)
            hrun = max((sum(1 for xx in range(x0, x1 + 1) if (xx, yy) in pset) for yy in range(y0, y1 + 1)), default=0)
            if fill >= 0.80 and hrun >= 28:
                return (fill, len(pts), bw, bh, hrun, (x0, y0))
    return None


hits = []
for t in TARGETS:
    if not os.path.isdir(t):
        continue
    for fn in sorted(os.listdir(t)):
        if not fn.lower().endswith((".png", ".jpg")):
            continue
        p = os.path.join(t, fn)
        try:
            im = Image.open(p)
            r = has_rect(im)
        except Exception as e:
            print("  ERR", fn, e)
            continue
        if r:
            hits.append((os.path.relpath(p, ROOT), r))
            print("  [矩形] %s  fill=%.2f area=%d %dx%d 横边=%d at%s" % (
                os.path.relpath(p, ROOT), r[0], r[1], r[2], r[3], r[4], r[5]))
print()
print("命中 %d 个文件" % len(hits))
