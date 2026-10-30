extends Node
## 时钟回归：ClockHUD 必须能从 `game_clock` 组认领当前时钟，
## 时间变化后（时针 + 下方数字）都要跟着更新，不能卡在初始值。
##   "<godot.exe>" --headless --path . --quit-after 9000 res://tests/verify_clock.tscn

var _pass := 0
var _fail := 0


func _ready() -> void:
	TestView.logic_resolution()
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	await get_tree().process_frame

	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	var clock: Node = scene.get_node_or_null("Clock")
	var hud: Node = scene.get_node_or_null("HUD/UIRoot/ClockPanel")
	var digits: Label = scene.get_node_or_null("HUD/UIRoot/ClockPanel/Digits") as Label
	if clock == null or hud == null or digits == null:
		_report("场景结构完整（Clock / ClockPanel / Digits）", false,
				"clock=%s hud=%s digits=%s" % [clock != null, hud != null, digits != null])
		_finish()
		return

	# 1) 时钟信号已连上：初始应是 start_hour(7:30) → 数字 07
	_report("初始数字为 07（时钟已认领）", digits.text == "07", "digits=%s" % digits.text)

	# 2) 改时间后数字跟随
	clock.set_time(14, 30)
	await get_tree().process_frame
	await get_tree().process_frame
	_report("改为 14:30 后数字变 14", digits.text == "14", "digits=%s" % digits.text)

	# 3) 跨整点也跟随
	clock.set_time(23, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_report("改为 23:00 后数字变 23", digits.text == "23", "digits=%s" % digits.text)

	# 4) ClockHUD 确实订阅了 time_changed（不只靠初始 _on_time_changed 硬设）
	var connected := false
	for c in clock.time_changed.get_connections():
		if c.callable.get_object() == hud:
			connected = true
			break
	_report("ClockHUD 已连接 time_changed 信号", connected, "connections=%d" % clock.time_changed.get_connections().size())

	_finish()


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s" % name)
	else:
		_fail += 1
		print("[check] FAIL  %s  (%s)" % [name, detail])


func _finish() -> void:
	print("PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
