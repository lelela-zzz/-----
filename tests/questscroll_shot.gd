extends Node
## 任务清单面板【滚动】观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/questscroll_shot.tscn --quit-after 9000
## 摆 8 段任务（必超出框高 → 出现竖向滚动条），截：
##   01_scroll_top.png  —— 滚到最顶（第一段在最上）
##   02_scroll_mid.png  —— 滚到中段（验证滚轮/拖动能翻看下面的任务）

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
		["采购酿酒材料", "凯瑟琳的摊位就在集市南边。", ["生姜", "月影莓", "大麦", "薄荷草"]],
		["把材料带回酒馆", "萃歌在店里等着开锅。", ["回银辉酒馆", "和萃歌说话"]],
		["试试魔法酿造机", "锅子看着比想象的复杂。", ["酿一瓶暖身姜酒"]],
		["招待第一批客人", "酒馆刚开张，来尝鲜的人不少。", ["露西的姜酒", "西蒙的麦酒"]],
		["打听雪山的消息", "过冬的物资还得从山里来。", ["找佐佐木", "问物流"]],
		["整理地窖存货", "地窖里还压着去年的几桶。", ["清点酒桶", "擦拭瓶身"]],
		["修复招牌灯", "门口那盏灯昨晚被风吹歪了。", ["买灯油", "爬梯子上紧螺丝"]],
	]
	for i: int in specs.size():
		var s: Array = specs[i]
		QuestLog.add("q%d" % i, s[0], s[1])
		for st: String in s[2]:
			QuestLog.add_step("q%d" % i, st)

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		print("[qscroll] 找不到 HUD")
		get_tree().quit(1)
		return
	var panel: Node = (load("res://scenes/ui/quest_panel.tscn") as PackedScene).instantiate()
	hud.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	await _shot("01_scroll_top.png", panel)
	# 滚到中段验证"内容翻得动"
	var sc: ScrollContainer = _find_scroll(panel)
	if sc != null:
		sc.scroll_vertical = 240.0
		await get_tree().process_frame
		await get_tree().process_frame
	await _shot("02_scroll_mid.png", panel)

	print("[qscroll] done scroll_v=%s" % (sc.scroll_vertical if sc != null else -1))
	get_tree().quit()


func _find_scroll(p: Node) -> ScrollContainer:
	if p is ScrollContainer:
		return p as ScrollContainer
	for c: Node in p.get_children():
		var r: ScrollContainer = _find_scroll(c)
		if r != null:
			return r
	return null


func _shot(file_name: String, _panel: Node) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
