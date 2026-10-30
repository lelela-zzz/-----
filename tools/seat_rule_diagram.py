#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""坐姿方向规则示意：4 张长凳座位 —— 左椅用「朝右(col2)」、右椅用「朝左(col1)」，
均为图集第 5 行的侧面真坐姿帧（正/背占位稿不用）。逐座展示实际会用的那一帧 + 朝向箭头。
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC_DIR = os.path.join(ROOT, "assets", "actors", "npc")
OUT = os.path.join(ROOT, "tests", "seat_rule_diagram.png")

ASSIGN = {"s1": "雪山探险家_哈特菲利亚", "s2": "矿工少年_西蒙",
          "s3": "矮人战士_爱德华", "s4": "集市管理员_凯瑟琳"}
SIDE_CN = {"left": "左椅", "right": "右椅"}
COL_CN = {2: "朝右 col2", 1: "朝左 col1"}


def sit_cell(name, col, scale=2):
    sheet = Image.open(os.path.join(NPC_DIR, name + ".png")).convert("RGBA")
    cell = sheet.crop((col * 60, 480, col * 60 + 60, 600))
    return cell.resize((60 * scale, 120 * scale), Image.NEAREST)


def main():
    with open(os.path.join(ROOT, "data", "seats.json"), encoding="utf-8") as f:
        seats = {s["id"]: s for s in json.load(f)}
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 15)
        fontb = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 17)
    except Exception:
        font = fontb = ImageFont.load_default()

    PW, PH = 150, 380
    W, H = PW * 4 + 20, PH + 20
    canvas = Image.new("RGBA", (W, H), (28, 22, 18, 255))
    d = ImageDraw.Draw(canvas)
    d.text((10, 8), "坐姿方向：左椅→朝右(col2)　右椅→朝左(col1)　只用第5行侧面帧",
           font=fontb, fill=(240, 232, 210, 255))

    order = ["s1", "s2", "s3", "s4"]
    for i, sid in enumerate(order):
        s = seats[sid]
        side = s.get("side", "left")
        col = 2 if side == "left" else 1
        color = (90, 160, 245, 255) if side == "left" else (245, 165, 75, 255)
        x0 = 10 + i * PW
        # 面板分隔
        if i > 0:
            d.line([(x0 - 4, 34), (x0 - 4, H - 6)], fill=(70, 60, 52, 255), width=1)
        # 座位编号 + 侧别
        d.text((x0 + 4, 38), "%s %s" % (sid, SIDE_CN.get(side, side)), font=fontb, fill=color)
        # 角色（实际帧）
        cell = sit_cell(ASSIGN[sid], col)
        cx = x0 + (PW - 4) // 2
        sprite_top = 70
        canvas.alpha_composite(cell, (cx - cell.width // 2, sprite_top))
        # 朝向箭头
        ay = sprite_top + cell.height + 10
        if col == 2:  # 朝右
            d.line([(cx - 16, ay), (cx + 16, ay)], fill=color, width=3)
            d.polygon([(cx + 18, ay), (cx + 8, ay - 6), (cx + 8, ay + 6)], fill=color)
        else:         # 朝左
            d.line([(cx - 16, ay), (cx + 16, ay)], fill=color, width=3)
            d.polygon([(cx - 18, ay), (cx - 8, ay - 6), (cx - 8, ay + 6)], fill=color)
        # 帧说明
        d.text((x0 + 8, ay + 12), COL_CN[col], font=font, fill=(220, 210, 190, 255))

    canvas.convert("RGB").save(OUT)
    print("saved", OUT, canvas.size)


if __name__ == "__main__":
    main()
