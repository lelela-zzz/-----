"""彻底清掉坐姿行的占位稿矩形。

占位稿 = 坐姿行第 0 格（正面）和第 3 格（背面），里面有：
  - y≈69..90 一整块带深色描边的实心浅色矩形（52x22）
  - y≈93..119 两条 16px 宽的方块腿
这是当初"先占位后面再补"留下的，正式美术（侧面两格）到位后就不该再存在。

做法：col0 <- col2（朝右侧面），col3 <- col1（朝左侧面）。
这样坐姿行 4 格全是真侧面，任何代码路径（哪怕误取 frame 0/3）都不会再显示矩形。
备份 .norect.bak。
"""
from PIL import Image
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NPC = os.path.join(ROOT, "assets", "actors", "npc")
NAMES = ["雪山探险家_哈特菲利亚", "矿工少年_西蒙", "矮人战士_爱德华", "集市管理员_凯瑟琳"]

for name in NAMES:
    p = os.path.join(NPC, name + ".png")
    bak = p + ".norect.bak"
    if not os.path.exists(bak):
        shutil.copy2(p, bak)
    sheet = Image.open(p).convert("RGBA")
    if sheet.height < 600:
        print("跳过（无坐姿行）:", name, sheet.size)
        continue
    col1 = sheet.crop((60, 480, 120, 600))    # 朝左
    col2 = sheet.crop((120, 480, 180, 600))   # 朝右
    sheet.paste(col2, (0, 480))               # col0 <- 朝右
    sheet.paste(col1, (180, 480))             # col3 <- 朝左
    sheet.save(p)
    print("已清理:", name, sheet.size)

print("done")
