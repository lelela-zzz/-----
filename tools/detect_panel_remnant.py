"""量化检测坐姿帧里"低饱和浅色块"是否像抠图残留的矩形背景板。

判定线索：
  1) 面积 / 外接框填充率（矩形板 fill 会很高）
  2) 最长直线边（背景板边缘一定是长直边）
  3) 是否贴到格子边界（背景板通常延伸出画面）
对照组 = 同一角色走路帧（原画，绝无残留）
"""
from PIL import Image
import os
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]


def is_pale(c):
    r, g, b, a = c
    if a < 40:
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    sat = 0 if mx == 0 else (mx - mn) / mx
    return sat < 0.22 and 110 < mx < 240


def analyse(cell, tag):
    w, h = cell.size
    px = cell.load()
    seen = [[False] * h for _ in range(w)]
    out = []
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
            if len(pts) < 60:
                continue
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
            bw, bh = x1 - x0 + 1, y1 - y0 + 1
            pset = set(pts)
            fill = len(pts) / float(bw * bh)
            # 最长水平直边 / 最长垂直直边
            hrun = max((sum(1 for xx in range(x0, x1 + 1) if (xx, yy) in pset) for yy in range(y0, y1 + 1)), default=0)
            vrun = max((sum(1 for yy in range(y0, y1 + 1) if (xx, yy) in pset) for xx in range(x0, x1 + 1)), default=0)
            touch = (x0 <= 1 or x1 >= w - 2 or y0 <= 1 or y1 >= h - 2)
            out.append(dict(area=len(pts), bbox=(x0, y0, x1, y1), bw=bw, bh=bh,
                            fill=fill, hrun=hrun, vrun=vrun, touch=touch))
    out.sort(key=lambda d: -d["area"])
    print("  [%s]" % tag)
    if not out:
        print("     无 >60px 浅色块")
    for b in out[:4]:
        print("     area=%-5d bbox=%s %dx%d fill=%.2f 最长横边=%d 最长竖边=%d 贴边=%s"
              % (b["area"], b["bbox"], b["bw"], b["bh"], b["fill"], b["hrun"], b["vrun"], b["touch"]))
    return out


for name in NAMES:
    sheet = Image.open(os.path.join(NPC, name + ".png")).convert("RGBA")
    print("=" * 72)
    print(name)
    analyse(sheet.crop((0, 240, 60, 360)), "走路(右) 对照")
    analyse(sheet.crop((60, 480, 120, 600)), "坐 col1(左)")
    analyse(sheet.crop((120, 480, 180, 600)), "坐 col2(右)")
