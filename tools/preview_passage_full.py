"""离线拼一张「整张地图」预览图，用来肉眼验收酒馆↔地窖的接缝。

不跑引擎，直接照 world.tscn 的叠法用 Pillow 合成：
  1. 地窖底图（662×512，右缘已补过 22px）贴在 (-22, 0)  ← 屏幕坐标，world y + 398 = 屏幕 y
  2. 酒馆底图（1280×768）缩小一半 → 640×384，贴在 (0, 398)
     它的门洞在 assets 里已经抠成 alpha=0，所以地窖那段楼梯会透出来
  3. --closed 时再把 door_panel_day（66×82）缩到 33×41 贴回门扇位置，看起来就是关着门

产物（tests/passage_shots/）：
  00_full_map_closed.png   门关着的整图
  00_full_map_open.png     门虚化之后的整图
  00b_door_pair.png        同一块门洞区域的关/开并排对照

用法：
    python tools/preview_passage_full.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SHOTS = ROOT / "tests" / "passage_shots"

CELLAR = ROOT / "assets/cellar/v1/scene_night_pad.png"
TAVERN = ROOT / "assets/house/v4/scene_day_v16_2x.png"
DOOR = ROOT / "assets/house/v4/door_panel_day_v16.png"

CELLAR_OFFSET = (-22, 0)          # 屏幕坐标（world 的 -398 已经算成屏幕 0）
TAVERN_AT = (0, 398)
TAVERN_SCALE = 0.5
HOLE = (106, 28, 41, 55)          # 门洞（world 坐标）x, y, w, h —— 与 punch_cellar_passage.HOLE 一致
DOOR_SCALE = 0.5
MAP_SIZE = (640, 782)

# 玩家在店堂时地窖压的那层阴影（与 scripts/cellar_shade.gd 的 dark_alpha/颜色一致）
SHADE_COLOR = (10, 13, 23)
SHADE_ALPHA = 0.5
SHADE_RECT = (-22, 0, 662, 398)   # 屏幕坐标 x, y, w, h —— world y<=0 那一整块

PAIR_CROP = (60, 330, 250, 500)   # 并排对照用的裁剪框（屏幕坐标）


def build(closed: bool) -> Image.Image:
    cell = Image.open(CELLAR).convert("RGBA")
    tav = Image.open(TAVERN).convert("RGBA")
    tav = tav.resize(
        (int(tav.width * TAVERN_SCALE), int(tav.height * TAVERN_SCALE)),
        Image.NEAREST,
    )

    canvas = Image.new("RGBA", MAP_SIZE, (0, 0, 0, 255))
    canvas.alpha_composite(cell, CELLAR_OFFSET)

    # 地窖整体阴影：只压 world y<=0 那一块，跟游戏里 CellarShade 一致
    shade = Image.new("RGBA", MAP_SIZE, (0, 0, 0, 0))
    sx, sy, sw, sh = SHADE_RECT
    ImageDraw.Draw(shade).rectangle(
        (sx, sy, sx + sw - 1, sy + sh - 1),
        fill=(SHADE_COLOR[0], SHADE_COLOR[1], SHADE_COLOR[2], int(255 * SHADE_ALPHA)),
    )
    canvas.alpha_composite(shade, (0, 0))

    canvas.alpha_composite(tav, TAVERN_AT)

    if closed:
        door = Image.open(DOOR).convert("RGBA")
        door = door.resize(
            (int(door.width * DOOR_SCALE), int(door.height * DOOR_SCALE)),
            Image.NEAREST,
        )
        canvas.alpha_composite(door, (HOLE[0], TAVERN_AT[1] + HOLE[1]))
    return canvas


def main() -> None:
    SHOTS.mkdir(parents=True, exist_ok=True)

    closed = build(True)
    opened = build(False)
    closed.save(SHOTS / "00_full_map_closed.png")
    opened.save(SHOTS / "00_full_map_open.png")

    a = closed.crop(PAIR_CROP)
    b = opened.crop(PAIR_CROP)
    gap = 6
    pair = Image.new("RGBA", (a.width * 2 + gap, a.height), (255, 0, 255, 255))
    pair.paste(a, (0, 0))
    pair.paste(b, (a.width + gap, 0))
    pair = pair.resize((pair.width * 2, pair.height * 2), Image.NEAREST)
    pair.save(SHOTS / "00b_door_pair.png")

    print(f"写出 00_full_map_closed / 00_full_map_open / 00b_door_pair -> {SHOTS}")


if __name__ == "__main__":
    main()
