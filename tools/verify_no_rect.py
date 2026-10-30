"""验收：坐姿行 4 格全部无"占位矩形"——两条独立判据。

判据 A（结构性）：col0 必须等于 col2、col3 必须等于 col1（占位稿已彻底移除）。
判据 B（形态学）：任何一格都不允许出现"高填充率的实心浅色块"
                 （占位矩形是 52x22 的纯色块，填充率 ~0.95，最长横边 ~50）。
"""
from PIL import Image
import os
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]

fails = []


def is_pale(c):
    r, g, b, a = c
    if a < 40:
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    sat = 0 if mx == 0 else (mx - mn) / mx
    return sat < 0.30 and 100 < mx < 245


def rect_scan(cell, tag, name):
    w, h = cell.size
    px = cell.load()
    seen = [[False] * h for _ in range(w)]
    worst = None
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
            if len(pts) < 40:
                continue
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
            bw, bh = x1 - x0 + 1, y1 - y0 + 1
            fill = len(pts) / float(bw * bh)
            pset = set(pts)
            hrun = max((sum(1 for xx in range(x0, x1 + 1) if (xx, yy) in pset) for yy in range(y0, y1 + 1)), default=0)
            if worst is None or (fill, len(pts)) > (worst[0], worst[1]):
                worst = (fill, len(pts), bw, bh, hrun)
    if worst is None:
        print("   [OK] %s %s : 无浅色块" % (name, tag))
        return
    fill, area, bw, bh, hrun = worst
    ok = not (fill > 0.80 and area > 150 and hrun > 28)
    print("   [%s] %s %s : 最大块 fill=%.2f area=%d %dx%d 最长横边=%d"
          % ("OK" if ok else "FAIL", name, tag, fill, area, bw, bh, hrun))
    if not ok:
        fails.append("%s %s 矩形残留 fill=%.2f area=%d" % (name, tag, fill, area))


def same(a, b):
    if a.size != b.size:
        return False
    pa, pb = a.load(), b.load()
    for y in range(a.height):
        for x in range(a.width):
            if pa[x, y] != pb[x, y]:
                return False
    return True


for name in NAMES:
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    print("=" * 68)
    print(name, sheet.size)
    if sheet.height < 600:
        fails.append(name + " 无坐姿行")
        continue
    c0 = sheet.crop((0, 480, 60, 600))
    c1 = sheet.crop((60, 480, 120, 600))
    c2 = sheet.crop((120, 480, 180, 600))
    c3 = sheet.crop((180, 480, 240, 600))
    e01 = same(c0, c2)
    e31 = same(c3, c1)
    print("   [%s] col0 == col2（无正面占位）: %s" % ("OK" if e01 else "FAIL", e01))
    print("   [%s] col3 == col1（无背面占位）: %s" % ("OK" if e31 else "FAIL", e31))
    if not e01:
        fails.append(name + " col0 仍含占位稿")
    if not e31:
        fails.append(name + " col3 仍含占位稿")
    for c, tag in ((c0, "col0"), (c1, "col1"), (c2, "col2"), (c3, "col3")):
        rect_scan(c, tag, name)

print()
if fails:
    print("FAIL %d:" % len(fails))
    for f in fails:
        print("   -", f)
else:
    print("ALL PASS：坐姿行四格均为真侧面，无任何占位矩形。")
