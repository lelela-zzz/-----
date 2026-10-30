"""裁出反馈截图底部文字条 + 顶部区域，放大以便读字。"""
from PIL import Image

im = Image.open("tests/rect_feedback.png").convert("RGB")
w, h = im.size
bot = im.crop((0, h - 90, w, h))
bot.resize((bot.width * 6, bot.height * 6), Image.NEAREST).save("tests/rect_bottom_6x.png")
top = im.crop((0, 0, w, 120))
top.resize((top.width * 6, top.height * 6), Image.NEAREST).save("tests/rect_top_6x.png")
print("ok", w, h)
