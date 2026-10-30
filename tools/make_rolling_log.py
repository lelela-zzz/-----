"""竖立滚木 prop 后处理：品红抠图 -> 严格 2:1 定形 -> 32x64 像素化 -> 项目色板量化。

用法: python tools/make_rolling_log.py
输出: assets/props/rolling_log/v1/rolling_log_1x.png (32x64)
      assets/props/rolling_log/v1/rolling_log_2x.png (64x128 = NEAREST x2)
      assets/props/rolling_log/v1/rolling_log_4x_preview.png
      exports/rolling_log_preview.png (规格校验用接触表)
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets/props/rolling_log/v1/raw/A_single_upright_wooden_log_st_2026-10-23T10-31-27.png")
OUT = os.path.join(ROOT, "assets/props/rolling_log/v1")

TARGET_W, TARGET_H = 32, 64            # 1x，严格 2:1
PAD_X, PAD_TOP, PAD_BOTTOM = 1, 2, 2   # 主体绘制区 30x60

# 项目色板 v4：木三阶 + 结构 + 草苔点缀（8 色，足够 32x64 道具）
PALETTE = [
    ("outline",      (0x18, 0x18, 0x18)),
    ("aged-shadow",  (0x20, 0x20, 0x18)),
    ("crevice",      (0x3A, 0x2A, 0x22)),
    ("wood-dark",    (0x50, 0x38, 0x18)),
    ("wood-mid",     (0x78, 0x50, 0x28)),
    ("wood-light",   (0x90, 0x68, 0x38)),
    ("straw",        (0xBF, 0xA1, 0x6C)),
    ("moss",         (0x49, 0x5A, 0x37)),
]


def is_bg(p):
    r, g, b = p[:3]
    return (r - g) > 70 and (b - g) > 50 and r > 110


def key_out(img):
    """品红底 -> 透明；右下角水印区强制清空。"""
    img = img.convert("RGB")
    w, h = img.size
    px = img.load()
    wm_x, wm_y = int(w * 0.82), int(h * 0.86)   # 水印屏蔽矩形起点
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if x >= wm_x and y >= wm_y:
                continue
            p = px[x, y]
            if not is_bg(p):
                op[x, y] = (p[0], p[1], p[2], 255)
    return out


def content_bbox(img):
    a = img.getchannel("A")
    return a.getbbox()


def nearest_palette(rgb):
    best, bd = None, 1e9
    r, g, b = rgb
    for name, (pr, pg, pb) in PALETTE:
        d = 2 * (r - pr) ** 2 + 4 * (g - pg) ** 2 + 3 * (b - pb) ** 2
        if d < bd:
            bd, best = d, (pr, pg, pb)
    return best


def quantize(img):
    """RGBA -> 8 色量化，alpha 二值化。"""
    img = img.convert("RGBA")
    px = list(img.getdata())
    out = []
    for r, g, b, a in px:
        if a < 128:
            out.append((0, 0, 0, 0))
        else:
            qr, qg, qb = nearest_palette((r, g, b))
            out.append((qr, qg, qb, 255))
    res = Image.new("RGBA", img.size, (0, 0, 0, 0))
    res.putdata(out)
    return res


def apply_palette_only(img):
    """只做色板映射（保留 alpha 渐变），用于中间层。"""
    img = img.convert("RGBA")
    px = list(img.getdata())
    out = []
    for r, g, b, a in px:
        if a < 8:
            out.append((0, 0, 0, 0))
        else:
            qr, qg, qb = nearest_palette((r, g, b))
            out.append((qr, qg, qb, a))
    res = Image.new("RGBA", img.size, (0, 0, 0, 0))
    res.putdata(out)
    return res


def lift_top(subject, blend=0.42):
    """只在顶面椭圆内圈提亮年轮：边缘树皮留给暗部，避免轮廓端点冒出亮斑。"""
    img = subject.copy()
    w, h = img.size
    px = img.load()
    tr, tg, tb = PALETTE[6][1]  # straw
    cx, cy = w * 0.5, h * 0.075
    rx, ry = w * 0.34, h * 0.055     # 内圈：外缘 20% 不动，留作暗边
    for y in range(int(h * 0.15)):
        for x in range(w):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 > 1.0:
                continue
            r, g, b, a = px[x, y]
            if a < 200 or r < 110:
                continue
            nr = int(r + (tr - r) * blend)
            ng = int(g + (tg - g) * blend)
            nb = int(b + (tb - b) * blend)
            px[x, y] = (nr, ng, nb, a)
    return img


def build():
    src = Image.open(RAW)
    keyed = key_out(src)
    bb = content_bbox(keyed)
    subject = lift_top(keyed.crop(bb))
    print("原始尺寸", src.size, "主体 bbox", bb, "主体宽高比 %.2f" % (subject.size[0] and subject.size[1] / subject.size[0]))

    box_w = TARGET_W - PAD_X * 2
    box_h = TARGET_H - PAD_TOP - PAD_BOTTOM

    # 一次性 BOX 降到 1x（2 像素级细节靠平均保住色调，量化后归到色板）
    small = subject.resize((box_w, box_h), Image.BOX)
    small_q = quantize(small)

    canvas = Image.new("RGBA", (TARGET_W, TARGET_H), (0, 0, 0, 0))
    canvas.paste(small_q, (PAD_X, PAD_TOP), small_q)

    # 两段式备选：先 2x 量化再降采样，边缘更"块"
    mid = subject.resize((box_w * 2, box_h * 2), Image.BOX)
    mid_q = apply_palette_only(mid)
    alt = quantize(mid_q.resize((box_w, box_h), Image.BOX))
    canvas_alt = Image.new("RGBA", (TARGET_W, TARGET_H), (0, 0, 0, 0))
    canvas_alt.paste(alt, (PAD_X, PAD_TOP), alt)

    os.makedirs(OUT, exist_ok=True)
    canvas.save(os.path.join(OUT, "rolling_log_1x.png"))
    canvas.resize((TARGET_W * 2, TARGET_H * 2), Image.NEAREST).save(os.path.join(OUT, "rolling_log_2x.png"))
    canvas.resize((TARGET_W * 4, TARGET_H * 4), Image.NEAREST).save(os.path.join(OUT, "rolling_log_4x_preview.png"))

    outlined = add_outline(canvas)
    outlined.save(os.path.join(OUT, "rolling_log_outline_1x.png"))
    outlined.resize((TARGET_W * 2, TARGET_H * 2), Image.NEAREST).save(
        os.path.join(OUT, "rolling_log_outline_2x.png"))

    canvas_alt = canvas
    keyed.crop(bb).save(os.path.join(OUT, "rolling_log_source_keyed.png"))
    return canvas, outlined


def add_outline(img):
    """外描 1px #181818：降采样会把原始描边吃掉，浅色地面上边界需重新压住。"""
    w, h = img.size
    a = img.getchannel("A").load()
    out = img.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            if a[x, y] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and a[nx, ny] > 0:
                    op[x, y] = (0x18, 0x18, 0x18, 255)
                    break
    return out


