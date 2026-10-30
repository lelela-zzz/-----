#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""重建 3 位顾客的侧坐帧：
 · 爱德华 改映射到网格(2,4)=金发红披风骑士（与其行走帧一致，修「坐下变别人」）
 · 哈特菲利亚/西蒙 重新干净抠图（顺便去掉黑噪点）
 · 凯瑟琳 保留她的真美术，仅对现有帧做去噪
管道：内缩裁格 → 四角洪水抠灰底 → 去小块 → 去孤立噪点 → 等比 contain 进 60x120
（脚底对齐格底、水平居中）→ 右=原图/左=镜像 → 写回坐姿行 col1(左)/col2(右)。"""
from collections import deque
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRID = os.path.join(ROOT, "tests", "sidesit_grid.jpg")
NPC = os.path.join(ROOT, "assets", "actors", "npc")

# 角色 -> 网格面板 (x0,y0,x1,y1)
MAP = {
    "雪山探险家_哈特菲利亚": (1601, 697, 1911, 1007),   # 金发白大衣女
    "矿工少年_西蒙": (8, 697, 318, 1007),         # 护目镜蓝夹克少年
    "矮人战士_爱德华": (964, 361, 1274, 670),     # ★改为 金发红披风骑士（匹配行走帧）
}
KEEP_REAL = ["集市管理员_凯瑟琳"]                 # 真美术，只去噪

CELL_W, CELL_H = 60, 120
SIT_ROW_Y = 480
INSET = 20
CORNER_TOL = 58
MAX_W, MAX_H = 56, 116


def key_corner(cell):
    W, H = cell.size
    px = cell.load()
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    op = out.load()
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y][:3]
            op[x, y] = (r, g, b, 255)
    bg = [[False] * W for _ in range(H)]

    def flood(sx, sy):
        sc = px[sx, sy][:3]
        q = deque([(sx, sy)])
        bg[sy][sx] = True
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and not bg[ny][nx]:
                    c = px[nx, ny]
                    if max(abs(c[0] - sc[0]), abs(c[1] - sc[1]), abs(c[2] - sc[2])) <= CORNER_TOL:
                        bg[ny][nx] = True
                        q.append((nx, ny))

    for (sx, sy) in [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)]:
        if not bg[sy][sx]:
            flood(sx, sy)
    for y in range(H):
        for x in range(W):
            if bg[y][x]:
                op[x, y] = (0, 0, 0, 0)
    return out


def remove_small(im, min_area=40):
    W, H = im.size
    px = im.load()
    opaque = [[px[x, y][3] > 128 for x in range(W)] for y in range(H)]
    seen = [[False] * W for _ in range(H)]
    comps = []
    for y in range(H):
        for x in range(W):
            if opaque[y][x] and not seen[y][x]:
                q = deque([(x, y)])
                seen[y][x] = True
                pts = []
                while q:
                    cx, cy = q.popleft()
                    pts.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < W and 0 <= ny < H and opaque[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            q.append((nx, ny))
                comps.append(pts)
    if not comps:
        return im
    biggest = max(len(p) for p in comps)
    out = im.copy()
    op = out.load()
    for pts in comps:
        if len(pts) < min_area and len(pts) != biggest:
            for (x, y) in pts:
                op[x, y] = (0, 0, 0, 0)
    return out


def despeckle(im, min_neighbors=2):
    W, H = im.size
    px = im.load()
    op_mask = [[px[x, y][3] > 128 for x in range(W)] for y in range(H)]
    out = im.copy()
    op = out.load()
    for y in range(H):
        for x in range(W):
            if not op_mask[y][x]:
                continue
            n = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and op_mask[ny][nx]:
                    n += 1
            if n < min_neighbors:
                op[x, y] = (0, 0, 0, 0)
    return out


def fit_cell(body):
    bw, bh = body.size
    if bw == 0 or bh == 0:
        return Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    scale = min(MAX_W / float(bw), MAX_H / float(bh))
    nw = max(1, int(round(bw * scale)))
    nh = max(1, int(round(bh * scale)))
    big = body.resize((nw, nh), Image.NEAREST)
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    cell.paste(big, ((CELL_W - nw) // 2, CELL_H - nh), big)
    return cell


def build_from_grid(name, rect):
    grid = Image.open(GRID).convert("RGB")
    x0, y0, x1, y1 = rect
    crop = grid.crop((x0 + INSET, y0 + INSET, x1 - INSET, y1 - INSET))
    k = key_corner(crop)
    k = remove_small(k, 40)
    k = despeckle(k, 2)
    bbox = k.getbbox()
    body = k.crop(bbox)
    return fit_cell(body)


def write_side(sheet, right, left):
    px = sheet.load()
    for cx, cell in ((120, right), (60, left)):
        cpx = cell.load()
        for y in range(CELL_H):
            for x in range(CELL_W):
                r, g, b, a = cpx[x, y]
                px[cx + x, SIT_ROW_Y + y] = (r, g, b, a)


def main():
    for name, rect in MAP.items():
        src = os.path.join(NPC, name + ".png")
        sheet = Image.open(src).convert("RGBA")
        assert sheet.size == (240, 600), "%s %s" % (name, sheet.size)
        right = build_from_grid(name, rect)
        left = right.transpose(Image.FLIP_LEFT_RIGHT)
        bak = src + ".rebuild.bak"
        if not os.path.exists(bak):
            Image.open(src).convert("RGBA").save(bak, "PNG")
        write_side(sheet, right, left)
        sheet.save(src)
        print("rebuilt ->", name)

    # 凯瑟琳：只对现有侧面帧去噪
    for name in KEEP_REAL:
        src = os.path.join(NPC, name + ".png")
        sheet = Image.open(src).convert("RGBA")
        right = sheet.crop((120, SIT_ROW_Y, 180, SIT_ROW_Y + 120))
        left = sheet.crop((60, SIT_ROW_Y, 120, SIT_ROW_Y + 120))
        right = despeckle(remove_small(right, 30), 2)
        left = despeckle(remove_small(left, 30), 2)
        bak = src + ".rebuild.bak"
        if not os.path.exists(bak):
            Image.open(src).convert("RGBA").save(bak, "PNG")
        write_side(sheet, right, left)
        sheet.save(src)
        print("despeckled ->", name)


if __name__ == "__main__":
    main()
