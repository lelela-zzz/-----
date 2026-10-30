#!/usr/bin/env python3
"""生成酒馆布局 v4.3 蓝图：SVG + PNG + ASCII（先调布局，再喂 AI 生成）。

v4.3 相对 v4.2 的改动（本轮用户指令）：
1. **右侧不再拥挤 / 楼梯通道留空**：cols17-19 × rows7-11 全空，禁放任何家具；
   楼梯（右上角两段式 L）落地口与下行路径完全让开。
2. **散座减密**：7 小桌+7 椅 → 6 小桌+6 椅，收在 cols11-16 × rows7-9，row10 留过道。
3. **待整理角挪到左下**：cols2-4 × row11（木箱×2 + 倒扣凳×1），远离楼梯。
4. 其余不变：吧台接左墙 col1、酒桶 col13-15 row4、左长桌 4 张 + 长凳 4 条。

生成约束（写给 AI，不是几何）：无地面投射阴影、窗不射光、右侧楼梯口留空。
坐标系：20col × 12row，tile 32，col0–19 左→右，row0–11 上→下。
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
    (11, 7, 6, 3, "#CFE3F7", "右·散座区(6小桌·6椅)"),
    (9, 7, 2, 5, "#FFFFFF", "竖通道→主门"),
    (18, 3, 2, 4, "#90CAF9", "楼梯·接地段(上楼)"),
    (16, 2, 4, 1, "#42A5F5", "楼梯·向左段(转角)"),
    (17, 7, 3, 5, "#E8F5E9", "★楼梯通道·禁放家具"),
    (2, 11, 3, 1, "#E0D6C0", "待整理角(左下 箱×2+倒扣凳)"),
    (9, 11, 2, 1, "#EF9A9A", "主门"),
]

# ── 家具（col,row,w,h, code, fill）──
FURN = []
# 左长桌区：4 张 3×1 长桌 + 4 条长凳（row11 空出放待整理角）
for cc in (1, 5):
    for ry in (8, 10):
        FURN.append((cc, ry, 3, 1, "T", "#7BA86F"))
for ry in (7, 9):
    for cc in (1, 5):
        FURN.append((cc, ry, 3, 1, "B", "#9BB38C"))
# 右散座区：6 小桌 + 6 椅（收在 cols11-16 × rows7-9，row10 与 cols17+ 留空）
for pos in ((11, 7), (13, 7), (15, 7), (11, 9), (13, 9), (15, 9)):
    FURN.append((pos[0], pos[1], 1, 1, "t", "#6E8FCB"))
for pos in ((12, 7), (14, 7), (16, 7), (12, 9), (14, 9), (16, 9)):
    FURN.append((pos[0], pos[1], 1, 1, "c", "#A9C2E8"))
# 酒桶 col13–15 row4
for c in (13, 14, 15):
    FURN.append((c, 4, 1, 1, "O", "#C77B3E"))
# 左下待整理角：木箱×2 + 倒扣凳×1
FURN.append((2, 11, 1, 1, "X", "#B89B6A"))
FURN.append((3, 11, 1, 1, "X", "#B89B6A"))
FURN.append((4, 11, 1, 1, "S", "#B89B6A"))

TITLE = "炉火镇 · 酒馆布局 v4.3（20×12, tile 32）— AI 生成底稿"


def main() -> int:
    from PIL import Image, ImageDraw, ImageFont
    try:
        FT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
        FT_B = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 13)
    except OSError:
        FT = FT_B = ImageFont.load_default()
    W, H = C * CELL + PAD * 2, R * CELL + PAD * 2 + 40
    oy = PAD + 24
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" font-family="monospace">']
    out.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#F7F4EC"/>')
    out.append(f'<text x="{PAD}" y="20" font-size="16" font-weight="bold">{TITLE}</text>')
    for (x0, y0, w, h, fill, label) in ZONES:
        px, py = PAD + x0 * CELL, oy + y0 * CELL
        out.append(f'<rect x="{px}" y="{py}" width="{w*CELL}" height="{h*CELL}" '
                   f'fill="{fill}" stroke="#5b5247" stroke-width="1.5" opacity="0.92"/>')
        if w * h > 1:
            out.append(f'<text x="{px+4}" y="{py+14}" font-size="10" fill="#3a342b">{label}</text>')
    for (c, r, w, h, code, fill) in FURN:
        px, py = PAD + c * CELL, oy + r * CELL
        out.append(f'<rect x="{px+2}" y="{py+2}" width="{w*CELL-4}" height="{h*CELL-4}" '
                   f'fill="{fill}" stroke="#3a342b" stroke-width="1"/>')
        out.append(f'<text x="{px+w*CELL/2}" y="{py+h*CELL/2+4}" font-size="11" '
                   f'font-weight="bold" text-anchor="middle" fill="#1d1a15">{code}</text>')
    notes = [
        ("吧台接左墙", PAD + 1 * CELL, oy + 4 * CELL),
        ("长桌区·双排凳", PAD + 1 * CELL, oy + 7 * CELL + 30),
        ("散座·6小桌", PAD + 11 * CELL, oy + 7 * CELL),
        ("楼梯·右上角", PAD + 18 * CELL, oy + 3 * CELL + 30),
        ("★楼梯通道留空", PAD + 17 * CELL, oy + 8 * CELL + 20),
        ("待整理·左下", PAD + 2 * CELL, oy + 11 * CELL),
    ]
    for txt, x, y in notes:
        out.append(f'<text x="{x}" y="{y}" font-size="11" font-weight="bold" fill="#C0392B">★{txt}</text>')
    out.append('</svg>')
    with open("assets/house/v4/layout_v4_3.svg", "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("SVG → assets/house/v4/layout_v4_3.svg")

    img = Image.new("RGB", (W, H), (247, 244, 236))
    dd = ImageDraw.Draw(img)
    dd.text((PAD, 6), TITLE, fill=(40, 36, 30), font=FT_B)
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
        dd.text((px + w * CELL / 2 - 3, py + h * CELL / 2 - 6), code, fill=(29, 26, 21), font=FT_B)
    for txt, x, y in notes:
        dd.text((x, y), "★" + txt, fill=(192, 57, 43), font=FT_B)
    img.save("assets/house/v4/layout_v4_3.png")
    print("PNG → assets/house/v4/layout_v4_3.png")

    grid = [["·" for _ in range(C)] for _ in range(R)]

    def put(c0, r0, w, h, ch):
        for x in range(c0, min(c0 + w, C)):
            for y in range(r0, min(r0 + h, R)):
                grid[y][x] = ch

    put(0, 0, 20, 2, "#")
    put(1, 2, 15, 2, "_")
    put(1, 4, 10, 1, "=")
    put(1, 5, 15, 2, ".")
    put(9, 7, 2, 5, "|")
    put(18, 3, 2, 4, "\\")
    put(16, 2, 4, 1, "/")
    put(17, 7, 3, 5, "o")      # 楼梯通道（空）
    put(2, 11, 3, 1, "z")      # 待整理角（左下）
    put(9, 11, 2, 1, "M")
    for (c, r, w, h, code, _f) in FURN:
        put(c, r, w, h, code)
    print("\n".join(" ".join(row) for row in grid))
    print("\n图例: # 后墙 |=竖通道 _ 走廊 .=横通道 = 吧台 O 酒桶 M 主门 "
          "T 长桌 B 长凳 t 小桌 c 椅子 X 木箱 S 倒扣凳 \\ 楼梯接地 / 楼梯左转 "
          "o 楼梯通道(空) z 待整理")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
