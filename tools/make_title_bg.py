#!/usr/bin/env python3
"""标题界面底图：酒馆外观（黄昏）→ 1280×768 夜景竖幅。

**为什么是 1280×768**：这是工程内部渲染尺寸（655 逻辑 640×384 ×2）。
标题界面不跟世界共用 640 逻辑网格（它是"海报"，不是场景），直接用渲染原生
尺寸排版 —— 1 个源像素 = 1 个屏幕像素，字也不用被相机 zoom 拉一遍。

构图（左暗右亮）：建筑放在右半边，左边留出一条 256px 的暗色竖带放标题与菜单。

处理链（全部整数像素操作，不做插值）：
  1. 源图 512² NEAREST ×2 → 1024²（像素 1:1 放大，不产生新色）
  2. 取上部 768 行（保屋顶与立面，裁掉底部石墙）→ 1024×768
  3. 左竖带：把最左 256 列镜像翻过来接在左边（屋檐/立面的边缘能对上，
     比横向拉伸更像"建筑继续往左延伸"），再按 x 从暗到亮做坡度，接缝消失
  4. 黄昏调：整体压暗 + 偏暖，顶部再加一层夜蓝压顶（天色沉下来）
  5. 暖光：门洞、门口两盏壁灯、二楼窗 各加一团高斯暖光（加色）
  6. 暗角：四角压黑，左侧最重（标题压得住）

用法：python tools/make_title_bg.py
产物：assets/title/v1/title_bg_2x.png          1280×768 成品
      tests/probe_shots/title_bg_preview.png   640×384 缩略预览（看构图用）
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/tavern_exterior/v1/scene_dusk_1x.png"
OUT_DIR = ROOT / "assets/title/v1"
OUT = OUT_DIR / "title_bg_2x.png"
PREVIEW = ROOT / "tests/probe_shots/title_bg_preview.png"

W, H = 1280, 768
ART = 1024          # 源图 ×2
PASTE_X = W - ART   # 建筑贴右边（256）
STRIP = PASTE_X     # 左竖带宽度
## 纵向取景：从放大后的 1024 行里从第几行开始截。留住屋顶顶边，但往下多带一点
## 门前的草地与石阶，建筑才不会顶到画框上沿。
CROP_Y = 84

# 暖光源（画布坐标，由源图坐标 ×2 + PASTE_X 换算）
#   源图：门 (256,285)、左壁灯 (208,266)、右壁灯 (378,264)
#        一楼窗 (110,268)/(300,268)、二楼窗 (135,205)/(197,205)/(307,205)
LIGHTS: list[tuple[float, float, float, float]] = [
    (PASTE_X + 2 * 256, 2 * 285, 300.0, 0.20),   # 门洞漏出来的火光（大范围）
    (PASTE_X + 2 * 256, 2 * 288, 90.0, 0.16),    # 门口地面反光（集中）
    (PASTE_X + 2 * 208, 2 * 266, 64.0, 0.30),    # 左壁灯
    (PASTE_X + 2 * 378, 2 * 264, 64.0, 0.30),    # 右壁灯
    (PASTE_X + 2 * 110, 2 * 268, 60.0, 0.20),    # 一楼窗
    (PASTE_X + 2 * 300, 2 * 268, 60.0, 0.20),
    (PASTE_X + 2 * 135, 2 * 205, 58.0, 0.16),    # 二楼窗
    (PASTE_X + 2 * 197, 2 * 205, 58.0, 0.16),
    (PASTE_X + 2 * 307, 2 * 205, 58.0, 0.16),
    (PASTE_X + 2 * 450, 2 * 208, 58.0, 0.14),
]
WARM = np.array([1.00, 0.62, 0.28], dtype=np.float32)


def build() -> Image.Image:
    src = Image.open(SRC).convert("RGB")
    if src.size != (512, 512):
        raise SystemExit(f"源图尺寸变了：{src.size}（预期 512×512）")
    art = src.resize((ART, ART), Image.NEAREST)
    art = art.crop((0, CROP_Y, ART, CROP_Y + H))
    # 光斑坐标是按"不裁剪"算的，裁剪后整体上移
    lights = [(x, y - CROP_Y, r, s) for x, y, r, s in LIGHTS]

    canvas = Image.new("RGB", (W, H), (0, 0, 0))

    # 左竖带：镜像最左 STRIP 列
    left = art.crop((0, 0, STRIP, H)).transpose(Image.FLIP_LEFT_RIGHT)
    canvas.paste(left, (0, 0))
    canvas.paste(art, (PASTE_X, 0))

    img = np.asarray(canvas, dtype=np.float32) / 255.0

    # 左侧压黑：x≤180 只剩 8% 亮度，到 x=520 平滑回到 100%。
    # 镜像出来的"另一半屋檐"因此只是暗处的一点结构，不会跟主建筑抢注意力；
    # 坡度跨过接缝那一列，也就没有硬接缝。文字列（x<500）整条都在暗处。
    xs = np.arange(W, dtype=np.float32)
    t = np.clip((xs - 240.0) / 480.0, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    img *= (0.05 + 0.95 * t)[None, :, None]

    # 黄昏调：压暗 + 提暖（蓝通道压得最狠，红留下）
    img *= np.array([1.00, 0.90, 0.78], dtype=np.float32) * 0.94

    # 夜蓝压顶：上部 280 行从 0.62 渐到 1.0，天光沉下去
    top = np.ones((H, 1, 1), dtype=np.float32)
    ys = np.arange(H, dtype=np.float32)
    fall = np.clip(ys / 280.0, 0.0, 1.0)[:, None, None]
    top = 0.62 + 0.38 * fall
    night_tint = np.array([0.86, 0.90, 1.00], dtype=np.float32)  # 顶部偏冷
    cold = np.clip(1.0 - ys / 280.0, 0.0, 1.0)[:, None, None]
    img *= top
    img *= (1.0 - cold) + cold * night_tint

    # 暖光（加色，高斯衰减）
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    glow = np.zeros((H, W, 1), dtype=np.float32)
    for cx, cy, radius, strength in lights:
        d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / (radius * radius)
        glow += (np.exp(-d2 * 1.6) * strength)[:, :, None]
    img += glow * WARM

    # 暗角：椭圆距离，四角最黑
    nx = (xx - W * 0.62) / (W * 0.70)
    ny = (yy - H * 0.46) / (H * 0.76)
    r = np.sqrt(nx * nx + ny * ny)
    vig = np.clip(1.0 - 0.45 * np.clip(r - 0.55, 0.0, None) / 0.75, 0.0, 1.0)
    img *= vig[:, :, None]

    # 底部压暗，给页脚字留位置
    bottom = np.clip((yy - (H - 190)) / 190.0, 0.0, 1.0)[:, :, None]
    img *= (1.0 - 0.62 * bottom)

    # 顶部压暗：取景把屋顶上沿裁掉了，压一层暗让那道切口读作"处在阴影里"，
    # 而不是"图被切了"
    top_mask = np.clip((150.0 - yy) / 150.0, 0.0, 1.0)[:, :, None]
    img *= (1.0 - 0.42 * top_mask)

    out = Image.fromarray((np.clip(img, 0.0, 1.0) * 255.0).round().astype(np.uint8))
    return out


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    out = build()
    out.save(OUT)
    out.resize((640, 384), Image.LANCZOS).save(PREVIEW)
    print(f"[title] {OUT.relative_to(ROOT)} {out.size[0]}×{out.size[1]}")
    print(f"[title] 预览 {PREVIEW.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
