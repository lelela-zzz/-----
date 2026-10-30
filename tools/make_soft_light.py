"""生成「无边界」的柔光衰减贴图 light_soft_radial.png（给漆黑空间用）。

为什么不用现成的 light_warm_radial_1x.png：
那张贴图是给火炉/烛台用的**小**光斑（128²），alpha 沿半径线性递减、
总共只有 ~10 级台阶。放大 2 倍以上铺到半屏时，问题就露出来了：

  * 线性锥形衰减的斜率恒定，中心没有过渡 -> 看起来像一个"圆盘"，
    圆盘边缘是亮度梯度突变处，于是读成一条清晰的**光圈边界**；
  * 8 位 alpha 在暗部只有几级台阶 -> 一圈一圈的**色带（banding）**。

这里改成"按物理光衰减画、再抖动量化"的做法：

  * 主体用截断高斯 exp(-k·t²)：中心平缓、外圈平滑收尾，
    并减去 t=1 处的值让边缘**严格等于 0**（不会有一圈硬边）；
  * 叠一个极窄的热核 exp(-(t/0.20)²)，让中心有一点"光源本体"的亮；
  * alpha 量化时加 4×4 Bayer 有序抖动，暗部台阶被打散成噪点，
    再经线性过滤就看不到任何环。

用法：python tools/make_soft_light.py
"""

from __future__ import annotations

import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "lighting", "light_soft_radial.png")

SIZE = 512                 # 够大：即使铺到 ~300 逻辑像素半径也不会看出像素格
BODY_K = 3.4               # 高斯主体衰减系数（越大收得越快、越像小光斑）
CORE_W = 0.20              # 热核宽度（占半径比例）
CORE_MIX = 0.30            # 热核权重

# 4x4 Bayer 矩阵，取值 0..15
BAYER4 = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)


def falloff(t: float) -> float:
    """t=0 中心、t=1 边缘；边缘严格为 0。"""
    edge = math.exp(-BODY_K)
    body = (math.exp(-BODY_K * t * t) - edge) / (1.0 - edge)
    core = math.exp(-((t / CORE_W) ** 2))
    a = (1.0 - CORE_MIX) * body + CORE_MIX * core
    return max(0.0, min(1.0, a))


def main() -> None:
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    px = img.load()
    c = (SIZE - 1) / 2.0
    r_max = SIZE / 2.0
    for y in range(SIZE):
        for x in range(SIZE):
            dx = (x - c) / r_max
            dy = (y - c) / r_max
            t = math.hypot(dx, dy)
            if t >= 1.0:
                continue
            a = falloff(t)
            # 有序抖动：把 8 位量化的台阶摊成噪点，暗部不再出现同心环
            d = (BAYER4[y & 3][x & 3] + 0.5) / 16.0 - 0.5
            v = int(round(a * 255.0 + d))
            v = max(0, min(255, v))
            if v == 0:
                continue
            px[x, y] = (255, 255, 255, v)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)

    # 顺便打印一条剖面，方便肉眼核对衰减曲线（逻辑数值，非截图）
    row = [px[x, SIZE // 2][3] for x in range(0, SIZE, SIZE // 16)]
    print("wrote %s (%dx%d)" % (os.path.relpath(OUT, ROOT), SIZE, SIZE))
    print("  alpha@center->edge:", row)


if __name__ == "__main__":
    main()