def report(img, tag):
    w, h = img.size
    cols = {c for c in img.getdata() if c[3] > 0}
    alphas = {a for (_, _, _, a) in img.getdata()}
    print("[%s] 尺寸 %dx%d  比例1:%.3f  用色 %d  alpha取值 %s"
          % (tag, w, h, h / w, len(cols), sorted(alphas)))


def contact_sheet(plain, outlined):
    """对比图：无描边/有描边 x 深色底/草绿底，4x 展示。"""
    scale = 4
    cw, ch = TARGET_W * scale, TARGET_H * scale
    pad, top = 18, 46
    sheet = Image.new("RGB", (pad + (cw + pad) * 4, top + ch + 40), (30, 30, 30))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 14), "rolling_log  32x64 (ratio 1:2)   4x preview", fill=(235, 235, 235))
    cells = [
        ("no outline / #181818", (24, 24, 24), plain),
        ("1px outline / #181818", (24, 24, 24), outlined),
        ("no outline / #6E7C46", (0x6E, 0x7C, 0x46), plain),
        ("1px outline / #6E7C46", (0x6E, 0x7C, 0x46), outlined),
    ]
    for i, (name, bg, img) in enumerate(cells):
        x0, y0 = pad + i * (cw + pad), top
        panel = Image.new("RGB", (cw, ch), bg)
        big = img.resize((cw, ch), Image.NEAREST)
        panel.paste(big, (0, 0), big)
        sheet.paste(panel, (x0, y0))
        d.text((x0, y0 + ch + 8), name, fill=(205, 205, 205))
    out = os.path.join(ROOT, "exports/rolling_log_preview.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print("接触表 ->", out)


if __name__ == "__main__":
    a, b = build()
    report(a, "无描边")
    report(b, "带描边")
    contact_sheet(a, b)
