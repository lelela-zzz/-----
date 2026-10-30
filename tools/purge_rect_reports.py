"""删掉所有仍带"占位矩形"的旧诊断/预览图（含 .import），只保留真实游戏截图与不含矩形的对比图。

这些都是本轮为了排查而生成的一次性图，删掉不影响工程；游戏内截图（tests/shots、
tests/prologue_shots）与不含矩形的对比图全部保留。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(ROOT, "tests")

NAMES = [
    # 明确含占位矩形的旧预览/模板
    "before_after_lucy.png",
    "sit_frames_all.png",
    "catherine_side_sit_preview.png",
    "cathsit_full_preview.png",
    "clean_seats_preview.png",
    "gridsit_preview_雪山探险家_哈特菲利亚.png",
    "tpl_sit_full_preview.png",
    "tpl_sit_left.png",
    "tpl_sit_left_x5.png",
    "tpl_sit_right.png",
    "tpl_sit_right_x5.png",
    "sit_preview_集市管理员_凯瑟琳.png",
    "sit_preview_集市管理员_凯瑟琳.png.png",
    "sit_preview_雪山探险家_哈特菲利亚.png",
    "sit_preview_雪山探险家_哈特菲利亚.png.png",
    "sit_preview_矮人战士_爱德华.png",
    "sit_preview_矮人战士_爱德华.png.png",
    "sit_preview_矿工少年_西蒙.png",
    "sit_preview_矿工少年_西蒙.png.png",
    # 本轮一次性排查裁剪
    "hip_16x.png", "hip_catherine.png", "hip_source_lucy.png",
    "rekey_lucy_8x.png", "panel_candidate.png",
    "seat_feedback.png", "seat_feedback_zoom.png",
    "gridsrc_edward.png", "gridsrc_lucy.png",
    "cath_bug.png", "cath_bug_3x.png", "cath_zoom_6x.png",
    "sit_side_zoom.png", "sit_side_zoom_v2.png",
    "rect_feedback.png", "rect_feedback_6x.png", "rect_feedback_chess.png",
    "rect_bottom_6x.png", "rect_top_6x.png",
    "zoomrow_0.png", "zoomrow_1.png", "zoomrow_2.png", "zoomrow_3.png",
]

gone, missing = [], []
for fn in NAMES:
    p = os.path.join(T, fn)
    imp = p + ".import"
    if os.path.exists(p):
        os.remove(p)
        gone.append(fn)
    else:
        missing.append(fn)
    if os.path.exists(imp):
        os.remove(imp)

print("已删除 %d 个（含 .import）" % len(gone))
for g in gone:
    print("   -", g)
print()
print("原本就不存在 %d 个" % len(missing))
