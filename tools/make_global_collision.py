#!/usr/bin/env python3
"""Generate a 3x global collision overlay for the tavern (current props.json).

RULE (project convention, 2026-10-22): the day background map
(`scene_day_v15_1x.png`) is kept as the BASE LAYER so the user can compare
the collision boxes against the actual art. Do not replace it with a solid
color background.

Draws on top of the base:
  - room bounds (walkable rect) in green outline
  - the 4 wall bands (generated from room_bounds + wall_thickness) as faint green fill
  - each prop sprite_rect in gray outline
  - each prop collision_rect: blue for wall items, orange for ground items
  - prop index label at the top-left of each collision box
  - a small legend
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
SRC = os.path.join(PROJ, "assets/house/v4/objects/props.json")
# base day map derived from props.json "source" (.../v4/objects -> .../v4)
BASE_DAY = os.path.join(os.path.dirname(os.path.dirname(SRC)), "scene_day_v15_1x.png")
OUT = os.path.join(PROJ, "tests/probe_shots/global_collision.png")

SCALE = 3
W, H = 640, 384
IW, IH = W * SCALE, H * SCALE

# overlay colors (drawn on top of the real day map)
GRAY = (150, 150, 160)         # sprite rect
BLUE = (64, 140, 255)          # wall collision
ORANGE = (255, 150, 40)        # ground collision
GREEN = (40, 225, 120)         # room bounds / walls
TEXT = (255, 255, 255)
STROKE = (0, 0, 0)

with open(SRC, "r", encoding="utf-8") as f:
    data = json.load(f)

# room bounds + walls parsed from room_collision.gd (single source of truth)
import re as _re
_gd = open(os.path.join(PROJ, "scripts/room_collision.gd"), "r", encoding="utf-8").read()
_m = _re.search(r"room_bounds: Rect2 = Rect2\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)", _gd)
_t = _re.search(r"wall_thickness: float = ([\d.]+)", _gd)
_dg = _re.search(r"door_gap_x: Vector2 = Vector2\(\s*([\d.]+)[,\s]+([\d.]+)", _gd)
_ds = _re.search(r"door_sill_y: float = ([\d.]+)", _gd)
bx, by, bw, bh = (float(v) for v in _m.groups())
t = float(_t.group(1))
b = (bx, by, bw, bh)   # x, y, w, h
door_l = float(_dg.group(1)) if _dg else None
door_r = float(_dg.group(2)) if _dg else None
sill = float(_ds.group(1)) if _ds else None
MAP_H = 384.0
walls = [
    (b[0] - t, b[1] - t, b[0] + b[2] + t, b[1]),            # top
    (b[0] - t, b[1], b[0], b[1] + b[3]),                    # left
    (b[0] + b[2], b[1], b[0] + b[2] + t, b[1] + b[3]),      # right
]
if door_l is None:  # bottom: full band (no door)
    walls.append((b[0] - t, b[1] + b[3], b[0] + b[2] + t, b[1] + b[3] + t))
else:  # bottom split by the door gap + sill strip
    walls.append((b[0] - t, b[1] + b[3], door_l - (b[0] - t), t))
    walls.append((door_r, b[1] + b[3], (b[0] + b[2] + t) - door_r, t))
    walls.append((door_l, sill, door_r - door_l, MAP_H - sill))
room = (b[0], b[1], b[0] + b[2], b[1] + b[3])


def s(v):
    return int(round(v * SCALE))


def rect_pts(r):
    x, y, w, h = r
    return (s(x), s(y), s(x + w), s(y + h))


# base layer: real day map, NEAREST upscaled 3x to keep pixel-art crisp
base = Image.open(BASE_DAY).convert("RGB")
base = base.resize((IW, IH), Image.NEAREST)
img = base.copy()
d = ImageDraw.Draw(img, "RGBA")

# faint wall bands
for wr in walls:
    x0, y0, x1, y1 = rect_pts(wr)
    d.rectangle([x0, y0, x1, y1], fill=(40, 225, 120, 35))

# room bounds outline (thick green)
x0, y0, x1, y1 = rect_pts(room)
d.rectangle([x0, y0, x1, y1], outline=GREEN, width=3)

font = None
try:
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 20)
except Exception:
    try:
        font = ImageFont.truetype("arial.ttf", 20)
    except Exception:
        font = ImageFont.load_default()

for i, p in enumerate(data["props"]):
    label = f"{i:02d}"
    wall = p.get("wall", False)
    col = BLUE if wall else ORANGE
    # sprite rect (gray)
    sr = p.get("sprite_rect")
    if sr:
        sx0, sy0, sx1, sy1 = rect_pts(sr)
        d.rectangle([sx0, sy0, sx1, sy1], outline=GRAY, width=1)
    # collision rect
    cr = p["collision_rect"]
    cx0, cy0, cx1, cy1 = rect_pts(cr)
    d.rectangle([cx0, cy0, cx1, cy1], outline=col, width=3,
                fill=(col[0], col[1], col[2], 70))
    # label (white with dark stroke for readability on busy base)
    d.text((cx0 + 5, cy0 + 4), label, fill=TEXT, font=font,
           stroke_width=3, stroke_fill=STROKE)

# legend (bottom-right, empty area)
lx, ly = IW - 380, IH - 168
d.rectangle([lx, ly, lx + 368, ly + 156], outline=(90, 90, 100), width=1,
            fill=(0, 0, 0, 140))
d.text((lx + 14, ly + 14), "Legend", fill=TEXT, font=font)
d.text((lx + 14, ly + 42), "Gray  = sprite_rect", fill=GRAY, font=font)
d.text((lx + 14, ly + 68), "Blue  = collision (wall)", fill=BLUE, font=font)
d.text((lx + 14, ly + 94), "Orange= collision (ground)", fill=ORANGE, font=font)
d.text((lx + 14, ly + 120), "Green = room bounds / walls", fill=GREEN, font=font)
d.text((lx + 14, ly + 138), "NN = prop index 00..16", fill=TEXT, font=font)

img.save(OUT)
print("wrote", OUT, img.size, "| base =", os.path.basename(BASE_DAY))
