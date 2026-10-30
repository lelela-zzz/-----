#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验 data/seats.json 的座位坐标与路径不会落在家具碰撞框 / 墙外。

纯数据检查，不需要 Godot 渲染，可在 headless 下跑。
用法：python tools/check_seats.py
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(ROOT, "assets", "house", "v4", "objects", "props.json")
SEATS = os.path.join(ROOT, "data", "seats.json")

# 房间可行走矩形（来自 scripts/room_collision.gd）
ROOM = (24.0, 76.0, 599.0, 230.0)  # x, y, w, h  -> x[24,623] y[76,306]
DOOR_GAP = (296.0, 342.0)          # 底墙门洞 x 范围
DOOR_SILL_Y = 378.0


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def rects_of(props):
    """返回所有会挡路的家具碰撞矩形 (name, x0,y0,x1,y1)。no_collision 的跳过。"""
    out = []
    for e in props["props"]:
        if e.get("no_collision", False):
            continue
        c = e.get("collision_rect", [0, 0, 0, 0])
        if c[2] <= 0 or c[3] <= 0:
            continue
        out.append((e["name"], c[0], c[1], c[0] + c[2], c[1] + c[3]))
    return out


def in_rect(px, py, r):
    return r[1] <= py <= r[3] and r[0] <= px <= r[2]


def walkable(px, py, rects, allow_furniture=False):
    """点是否在可行走区域内（房间内、不在墙内、不在家具碰撞内）。
    allow_furniture=True 时允许落在家具碰撞内——用于"坐长凳"的座位落点
    （顾客不走物理、直接落座，凳在桌面碰撞框内也成立）。"""
    # 房间内
    if not (ROOM[0] <= px <= ROOM[0] + ROOM[2] and ROOM[1] <= py <= ROOM[1] + ROOM[3]):
        return False, "房间外"
    # 底墙（门洞除外）
    if py >= ROOM[1] + ROOM[3]:  # y >= 306
        if not (DOOR_GAP[0] <= px <= DOOR_GAP[1]):
            return False, "底墙"
    # 家具碰撞
    if not allow_furniture:
        for name, x0, y0, x1, y1 in rects:
            if in_rect(px, py, (x0, y0, x1, y1)):
                return False, "家具:%s" % name
    return True, "ok"


def main():
    props = load_json(PROPS)
    seats = load_json(SEATS)
    rects = rects_of(props)

    fails = 0
    print("== 座位落点校验 ==")
    for s in seats:
        sid = s["id"]
        fx, fy = s["x"], s["y"]
        # 座位落点：允许在长凳(桌面碰撞框)内，但不能出房间/进墙
        ok, why = walkable(fx, fy, rects, allow_furniture=True)
        tag = "OK " if ok else "FAIL"
        if not ok:
            fails += 1
        on_bench = any(in_rect(fx, fy, (x0, y0, x1, y1)) for _n, x0, y0, x1, y1 in rects)
        print("  [%s] %s 落点(%.0f,%.0f): %s%s" % (
            tag, sid, fx, fy, why, "（坐长凳，允许压桌面碰撞）" if on_bench else ""))

        print("     路径点（除最后的落点外须可行走）:")
        pts = s.get("path", [])
        for i, p in enumerate(pts):
            px, py = p[0], p[1]
            is_last = (i == len(pts) - 1)
            ok2, why2 = walkable(px, py, rects, allow_furniture=is_last)
            tag2 = "OK " if ok2 else "FAIL"
            if not ok2:
                fails += 1
            print("       [%s] (%.0f,%.0f): %s%s" % (
                tag2, px, py, why2, "（落点）" if is_last else ""))

    print("== 结果 ==")
    if fails == 0:
        print("全部通过：4 个座位落点合规（可坐长凳），其余路径点都在可行走区内。")
        return 0
    else:
        print("有 %d 处冲突，需要修正。" % fails)
        return 1


if __name__ == "__main__":
    sys.exit(main())
