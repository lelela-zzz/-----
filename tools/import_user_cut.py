#!/usr/bin/env python3
"""把用户人工精修的整张抠图（白底、按原布局）切回 20+N 件精灵并更新 props.json。

流程：
  1. 连通域 + 质心最小二乘拟合 用户图 -> 2x 导出坐标 的缩放/偏移
  2. 对每个 sprite 条目按 sprite_rect 逆映射回用户图逐像素中心采样：
     近白(>=238) -> 透明，其余 -> 不透明（用户擦掉的部分即 alpha 挖除）
  3. clips 硬裁剪仍然生效（酒馆 y649 / 蓝顶屋 y661 / 摊位截断）
  4. 原为纯碰撞的条目（w_trough/w_crates/w_wheel/w_flower_well）若用户图里有
     干净像素，则提升为遮挡精灵（sort_y = rect 底边，collision 不变）
  5. 用新 alpha 从 dawn/dusk/night 帧重派生时段贴图；props.json 原位更新

注意：本脚本是「用户精修版」的入口；重跑 cut_village_props.py 会用算法掩膜
覆盖精修结果——覆盖后必须再跑一次本脚本。

用法：python tools/import_user_cut.py [用户图路径]
产物：assets/village/v1/objects/*.png + props.json + exports/user_cut_preview.png
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from cut_village_props import FRAMES, OBJECTS  # noqa: E402

OBJ_DIR = ROOT / "assets/village/v1/objects"
DEFAULT_SRC = Path(r"C:/Users/了了啦/Desktop/新建文件夹/城镇抠图中.png")
WHITE_T = 238          # r/g/b 全 >= 此值视为被擦除的白底
DS = 4                 # 连通域检测降采样
MIN_COMP = 300         # 1/4 尺度下最小连通域面积
EXTRA_ADOPT = ["w_trough", "w_crates", "w_wheel"]


def fit_transform(user: Image.Image) -> tuple[float, float, float]:
    """返回 (s, ox, oy)：user_px = s * export2x_px + o。"""
    gray = user.convert("L")
    mask = gray.point(lambda v: 255 if v < 235 else 0)
    small = mask.resize((user.width // DS, user.height // DS), Image.NEAREST)
    sw, sh = small.size
    sp = small.load()
    seen = [[False] * sh for _ in range(sw)]
    comps: list[dict] = []
    for sy in range(sh):
        for sx in range(sw):
            if sp[sx, sy] and not seen[sx][sy]:
                stack = [(sx, sy)]
                seen[sx][sy] = True
                n = 0
                x0 = x1 = sx
                y0 = y1 = sy
                while stack:
                    x, y = stack.pop()
                    n += 1
                    x0, x1 = min(x0, x), max(x1, x)
                    y0, y1 = min(y0, y), max(y1, y)
                    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                        if 0 <= nx < sw and 0 <= ny < sh and sp[nx, ny] \
                                and not seen[nx][ny]:
                            seen[nx][ny] = True
                            stack.append((nx, ny))
                if n >= MIN_COMP:
                    comps.append(((x0 + x1) / 2 * DS, (y0 + y1) / 2 * DS))

    props = json.loads((OBJ_DIR / "props.json").read_text(encoding="utf-8"))["props"]
    cents: list[tuple[str, tuple[float, float]]] = []
    for p in props:
        if not p.get("has_sprite"):
            continue
        im = Image.open(OBJ_DIR / (p["name"] + ".png"))
        a = im.getchannel("A")
        rect = p["sprite_rect"]
        sx = sy = n = 0
        for y in range(im.height):
            for x in range(im.width):
                if a.getpixel((x, y)) > 0:
                    sx += x
                    sy += y
                    n += 1
        if n:
            cents.append((p["name"], ((rect[0] + sx / n) * 2, (rect[1] + sy / n) * 2)))

    s, ox, oy = user.width / 1732.0, 0.0, 0.0
    for _ in range(3):
        n = 0
        sx = sy = ux = uy = 0.0
        sxx = syy = sux = suy = 0.0
        for name, c in cents:
            px_, py_ = s * c[0] + ox, s * c[1] + oy
            best = min(comps, key=lambda q: (q[0] - px_) ** 2 + (q[1] - py_) ** 2)
            if (best[0] - px_) ** 2 + (best[1] - py_) ** 2 > 60 ** 2:
                continue
            n += 1
            sx += c[0]
            sy += c[1]
            ux += best[0]
            uy += best[1]
            sxx += c[0] * c[0]
            syy += c[1] * c[1]
            sux += c[0] * best[0]
            suy += c[1] * best[1]
        if n < 5:
            break
        s = (sux + suy) / (sxx + syy)
        ox = (ux - s * sx) / n
        oy = (uy - s * sy) / n
    print(f"变换拟合: s={s:.5f} ox={ox:.1f} oy={oy:.1f}（配对 {n} 件）")
    return s, ox, oy


def extract(user: Image.Image, rect: list[int],
            s: float, ox: float, oy: float) -> Image.Image:
    """按 1x rect 从用户图切一件：近白 -> alpha 0。"""
    x, y, w, h = rect
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    upx = user.load()
    opx = out.load()
    uw, uh = user.size
    for py in range(h):
        uy = int(oy + (y + py + 0.5) * 2 * s)
        uy = max(0, min(uh - 1, uy))
        for px in range(w):
            ux = int(ox + (x + px + 0.5) * 2 * s)
            ux = max(0, min(uw - 1, ux))
            r, g, b = upx[ux, uy]
            if r >= WHITE_T and g >= WHITE_T and b >= WHITE_T:
                continue
            opx[px, py] = (r, g, b, 255)
    return out


def apply_clips(entry: dict, rect: list[int], im: Image.Image) -> Image.Image:
    """clips = 保留交集（与 cut_village_props 同语义）：clip 矩形之外全透明。"""
    if not entry.get("clips"):
        return im
    keep = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(keep)
    for kind, geo in entry.get("clips", []):
        x, y, w, h = geo
        d.rectangle((x - rect[0], y - rect[1], x - rect[0] + w - 1,
                     y - rect[1] + h - 1), fill=255)
    a = im.getchannel("A")
    from PIL import ImageChops
    im.putalpha(ImageChops.multiply(a, keep))
    return im


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    user = Image.open(src).convert("RGB")
    s, ox, oy = fit_transform(user)
    frames = {k: Image.open(v).convert("RGB") for k, v in FRAMES.items()}

    props = json.loads((OBJ_DIR / "props.json").read_text(encoding="utf-8"))
    by_name = {p["name"]: p for p in props["props"]}
    report: list[str] = []

    for entry in OBJECTS:
        name = entry["name"]
        p = by_name.get(name)
        if p is None:
            continue
        # 待切矩形：已有精灵用 sprite_rect；提升件用 collision_rect
        if p.get("has_sprite"):
            rect = list(p["sprite_rect"])
            was_sprite = True
        elif name in EXTRA_ADOPT:
            rect = list(entry["collision"])
            was_sprite = False
            p["has_sprite"] = True
            p["sprite_rect"] = rect
            p["sort_y"] = rect[1] + rect[3] - 1
            p["file"] = f"res://assets/village/v1/objects/{name}.png"
            report.append(f"[提升] {name}: 纯碰撞 -> 遮挡件 sort_y={p['sort_y']}")
        else:
            continue
        im = extract(user, rect, s, ox, oy)
        im = apply_clips(entry, rect, im)
        alpha_area = sum(1 for a_ in im.getchannel("A").getdata() if a_ > 0)
        if alpha_area < 40:
            report.append(f"[跳过] {name}: 用户图此区域已擦空，保留旧图")
            if not was_sprite:
                p["has_sprite"] = False
                for k in ("file", "sprite_rect", "sort_y"):
                    p.pop(k, None)
            continue
        im.save(OBJ_DIR / f"{name}.png")
        alpha = im.getchannel("A")
        for phase, frame in frames.items():
            color = frame.crop((rect[0], rect[1],
                                rect[0] + rect[2], rect[1] + rect[3])).convert("RGBA")
            color.putalpha(alpha)
            color.save(OBJ_DIR / f"{name}_{phase}.png")
        cover = alpha_area / (rect[2] * rect[3])
        report.append(f"[切件] {name}: 不透明 {alpha_area}px（rect 覆盖率 {cover:.0%}）")

    # 新增：井南花坛（用户图里有、原表没有的件）——追加到表尾
    if "w_flower_well" not in by_name:
        entry = dict(name="w_flower_well", label="花坛·井南",
                     shapes=[("rect", (407, 497, 64, 46))],
                     collision=(407, 497, 64, 46))
        OBJECTS.append(entry)
        rect = [407, 497, 64, 46]
        im = extract(user, rect, s, ox, oy)
        im.save(OBJ_DIR / "w_flower_well.png")
        alpha = im.getchannel("A")
        for phase, frame in frames.items():
            color = frame.crop((rect[0], rect[1], rect[0] + rect[2],
                                rect[1] + rect[3])).convert("RGBA")
            color.putalpha(alpha)
            color.save(OBJ_DIR / f"w_flower_well_{phase}.png")
        props["props"].append(dict(
            name="w_flower_well", label="花坛·井南", has_sprite=True,
            collision_rect=[407, 497, 64, 46],
            file="res://assets/village/v1/objects/w_flower_well.png",
            sprite_rect=rect, sort_y=542))
        report.append(f"[新增] w_flower_well: 花坛·井南 rect={rect}")

    (OBJ_DIR / "props.json").write_text(
        json.dumps(props, ensure_ascii=False, indent=1), encoding="utf-8")

    # 结果预览：最终 objects 目录按 rect 合成
    day = Image.open(ROOT / "assets/village/v1/scene_day_1x.png").convert("RGBA")
    prev = Image.new("RGBA", day.size, (24, 26, 32, 255))
    for p in props["props"]:
        if not p.get("has_sprite"):
            continue
        sp = Image.open(OBJ_DIR / (p["name"] + ".png"))
        prev.alpha_composite(sp, tuple(p["sprite_rect"])[:2])
    out = ROOT / "exports/user_cut_preview.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    prev.resize((prev.width * 2, prev.height * 2), Image.NEAREST).save(out)

    print("\n".join(report))
    print(f"预览 -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
