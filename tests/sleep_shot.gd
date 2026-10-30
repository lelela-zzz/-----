extends Node
## 「睡觉中」过场观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/sleep_shot.tscn --quit-after 9000
## 从 22:59 触发宵禁跨天，走的是真实链路（GameClock → SleepOverlay）：
##   01_enter.png  —— 淡入，字/床/钟刚出来
##   02_hold.png   —— 停留段，指针转到一半
##   03_late.png   —— 快到淡出，指针转完两圈
## 末尾打印跨天结果（应为第 2 天 07:30）。

const DIR := "res://tests/sleep_shots/"

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
	await get_tree().process_frame

	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock == null:
		print("[sleep_shot] 找不到 GameClock")
		get_tree().quit(1)
		return
	GameClock.reset_day(1)
	clock.set_time(22, 59)
	clock.running = false
	print("[sleep_shot] before: day=%d %s" % [clock.day, clock.get_time_string()])

	# 真实链路：宵禁跨天 → 会把过场挂到 HUD/UIRoot 上
	clock.call("_roll_over_curfew")

	await get_tree().create_timer(0.36).timeout
	await _shot("01_enter.png")
	await get_tree().create_timer(0.85).timeout
	await _shot("02_hold.png")
	await get_tree().create_timer(0.85).timeout
	await _shot("03_late.png")

	await get_tree().create_timer(0.9).timeout
	print("[sleep_shot] after: day=%d %s" % [clock.day, clock.get_time_string()])
	await _shot("04_wake.png")
	get_tree().quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
