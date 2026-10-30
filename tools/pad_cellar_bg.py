"""把地窖底图右侧补 22px 暗边，铺到地图右缘。

背景：地窖底图为了对齐楼梯中线，整体左移了 22px（offset.x = -22），
于是它只覆盖 world x ∈ [-22, 618]，地图右边 618..640 这 22px 会露出
纯黑（0,0,0）的透明区，和底图自身的暗边框（约 28,26,29）对不上，
在酒馆上方形成一条扎眼的黑竖带。

做法：把最右边一列像素复制 22 列补上去（那一列本身就是暗边框，
纯色、无细节），补完宽度 662 = 640 + 22，正好贴到 world x = 640。

用法：
    python tools/pad_cellar_bg.py
"""

from pathlib import Path

from PIL import Image

SRC = Path("assets/cellar/v1/scene_night_1x.png")
DST = Path("assets/cellar/v1/scene_night_pad.png")
PAD = 22


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    out = Image.new("RGBA", (w + PAD, h), (0, 0, 0, 0))
    out.paste(im, (0, 0))

    edge = im.crop((w - 1, 0, w, h))
    for i in range(PAD):
        out.paste(edge, (w + i, 0))

    out.save(DST)
    print(f"{SRC} {w}x{h} -> {DST} {out.size[0]}x{out.size[1]}（右侧补 {PAD}px）")


if __name__ == "__main__":
    main()
