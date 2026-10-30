extends Node
## 任务清单面板（Q）观感截图 —— 窗口模式才能出图（headless 不触发 frame_post_draw）。
##   "<godot.exe>" --path . res://tests/questpanel_shot.tscn --quit-after 9000
## 摆一个"序章中段"的任务状态：一段已做完（应该消失）、两段还在做。

const DIR := "res://tests/quest_shots/"

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
	# ① 整段做完 → 应该从清单里消失
	QuestLog.add("q_market", "去集市进一批酿酒材料", "开张头一天，材料得备足。")
	QuestLog.add_step("q_market", "走出酒馆，前往卢迪克集市")
	QuestLog.add_step("q_market", "和集市管理员凯瑟琳搭上话")
	QuestLog.complete("q_market")

	# ② 还在做：4 个计数步骤，做了 2 个
	QuestLog.add("q_supplies", "采购酿酒材料", "凯瑟琳的摊位就在集市南边，先聊两句再挑货。")
	QuestLog.add_step("q_supplies", "生姜", 4)
	QuestLog.add_step("q_supplies", "月影莓", 6)
	QuestLog.add_step("q_supplies", "大麦", 6)
	QuestLog.add_step("q_supplies", "薄荷草", 4)
	QuestLog.set_progress("q_supplies", 0, 4)
	QuestLog.set_progress("q_supplies", 1, 6)

	# ③ 新的一段，一步没动
	QuestLog.add("q_return", "把材料带回酒馆", "萃歌在店里等着开锅。")
	QuestLog.add_step("q_return", "回银辉酒馆，和萃歌说话")

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		print("[qpshot] 找不到 HUD")
		get_tree().quit(1)
		return
	var panel: Node = (load("res://scenes/ui/quest_panel.tscn") as PackedScene).instantiate()
	hud.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	await RenderingServer.frame_post_draw
	(get_viewport().get_texture().get_image()).save_png(DIR + "01_quest_panel.png")

	# 再做掉一段 → 剩下的自动顶上来（同一面板实例即时刷新）
	QuestLog.complete("q_supplies")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	(get_viewport().get_texture().get_image()).save_png(DIR + "02_after_complete.png")

	print("[qpshot] done")
	get_tree().quit()
