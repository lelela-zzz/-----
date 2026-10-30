"""生成萃歌（酒馆老板娘）的**占位**行走图集。

为什么是占位：现有 19 张图集里没有老板娘/丰收神明的形象，用户选择「先留数据位、
等图」—— 先用一张风格对齐的简笔像素人把流程跑通。用户之后只要拿一张新的
240x480 图集覆盖 assets/actors/npc/酒馆老板娘_萃歌.png（同名），游戏立刻换人，
代码与数据一行都不用改。

规格与其它 NPC 完全一致：240x480 = 4 列 x 4 行，单格 60x120，
行序 0 下 / 1 左 / 2 右 / 3 上，脚底压在格底 y=119，水平中心 x=30。

用法：python tools/make_cuige_placeholder.py
"""
from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "actors", "npc", "酒馆老板娘_萃歌.png")

CELL_W, CELL_H = 60, 120
COLS, ROWS = 4, 4

# 色板：全部取自现有角色的暖色系，避免占位人跳出画面
OUTLINE = (42, 32, 32, 255)
HAIR = (232, 196, 106, 255)
HAIR_DARK = (188, 148, 66, 255)
SKIN = (242, 203, 164, 255)
SKIN_DARK = (206, 158, 122, 255)
APRON = (239, 230, 210, 255)
APRON_DARK = (202, 190, 166, 255)
DRESS = (138, 90, 60, 255)
DRESS_DARK = (104, 64, 40, 255)
BOOT = (74, 52, 40, 255)
BERRY = (176, 82, 78, 255)   # 围裙口袋里露出的野莓，一点身份暗示

# 每格内的骨架高度（相对格顶）
HEAD_TOP = 8
HEAD_H = 18
BODY_H = 44
LEG_H = 38
FOOT_Y = 119                 # 脚底（格内坐标）


def rect(dst: Image.Image, x0: int, y0: int, x1: int, y1: int, color) -> None:
    """闭区间矩形，坐标越界自动裁掉。"""
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(CELL_W - 1, x1), min(CELL_H - 1, y1)
    if x1 < x0 or y1 < y0:
        return
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            dst.putpixel((x, y), color)


def outlined(dst: Image.Image, x0: int, y0: int, x1: int, y1: int, color) -> None:
    """先描 1px 外轮廓再填色 —— 像素角色不描边会糊在背景里。"""
    rect(dst, x0 - 1, y0 - 1, x1 + 1, y1 + 1, OUTLINE)
    rect(dst, x0, y0, x1, y1, color)


def draw_cell(facing: str, frame: int) -> Image.Image:
    img = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    cx = 30

    # 走路循环：帧 0/2 并腿，1/3 前后错开；同时上半身 ±1px 起伏
    step = {0: 0, 1: 2, 2: 0, 3: -2}[frame]
    bob = 1 if frame in (1, 3) else 0

    top = HEAD_TOP + bob
    head_b = top + HEAD_H - 1
    body_t = top + HEAD_H
    body_b = body_t + BODY_H - 1
    leg_t = body_b + 1
    leg_b = FOOT_Y - 10
    boot_b = FOOT_Y

    # ---- 腿与靴（先画，被裙摆压住上半截）----
    legs = [(cx - 7 + step, cx - 3 + step), (cx + 3 - step, cx + 7 - step)]
    for lx0, lx1 in legs:
        rect(img, lx0, leg_t, lx1, leg_b, SKIN_DARK)
        rect(img, lx0 - 1, leg_b + 1, lx1 + 1, boot_b, BOOT)

    # ---- 裙摆 + 围裙 ----
    outlined(img, cx - 10, body_t, cx + 10, body_b, DRESS)
    rect(img, cx - 10, body_b - 5, cx + 10, body_b, DRESS_DARK)      # 裙摆暗边
    outlined(img, cx - 6, body_t + 8, cx + 6, body_b - 1, APRON)     # 围裙正面
    rect(img, cx - 6, body_t + 8, cx + 6, body_t + 9, APRON_DARK)    # 围裙上沿
    rect(img, cx + 3, body_t + 30, cx + 5, body_t + 32, BERRY)       # 口袋里的野莓
    # 围裙系带（绕过腰后）
    rect(img, cx - 10, body_t + 20, cx - 7, body_t + 21, APRON_DARK)
    rect(img, cx + 7, body_t + 20, cx + 10, body_t + 21, APRON_DARK)

    # ---- 手臂 ----
    if facing == "down":
        outlined(img, cx - 13, body_t + 2, cx - 10, body_t + 24, SKIN)
        outlined(img, cx + 10, body_t + 2, cx + 13, body_t + 24, SKIN)
    elif facing == "up":
        outlined(img, cx - 13, body_t + 2, cx - 10, body_t + 24, SKIN_DARK)
        outlined(img, cx + 10, body_t + 2, cx + 13, body_t + 24, SKIN_DARK)
    else:
        # 侧面只看得见靠镜头的那只手，另一只被身体挡住
        side = -1 if facing == "left" else 1
        outlined(img, cx + side * 10 - (2 if side > 0 else 0),
                 body_t + 2, cx + side * 13 - (2 if side > 0 else 0), body_t + 24, SKIN)

    # ---- 头 ----
    outlined(img, cx - 8, top, cx + 8, head_b, SKIN)

    if facing == "up":
        # 背面：整颗头都是头发，只露出脖颈
        rect(img, cx - 8, top, cx + 8, head_b - 2, HAIR)
        rect(img, cx - 8, top, cx + 8, top + 3, HAIR_DARK)
        rect(img, cx - 3, head_b - 1, cx + 3, head_b, SKIN_DARK)
    else:
        # 刘海 + 两侧鬓发
        rect(img, cx - 8, top, cx + 8, top + 6, HAIR)
        rect(img, cx - 8, top + 7, cx - 6, head_b - 2, HAIR)
        rect(img, cx + 6, top + 7, cx + 8, head_b - 2, HAIR)
        rect(img, cx - 8, top, cx + 8, top + 2, HAIR_DARK)
        # 五官：正面两只眼，侧面一只（靠行进方向那一侧）
        eye_y = top + 11
        if facing == "down":
            rect(img, cx - 4, eye_y, cx - 3, eye_y + 1, OUTLINE)
            rect(img, cx + 3, eye_y, cx + 4, eye_y + 1, OUTLINE)
            rect(img, cx - 1, top + 9, cx + 1, top + 11, HAIR_DARK)   # 鼻梁投影
        elif facing == "left":
            rect(img, cx - 5, eye_y, cx - 4, eye_y + 1, OUTLINE)
        else:
            rect(img, cx + 4, eye_y, cx + 5, eye_y + 1, OUTLINE)

    # ---- 发髻（老板娘的小盘发，四个方向都在同一侧，剪影一致）----
    if facing in ("down", "left", "right"):
        outlined(img, cx - 4, top - 4, cx + 4, top - 1, HAIR)
        rect(img, cx - 4, top - 3, cx + 4, top - 2, HAIR_DARK)

    return img


def main() -> None:
    sheet = Image.new("RGBA", (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    order = ["down", "left", "right", "up"]
    for row, facing in enumerate(order):
        for col in range(COLS):
            cell = draw_cell(facing, col)
            sheet.paste(cell, (col * CELL_W, row * CELL_H), cell)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print("wrote %s (%dx%d)" % (os.path.relpath(OUT, ROOT), sheet.width, sheet.height))


if __name__ == "__main__":
    main()
