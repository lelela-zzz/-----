extends Node
## 章节解锁改造的观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/chaptergate_shot.tscn --quit-after 9000
##
##   01_prep_list.png —— 任务栏里的「为雪山之行做准备」：营业额进度 + 还差谁没认识
##   02_day_report.png —— 打烊结算卡（进度行已搬走，卡片变矮）

const DIR := "res://tests/chaptergate_shots/"

var scene: Node


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	QuestLog.reset()
	Regulars.reset()
	await get_tree().process_frame

	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	# 造一个"半途"的状态：营业额 120/300，三个人里认识了一位
	Revenue.total = 120.0
	Regulars.mark_known("broker_chiss")
	Story._ensure_prep("snow_logistics")
	await get_tree().process_frame

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		print("[gate_shot] 找不到 HUD")
		get_tree().quit(1)
		return

	var panel: Node = (load("res://scenes/ui/quest_panel.tscn") as PackedScene).instantiate()
	hud.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("01_prep_list.png")
	print("[gate_shot] prep steps = %s" % _steps())
	panel.queue_free()
	await get_tree().process_frame

	var card: Node = (load("res://scenes/ui/day_report_panel.tscn") as PackedScene).instantiate()
	card.set("report", {"day": 3, "revenue": 128, "wines": 6, "best": 96, "hours": 5})
	hud.add_child(card)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("02_day_report.png")

	Revenue.total = 0.0
	QuestLog.reset()
	Regulars.reset()
	get_tree().quit()


func _steps() -> String:
	var q: Dictionary = QuestLog.quest("prep_snow")
	var out: String = ""
	for s: Variant in (q.get("steps", []) as Array):
		var d: Dictionary = s as Dictionary
		out += "%s(%d/%d)%s " % [str(d["text"]), int(d["got"]), int(d["need"]),
				"✓" if bool(d["done"]) else ""]
	return out


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
