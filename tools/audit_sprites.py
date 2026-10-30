#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""审计所有角色的图集尺寸 vs 数据声明，揪出「行/列与图集高度不匹配」这类会让
静态 NPC 显示错乱的隐患，并对受影响的角色渲染 错误(rows=4) vs 正确(rows=H/ch) 对照图。

背景：scenes/npc.tscn 的 CharacterAnimator 未显式设 rows，默认 rows=4；
顾客图集是 240x600（5 行坐姿）。当某角色既有静态 NPC 站位、图集又是 5 行时，
npc.tscn 会按 600/4=150px 切格 -> 错乱。本脚本找出所有此类角色。
"""
from __future__ import annotations
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "npcs.json")


def fs_path(res_path: str) -> str:
    if res_path.startswith("res://"):
        return os.path.join(ROOT, res_path[len("res://"):])
    return res_path


def main() -> None:
    with open(DATA, encoding="utf-8") as f:
        data = json.load(f)
    npcs = data.get("npcs", [])

    problems = []
    print("%-20s %-8s %-8s %-8s %-6s %-6s %-8s %s" % (
        "id", "sheet", "cell", "atlas", "cols", "rows", "static?", "verdict"))
    print("-" * 96)

    for d in npcs:
        nid = str(d.get("id", ""))
        sheet_res = str(d.get("sheet", ""))
        p = fs_path(sheet_res)
        cell = d.get("cell", [60, 120])
        cw, ch = int(cell[0]), int(cell[1])
        placements = d.get("placement", []) or []
        has_static = len(placements) > 0
        if not os.path.exists(p):
            print("%-20s MISSING %s" % (nid, sheet_res))
            problems.append((nid, "missing sheet"))
            continue
        W, H = Image.open(p).size
        cols = W / cw
        rows = H / ch
        cols_int = (W % cw == 0)
        rows_int = (H % ch == 0)
        static_ok = True
        verdict = "OK"
        if not cols_int or not rows_int:
            verdict = "ATLAS/CELL 不整除!"
            problems.append((nid, "atlas %dx%d not divisible by cell %dx%d" % (W, H, cw, ch)))
        elif has_static and rows != 4:
            verdict = "静态NPC会错乱(rows=%d 但 npc.tscn 用4)" % rows
            static_ok = False
            problems.append((nid, "static npc + %d-row atlas" % rows))
        print("%-20s %-8s %-8s %-8s %-6s %-6s %-8s %s" % (
            nid, "%dx%d" % (W, H), "%dx%d" % (cw, ch), "%dx%d" % (W, H),
            ("%.0f" % cols) if cols_int else ("%.2f!" % cols),
            ("%.0f" % rows) if rows_int else ("%.2f!" % rows),
            ("是" if has_static else "否"), verdict))

    print("-" * 96)
    if problems:
        print("发现 %d 处问题:" % len(problems))
        for nid, why in problems:
            print("  - %s: %s" % (nid, why))
    else:
        print("全部角色尺寸/行列一致，无类似问题。")

    # 对照图：对每个"静态NPC + 非4行"的角色渲染 错误 vs 正确
    for nid, why in problems:
        if "static npc" not in why:
            continue
        d = next(x for x in npcs if str(x.get("id", "")) == nid)
        p = fs_path(str(d.get("sheet", "")))
        cell = d.get("cell", [60, 120])
        cw, ch = int(cell[0]), int(cell[1])
        sheet = Image.open(p).convert("RGBA")
        W, H = sheet.size
        rows = H // ch
        broken_ch = H // 4  # npc.tscn 默认 4 行时每格高度
        correct = sheet.crop((0, 0, cw, ch))          # 正确：row0 col0
        broken = sheet.crop((0, 0, cw, broken_ch))    # 错误：150 高
        # 放到画布上，脚下画一条地线，脚点对齐
        S = 4
        pad = 20
        canvas = Image.new("RGBA", ((cw * S) * 2 + pad * 3, ch * S + pad * 2 + 40), (40, 32, 26, 255))
        foot_x = [pad + cw * S // 2, pad * 2 + cw * S + cw * S // 2]
        foot_y = pad + ch * S
        # 地线
        from PIL import ImageDraw
        draw = ImageDraw.Draw(canvas)
        for fx in foot_x:
            draw.line([(fx - cw * S // 2, foot_y), (fx + cw * S // 2, foot_y)], fill=(120, 200, 120, 255), width=2)
        # 正确
        c = correct.resize((cw * S, ch * S), Image.NEAREST)
        canvas.alpha_composite(c, (pad, pad))
        # 错误：高 broken_ch*S，脚底对齐 foot_y（position=-60 时底部=脚点+extra）
        b = broken.resize((cw * S, broken_ch * S), Image.NEAREST)
        # 错误帧显示：顶 -60*S、高度 broken_ch*S，底= + (broken_ch-ch)*S 相对脚线
        extra = (broken_ch - ch) * S
        canvas.alpha_composite(b, (pad * 2 + cw * S, pad - extra))
        # 标签
        from PIL import ImageFont
        try:
            font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 16)
        except Exception:
            font = ImageFont.load_default()
        draw.text((pad + 4, ch * S + pad + 6), "修复后（正确 5 行 / 60x120）",
                  font=font, fill=(150, 235, 150, 255))
        draw.text((pad * 2 + cw * S + 4, ch * S + pad + 6), "修复前（误按 4 行 / 60x150）",
                  font=font, fill=(240, 150, 150, 255))
        canvas.convert("RGB").save(os.path.join(ROOT, "tests", "audit_%s_rows.png" % nid))
        print("对照图 -> tests/audit_%s_rows.png (左=正确%d行 右=错误4行)" % (nid, rows))


if __name__ == "__main__":
    main()
