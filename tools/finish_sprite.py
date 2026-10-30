"""把生成的白底家具图收尾成可用贴图：去白底/水印 -> 裁内容 -> 补贴边 -> 出 hd/512。

用法：
  python tools/finish_sprite.py <src.png> <out_prefix>
例：
  python tools/finish_sprite.py assets/furniture/raw_x.png assets/furniture/bed_iso_v3

输出：
  <prefix>_hd.png   裁好的透明底原尺寸
  <prefix>_512.png  长边缩到 512 的展示版
"""
import sys
import numpy as np
from PIL import Image

# 背景/水印判定：够亮且几乎无彩度（床的米色 #D5C193 sat=66、橄榄绿 sat=40 都安全）
BG_SUM = 640
BG_SAT = 22
PAD = 4


def to_alpha(im):
    a = np.array(im.convert("RGB")).astype(np.int16)
    s = a.sum(2)
    sat = a.max(2) - a.min(2)
    alpha = np.where((s >= BG_SUM) & (sat < BG_SAT), 0, 255).astype(np.uint8)
    return np.dstack([a.astype(np.uint8), alpha])


def crop(arr):
    al = arr[:, :, 3]
    ys, xs = np.where(al > 0)
    return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def fix_touching_edges(arr):
    """物体顶到画布边缘时（生成被裁），对应方向补 PAD 并用边缘像素收口 1px。"""
    h, w, _ = arr.shape
    bands = {"right": 0, "left": 0, "top": 0, "bottom": 0}
    if (arr[:, -1, 3] > 0).any():
        bands["right"] = PAD
    if (arr[:, 0, 3] > 0).any():
        bands["left"] = PAD
    if (arr[0, :, 3] > 0).any():
        bands["top"] = PAD
    if (arr[-1, :, 3] > 0).any():
        bands["bottom"] = PAD
    if not any(bands.values()):
        return arr, {}
    out = np.zeros((h + bands["top"] + bands["bottom"],
                    w + bands["left"] + bands["right"], 4), np.uint8)
    out[bands["top"]:bands["top"] + h, bands["left"]:bands["left"] + w] = arr
    if bands["right"]:
        for y in range(h):
            if arr[y, -1, 3] > 0:
                out[bands["top"] + y, bands["left"] + w] = arr[y, -1]
    if bands["left"]:
        for y in range(h):
            if arr[y, 0, 3] > 0:
                out[bands["top"] + y, bands["left"] - 1] = arr[y, 0]
    if bands["bottom"]:
        for x in range(w):
            if arr[-1, x, 3] > 0:
                out[bands["top"] + h, bands["left"] + x] = arr[-1, x]
    if bands["top"]:
        for x in range(w):
            if arr[0, x, 3] > 0:
                out[bands["top"] - 1, bands["left"] + x] = arr[0, x]
    return out, bands


def main():
    src, prefix = sys.argv[1], sys.argv[2]
    arr = to_alpha(Image.open(src))
    arr = crop(arr)
    arr, bands = fix_touching_edges(arr)
    im = Image.fromarray(arr, "RGBA")
    im.save(f"{prefix}_hd.png")
    r = 512 / max(im.width, im.height)
    im.resize((round(im.width * r), round(im.height * r)), Image.LANCZOS).save(f"{prefix}_512.png")
    print(f"{prefix}_hd.png {im.size}  padded={bands or 'none'}")


if __name__ == "__main__":
    main()
