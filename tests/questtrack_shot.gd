extends Node
## 任务清单面板【追踪】观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/questtrack_shot.tscn --quit-after 9000
## 摆几段任务、把中间一段设为追踪，截：
##   01_track_on.png  —— 被追踪段：标题加 ★、染金色、整段浅色高亮，按钮变「取消追踪」

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
	var specs: Array = [
		["去集市进一批酿酒材料", "开张头一天，材料得备足。", ["走出酒馆", "找凯瑟琳搭话"]],
		["采购酿酒材料", "凯瑟琳的摊位就在集市南边。", ["生姜", "月影莓", "大麦"]],
		["把材料带回酒馆", "萃歌在店里等着开锅。", ["回银辉酒馆", "和萃歌说话"]],
		["试试魔法酿造机", "锅子看着比想象的复杂。", ["酿一瓶暖身姜酒"]],
	]
	for i: int in specs.size():
		var s: Array = specs[i]
		QuestLog.add("q%d" % i, s[0], s[1])
		for st: String in s[2]:
			QuestLog.add_step("q%d" % i, st)
	# 把中间一段（采购酿酒材料）设为追踪，验证高亮 + 金色 ★ + 按钮切换
	QuestLog.set_tracked("q1")

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		print("[qtrack] 找不到 HUD")
		get_tree().quit(1)
		return
	var panel: Node = (load("res://scenes/ui/quest_panel.tscn") as PackedScene).instantiate()
	hud.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	await _shot("01_track_on.png", panel)
	print("[qtrack] tracked=%s" % QuestLog.tracked_id())
	get_tree().quit()


func _shot(file_name: String, _panel: Node) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
