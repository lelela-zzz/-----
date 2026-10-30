"""床贴图后处理：白底转透明 -> 裁到内容 -> 量化到像素网格 -> 输出 1x/2x/预览。

用法：
  python tools/make_bed_sprite.py <src.png> [w1x] [h1x]
默认 1x = 42x72（角色 1x 高 48，床长约 1.5 倍身高）
输出：
  assets/furniture/bed_v1_1x.png   逻辑尺寸贴图（透明底）
  assets/furniture/bed_v1_2x.png   2x（NEAREST 放大）
  assets/furniture/bed_v1_hd.png   高清透明底原图（裁到内容）
  assets/furniture/bed_v1_preview.png  8x 放大 + 棋盘格预览
"""
import sys
import numpy as np
from PIL import Image

WHITE_SUM = 730          # 三通道和超过此值视为白底
BORDER_ALPHA = 250       # 边缘清理阈值


def white_to_alpha(im):
    a = np.array(im.convert("RGB")).astype(np.int16)
    h, w, _ = a.shape
    s = a.sum(2)
    sat = a.max(2) - a.min(2)
    bg = (s >= WHITE_SUM) & (sat < 26)
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    # 去掉被背景包围的孤立白点残留：只保留与内容连通的区块
    out = np.dstack([a.astype(np.uint8), alpha])
    return out


def crop_content(arr):
    al = arr[:, :, 3]
    ys, xs = np.where(al > 0)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    return arr[y0:y1 + 1, x0:x1 + 1]


def defringe(arr):
    """把紧贴透明区的、偏白的边缘像素压暗，避免缩小时出现白边。"""
    rgb = arr[:, :, :3].astype(np.float32)
    al = arr[:, :, 3]
    h, w = al.shape
    whiteish = (rgb.min(2) > 150) & (rgb.max(2) - rgb.min(2) < 40)
    for _ in range(2):
        trans = np.zeros_like(al, dtype=bool)
        trans[1:, :] |= al[:-1, :] == 0
        trans[:-1, :] |= al[1:, :] == 0
        trans[:, 1:] |= al[:, :-1] == 0
        trans[:, :-1] |= al[:, 1:] == 0
        fix = trans & whiteish & (al > 0)
        if not fix.any():
            break
        rgb[fix] = rgb[fix] * 0.55
        whiteish &= ~fix
    arr[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    return arr


def quantize_sprite(hd, w1x, h1x, colors=14):
    """HD 透明图 -> 1x 像素贴图（BOX 降采样后吸附到有限调色板）。"""
    im = Image.fromarray(hd, "RGBA")
    small = im.resize((w1x, h1x), Image.BOX)
    small = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT,
                                          dither=Image.Dither.NONE)
    small = small.convert("RGBA")
    # 恢复 alpha：以原图 alpha 的 BOX 缩小结果为准，>50% 即不透明（像素画二值 alpha）
    a = im.split()[3].resize((w1x, h1x), Image.BOX)
    a = a.point(lambda v: 255 if v > 110 else 0)
    small.putalpha(a)
    return small


def checker_bg(w, h, cell=8):
    yy, xx = np.mgrid[0:h, 0:w]
    c = ((yy // cell + xx // cell) % 2)
    base = np.where(c == 0, 62, 44).astype(np.uint8)
    return Image.fromarray(np.dstack([base, base, base + 4]), "RGB")


def main():
    src = sys.argv[1]
    w1x = int(sys.argv[2]) if len(sys.argv) > 2 else 42
    h1x = int(sys.argv[3]) if len(sys.argv) > 3 else 72
    out = "assets/furniture"

    arr = white_to_alpha(Image.open(src))
    arr = crop_content(arr)
    arr = defringe(arr)
    print("content:", arr.shape[1], "x", arr.shape[0])

    hd = Image.fromarray(arr, "RGBA")
    hd.save(f"{out}/bed_v1_hd.png")
    hd.resize((w1x * 8, h1x * 8), Image.NEAREST).save(f"{out}/bed_v1_8x.png")

    sp = quantize_sprite(arr, w1x, h1x)
    sp.save(f"{out}/bed_v1_1x.png")
    sp.resize((w1x * 2, h1x * 2), Image.NEAREST).save(f"{out}/bed_v1_2x.png")

    prev = checker_bg(w1x * 8 + 32, h1x * 8 + 32)
    big = sp.resize((w1x * 8, h1x * 8), Image.NEAREST)
    prev.paste(big, (16, 16), big)
    prev.save(f"{out}/bed_v1_preview.png")

    print("wrote bed_v1_1x/2x/8x/hd/preview @", out)


if __name__ == "__main__":
    main()
