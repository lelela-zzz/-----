#!/usr/bin/env python3
"""物品图标自检：图与数据对不对得上、尺寸合不合规格。

为什么要有这一步：
  酿酒面板把图标按 1/2 或 1/4 整除缩放贴到 32px 格子里（Nearest 采样）。
  边长不是 32 的整数倍、或者不是正方形，缩下来就会糊、会偏。
  这类问题在 Godot 里不报错，只会"看着有点脏"，很难在验收里抓到 ——
  所以放到提交前跑一遍。

检查三件事：
  1. **缺图**：data/items.json 登记了，但 assets/items/ 下没有这张 PNG。
  2. **未登记**：assets/items/ 下有 PNG，但 items.json 里没有对应 id。
  3. **规格**：正方形、边长是 32 的整数倍、有透明通道。

用法：
  python tools/check_item_art.py            # 只检查，列表面
  python tools/check_item_art.py --fix      # 顺手把不合规的图裁边+补成方形
  （--fix 会覆盖原图，动手前请先备份；本项目 item_backup_*/ 就是干这个的）
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "items.json"
DIRS = {
    "ingredient": ROOT / "assets" / "items" / "icons",
    "wine": ROOT / "assets" / "items" / "wines",
}
GRID = 32
TARGET = 64


def load_items() -> list[dict]:
    with open(DATA, encoding="utf-8") as f:
        return json.load(f)["items"]


def check_one(path: Path) -> tuple[bool, str]:
    im = Image.open(path)
    w, h = im.size
    if im.mode != "RGBA":
        return False, f"mode={im.mode}（应为 RGBA）"
    if w != h:
        return False, f"{w}x{h} 不是正方形"
    if w % GRID != 0:
        return False, f"{w}x{h} 边长不是 {GRID} 的整数倍"
    return True, f"{w}x{h}"


def normalize(path: Path) -> str:
    """裁到不透明包围盒，再居中补成 TARGET 见方的透明底。"""
    im = Image.open(path).convert("RGBA")
    box = im.getchannel("A").getbbox()
    if box is None:
        return "全透明，跳过"
    im = im.crop(box)
    side = max(im.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    if side > TARGET:
        canvas = canvas.resize((TARGET, TARGET), Image.NEAREST)
    canvas.save(path)
    return f"已裁边补方 → {canvas.size[0]}x{canvas.size[1]}"


def main() -> int:
    fix = "--fix" in sys.argv
    items = load_items()
    problems = 0

    print(f"{'id':26s} {'种类':10s} {'文件':22s} 规格")
    print("-" * 78)
    seen: set[Path] = set()
    for it in items:
        kind = it.get("kind", "?")
        icon = Path(it.get("icon", "").replace("res://", ""))
        path = ROOT / icon
        name = Path(icon).name
        if not path.exists():
            print(f"{it['id']:26s} {kind:10s} {name:22s} ✗ 缺图")
            problems += 1
            continue
        seen.add(path)
        ok, detail = check_one(path)
        if not ok and fix:
            detail = normalize(path)
            ok, _ = check_one(path)
        print(f"{it['id']:26s} {kind:10s} {name:22s} {'✓' if ok else '✗'} {detail}")
        if not ok:
            problems += 1

    # 反向：目录里有图但数据没登记
    # 注意：assets/items/icons/ 也放任务道具之类的东西（quest_notebook.png），
    # 它由脚本里的常量引用，所以"已登记"的判定要看 json + gd + tscn 的全部文本。
    patterns = ["data/*.json", "scripts/**/*.gd", "scenes/**/*.tscn", "scenes/*.tscn"]
    blob = ""
    for pat in patterns:
        for f in ROOT.glob(pat):
            blob += f.read_text(encoding="utf-8", errors="ignore")
    print("-" * 78)
    for kind, folder in DIRS.items():
        if not folder.exists():
            continue
        for p in sorted(folder.glob("*.png")):
            if p in seen:
                continue
            if p.name in blob:
                print(f"{'(他处登记)':26s} {kind:10s} {p.name:22s} · 不在 items.json，别的数据在用")
                continue
            print(f"{'(未登记)':26s} {kind:10s} {p.name:22s} ✗ 任何 json 都没引用")
            problems += 1

    print("-" * 78)
    print(f"共 {len(items)} 条物品。问题 {problems} 个。" + ("" if problems == 0 else " ← 见上面 ✗"))
    return 0 if problems == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
