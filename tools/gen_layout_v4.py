#!/usr/bin/env python3
"""生成酒馆布局 v4.2 蓝图：SVG + PNG（评审/喂 AI 生成）+ ASCII 网格。

v4.2 相对 v4.1 的改动（用户指令）：
1. 楼梯移到右上角（贴后墙角）：接地段(上楼一段, cols18-19×rows3-6) +
   向左转角段(row2 cols16-19)，两段式 L；取消原底部转角平台。
2. 散座区右扩到 col16（cols11-16×rows7-10），7 小桌＋7 椅（row8 仅中央桌+1椅）；空置率回调到≈40%。
3. 待整理角从楼梯脚挪到右下空角（cols17-19×rows10-11）：木箱×2 + 倒扣凳×1。
4. 配套缩短后走廊/横通道，避开右上角楼梯；酒桶保持 col13-15 row4 不动。
坐标系：20col × 12row，tile 32，col0–19 左→右，row0–11 上→下，footprint 锚点 bottom-left。
"""
from __future__ import annotations

C, R = 20, 12
CELL = 40
PAD = 24

# ── 区域（x0,y0,w,h, fill, label）──
ZONES = [
    (0, 0, 20, 2, "#D9D2C5", "后墙(小门/窗/壁炉/背柜)"),
    (1, 2, 15, 2, "#EFE9DC", "后走廊(主角活动区)"),
    (1, 4, 10, 1, "#A0522D", "吧台·接左墙 col1"),
    (13, 4, 3, 1, "#C77B3E", "酒桶×3"),
    (1, 5, 15, 2, "#F2EEDD", "横通道(沿台点单)"),
    (1, 7, 8, 5, "#CBE7C9", "左·长桌区(4长桌·4凳)"),
    (11, 7, 6, 4, "#CFE3F7", "右·散座区(7小桌·7椅)"),
    (9, 7, 2, 5, "#FFFFFF", "竖通道→主门"),
    (18, 3, 2, 4, "#90CAF9", "楼梯·接地段(上楼)"),
    (16, 2, 4, 1, "#42A5F5", "楼梯·向左段(转角)"),
    (17, 10, 3, 2, "#E0D6C0", "待整理角(箱×2+倒扣凳)"),
    (9, 11, 2, 1, "#EF9A9A", "主门"),
]

# ── 家具（col,row,w,h, code, fill）──
# code: T长桌(3×1) B长凳(3×1) t小桌(1×1) c椅子(1×1) O桶 X箱 S倒扣凳
FURN = []
# 左长桌区：4 张 3×1 长桌；长凳去掉最底排(row11)，空置率回调到≈40%
for cc in (1, 5):                       # 两列（col1-3 / col5-7，col4/8 留过道）
    for ry in (8, 10):                   # 两排长桌
        FURN.append((cc, ry, 3, 1, "T", "#7BA86F"))
for ry in (7, 9):                        # 两排长凳（row9 两桌共用；去掉 row11 底排）
    for cc in (1, 5):
        FURN.append((cc, ry, 3, 1, "B", "#9BB38C"))
# 右散座区：7 张 1×1 小桌 + 7 椅（rows7/9 满排，row8 仅留中央桌+1椅）
for pos in ((11,7),(13,7),(15,7),(11,9),(13,9),(15,9),(12,8)):  # 7 小桌
    FURN.append((pos[0], pos[1], 1, 1, "t", "#6E8FCB"))
for pos in ((12,7),(14,7),(16,7),(12,9),(14,9),(16,9),(11,8)):  # 7 椅
    FURN.append((pos[0], pos[1], 1, 1, "c", "#A9C2E8"))
# 酒桶 col13–15 row4
for c in (13, 14, 15):
    FURN.append((c, 4, 1, 1, "O", "#C77B3E"))
# 右下待整理角：木箱×2 + 倒扣凳×1
FURN.append((17, 10, 1, 1, "X", "#B89B6A"))
FURN.append((18, 10, 1, 1, "X", "#B89B6A"))
FURN.append((19, 11, 1, 1, "S", "#B89B6A"))


