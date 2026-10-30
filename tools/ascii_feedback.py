"""把反馈截图打成 ASCII 色类图，快速判断"矩形"到底是什么。"""
from PIL import Image
from collections import Counter

im = Image.open("tests/rect_feedback.png").convert("RGBA")
w, h = im.size
px = im.load()

print("最常见颜色 TOP12:")
c = Counter()
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a < 20:
            c[("透明",)] += 1
        else:
            c[(r // 16 * 16, g // 16 * 16, b // 16 * 16)] += 1
for k, v in c.most_common(12):
    print("  ", k, v)

print()
print("ASCII 图（每字符=4x8 像素，采样中心点）:")
print("  图例: '.'=透明  '#'=暗  'o'=中灰  'O'=浅灰/白  'C'=彩色  '*'=高亮")
for y in range(0, h, 8):
    row = ""
    for x in range(0, w, 4):
        r, g, b, a = px[x, y]
        if a < 30:
            row += "."
            continue
        mx, mn = max(r, g, b), min(r, g, b)
        sat = 0 if mx == 0 else (mx - mn) / mx
        if sat > 0.28:
            row += "C"
        elif mx < 70:
            row += "#"
        elif mx < 130:
            row += "o"
        elif mx < 200:
            row += "O"
        else:
            row += "*"
    print("%4d %s" % (y, row))
