extends Node
## 左上角任务入口观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/tracker_shot.tscn --quit-after 9000
## 出图：tests/tracker_shots/01_with_quests.png（有 2 段任务，角标+光晕）
##       02_all_done.png（全部做完，角标光晕消失）
## 同时把左上角放大 4× 存 01_zoom.png 便于核对像素。

const DIR := "res://tests/tracker_shots/"

var scene: Node


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	await get_tree().process_frame

	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	QuestLog.reset()
	QuestLog.add("q_supplies", "采购酿酒材料", "")
	QuestLog.add_step("q_supplies", "生姜", 4)
	QuestLog.add_step("q_supplies", "月影莓", 6)
	QuestLog.set_progress("q_supplies", 0, 4)
	QuestLog.add("q_return", "把材料带回酒馆", "")
	QuestLog.add_step("q_return", "回银辉酒馆，和萃歌说话")

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		print("[trshot] 找不到 HUD")
		get_tree().quit(1)
		return
	hud.add_child(QuestTracker.new())
	# 让光晕亮到最亮那一刻再拍，否则抓到的是暗帧
	await _wait(30)
	await _shot("01_with_quests.png")

	QuestLog.complete("q_supplies")
	QuestLog.complete("q_return")
	await _wait(10)
	await _shot("02_all_done.png")

	print("[trshot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# 显示器缩放可能是分数（如 175%）→ 视口按窗口分辨率渲染，图会比 640×384 大。
	# 统一按整数倍缩回设计像素，出图尺寸才稳定（也才看得出像素细节）。
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