def main() -> int:
    from PIL import Image, ImageDraw, ImageFont
    try:
        FT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
        FT_B = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 13)
    except OSError:
        FT = FT_B = ImageFont.load_default()
    # ── SVG ──
    W, H = C * CELL + PAD * 2, R * CELL + PAD * 2 + 40
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" font-family="monospace">']
    out.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#F7F4EC"/>')
    out.append(f'<text x="{PAD}" y="20" font-size="16" font-weight="bold">'
               f'炉火镇 · 酒馆布局 v4.2（20×12, tile 32）— AI 生成底稿</text>')
    oy = PAD + 24
    for (x0, y0, w, h, fill, label) in ZONES:
        px, py = PAD + x0 * CELL, oy + y0 * CELL
        out.append(f'<rect x="{px}" y="{py}" width="{w*CELL}" height="{h*CELL}" '
                   f'fill="{fill}" stroke="#5b5247" stroke-width="1.5" opacity="0.92"/>')
        if w * h > 1:
            out.append(f'<text x="{px+4}" y="{py+14}" font-size="10" fill="#3a342b">'
                       f'{label}</text>')
    for (c, r, w, h, code, fill) in FURN:
        px, py = PAD + c * CELL, oy + r * CELL
        out.append(f'<rect x="{px+2}" y="{py+2}" width="{w*CELL-4}" height="{h*CELL-4}" '
                   f'fill="{fill}" stroke="#3a342b" stroke-width="1"/>')
        out.append(f'<text x="{px+w*CELL/2}" y="{py+h*CELL/2+4}" font-size="11" '
                   f'font-weight="bold" text-anchor="middle" fill="#1d1a15">{code}</text>')
    notes = [
        ("吧台接左墙", PAD + 1 * CELL, oy + 4 * CELL),
        ("长桌区·双排凳", PAD + 1 * CELL, oy + 7 * CELL + 30),
        ("散座·7小桌", PAD + 11 * CELL, oy + 7 * CELL),
        ("楼梯·右上角", PAD + 18 * CELL, oy + 3 * CELL + 30),
        ("待整理·右下", PAD + 17 * CELL, oy + 10 * CELL),
    ]
    for txt, x, y in notes:
        out.append(f'<text x="{x}" y="{y}" font-size="11" font-weight="bold" '
                   f'fill="#C0392B">★{txt}</text>')
    out.append('</svg>')
    with open("assets/house/v4/layout_v4_2.svg", "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("SVG → assets/house/v4/layout_v4_2.svg")

    # ── PNG ──
    img = Image.new("RGB", (W, H), (247, 244, 236))
    dd = ImageDraw.Draw(img)
    dd.text((PAD, 6), "炉火镇 · 酒馆布局 v4.2（20×12, tile 32）— AI 生成底稿",
            fill=(40, 36, 30), font=FT_B)
    for (x0, y0, w, h, fill, label) in ZONES:
        px, py = PAD + x0 * CELL, oy + y0 * CELL
        dd.rectangle([px, py, px + w * CELL - 1, py + h * CELL - 1],
                     fill=fill, outline=(91, 82, 71), width=2)
        if w * h > 1:
            dd.text((px + 4, py + 4), label, fill=(58, 52, 43), font=FT)
    for (c, r, w, h, code, fill) in FURN:
        px, py = PAD + c * CELL, oy + r * CELL
        dd.rectangle([px + 2, py + 2, px + w * CELL - 3, py + h * CELL - 3],
                     fill=fill, outline=(58, 52, 43), width=1)
        dd.text((px + w * CELL / 2 - 3, py + h * CELL / 2 - 6), code,
                fill=(29, 26, 21), font=FT_B)
    for txt, x, y in notes:
        dd.text((x, y), "★" + txt, fill=(192, 57, 43), font=FT_B)
    img.save("assets/house/v4/layout_v4_2.png")
    print("PNG → assets/house/v4/layout_v4_2.png")

    # ── ASCII ──
    grid = [["·" for _ in range(C)] for _ in range(R)]
    def put(c0, r0, w, h, ch):
        for x in range(c0, min(c0 + w, C)):
            for y in range(r0, min(r0 + h, R)):
                grid[y][x] = ch
    put(0, 0, 20, 2, "#")
    put(1, 2, 15, 2, "_")
    put(1, 4, 10, 1, "=")
    put(13, 4, 3, 1, "O")
    put(1, 5, 15, 2, ".")
    put(9, 7, 2, 5, "|")
    put(18, 3, 2, 4, "\\")      # 楼梯·接地(上楼)
    put(16, 2, 4, 1, "/")       # 楼梯·向左转角
    put(17, 10, 3, 2, "z")      # 待整理角
    put(9, 11, 2, 1, "M")
    for (c, r, w, h, code, _f) in FURN:
        put(c, r, w, h, code)
    print("\n".join(" ".join(row) for row in grid))
    print("\n图例: # 后墙 |=竖通道 _ 走廊 .=横通道 = 吧台 O 酒桶 M 主门 "
          "T 长桌 B 长凳 t 小桌 c 椅子 X 木箱 S 倒扣凳 \\ 楼梯接地 / 楼梯左转 z 待整理")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
