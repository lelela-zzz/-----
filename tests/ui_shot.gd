extends Node
## 新 UI 的观感取景（营业状态条 / 账簿两页 / 打烊小结）。
##   "<godot.exe>" --path . res://tests/ui_shot.tscn --quit-after 9000
## **必须窗口模式**：headless 下 frame_post_draw 不触发会卡住（项目既有结论）。
## 故意不调 TestView.logic_resolution()：要看的就是 1.5× 的真实渲染。

const DIR: String = "res://tests/ui_shots/"

var scene: Node2D


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = false
	DirAccess.make_dir_recursive_absolute(DIR)
	WindowScale.set_display_scale(1.5)
	await get_tree().process_frame

	# 先设阶段再挂场景：否则序言卡会盖住整屏
	Story.stage = StoryDirector.Stage.OPEN
	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)

	# 摆一点存货，让账簿/状态条看起来是"真在经营"
	Inventory.clear()
	Inventory.earn(240)
	for pair: Array in [["ginger", 6], ["wild_berry", 10], ["barley", 8],
			["white_rice", 6], ["moon_river_spring", 4], ["burnt_malt", 5],
			["snow_spring", 3], ["honey", 4]]:
		Inventory.add(str(pair[0]), int(pair[1]))
	Inventory.add("wine_warm_ginger", 5)
	Inventory.add("wine_river_ale", 3)
	Inventory.add("wine_burnt_ale", 2)

	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock != null:
		clock.set_time(17, 40)
	await _wait(10)

	# 1) 未开张：状态条提示怎么开
	await _shot("01_business_hud_closed.png")

	# 2) 营业中：状态条显示还剩多久打烊 + 今日进账
	Story.open_business()
	await _wait(4)
	Inventory.earn(118)
	await _wait(8)
	await _shot("02_business_hud_open.png")

	# 3) 账簿（累计营业额 / 按酒种累计销售 / 按酒种剩余）
	Revenue.total = 235.0
	Revenue.session_total = 235.0
	Revenue.session_wines = 13
	Revenue.total_wines_by_id = {"wine_warm_ginger": 7, "wine_river_ale": 4, "wine_burnt_ale": 2}
	var ledger: UiPanel = _open("res://scenes/ui/ledger_panel.tscn")
	await _wait(12)
	await _shot("03_ledger.png")
	ledger.close()
	await _wait(6)

	# 5) 打烊小结（report 必须在 add_child 之前塞好 —— _build 在 _ready 里跑）
	var rps: PackedScene = load("res://scenes/ui/day_report_panel.tscn") as PackedScene
	var report: DayReportPanel = rps.instantiate() as DayReportPanel
	report.report = {
		"day": 3, "revenue": 118, "wines": 7, "hours": 4,
		"best": 118, "threshold": 150, "forced": true,
	}
	_ui_root().add_child(report)
	await _wait(14)
	await _shot("05_day_report.png")

	# 6) 离开酒馆：右上角营业状态条应收起（村庄也有 HUD，以前会跟着显示"未开张"）
	var village_scene: Node = (load("res://scenes/village.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(village_scene)
	get_tree().current_scene = village_scene
	scene.queue_free()
	await _wait(24)
	await _shot("06_village_no_status.png")

	print("[ui_shot] done -> %s" % DIR)
	get_tree().quit(0)


func _open(path: String) -> UiPanel:
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return null
	var p: UiPanel = ps.instantiate() as UiPanel
	_ui_root().add_child(p)
	return p


func _ui_root() -> Node:
	return scene.get_node("HUD/UIRoot")


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + name)
	print("  -> ", name)
