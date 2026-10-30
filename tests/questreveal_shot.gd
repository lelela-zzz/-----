extends Node
## 任务清单【逐步揭示】观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/questreveal_shot.tscn --quit-after 9000
##
## 一次最多露两条（刚做完的 + 正在做的），往后每做完一条，窗口往前滑一格：
##   01_reveal_first.png  —— 三条都没做完：只露第一条
##   02_reveal_second.png —— 做完第一条：它留着转 ✓ 完成态，第二条补进来
##   03_reveal_third.png  —— 再做完一条：第一条滑走，第二条转 ✓，第三条出现

const DIR := "res://tests/quest_shots/"
const PANEL := "res://scenes/ui/quest_panel.tscn"

var scene: Node
var _panel: Node = null


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

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		print("[qreveal] 找不到 HUD")
		get_tree().quit(1)
		return
	_panel = (load(PANEL) as PackedScene).instantiate()
	hud.add_child(_panel)
	await get_tree().process_frame
	await get_tree().process_frame

	await _shot("01_reveal_first.png")
	print("[qreveal] 阶段1 窗口 = %s" % str(_vis()))

	# 做完第一条
	for k: int in 2:
		QuestLog.set_step_done("q0", k, true)
	await get_tree().process_frame
	await _shot("02_reveal_second.png")
	print("[qreveal] 阶段2 窗口 = %s" % str(_vis()))

	# 再做完第二条
	for k: int in 3:
		QuestLog.set_step_done("q1", k, true)
	await get_tree().process_frame
	await _shot("03_reveal_third.png")
	print("[qreveal] 阶段3 窗口 = %s" % str(_vis()))

	get_tree().quit()


func _vis() -> Array[String]:
	var out: Array[String] = []
	for q: Dictionary in QuestLog.visible():
		out.append("%s%s" % [str(q["id"]), "(完)" if QuestLog.is_finished(q) else ""])
	return out


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
