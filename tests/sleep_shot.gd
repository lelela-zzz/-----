extends Node
## 「睡觉中」过场观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/sleep_shot.tscn --quit-after 9000
## 走真实回店链路（set_time 23:00 → 旁白 → 过场 → 跨天）：
##   01_narration.png —— 回店旁白「累了一天了，早点休息吧」
##   02_black.png     —— 过场：全黑背景 + 字/床/钟
##   03_late.png      —— 指针转到后半段
##   04_wake.png      —— 醒来，白天场景

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

	# 序章卡片常开会挡过场（它是 modal），测试环境直接请走
	var ui: Node = scene.get_node_or_null("HUD/UIRoot")
	for c: Node in (ui.get_children() if ui != null else []):
		if c is PrologueCard:
			(c as PrologueCard).queue_free()
	await get_tree().process_frame

	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock == null:
		print("[sleep_shot] 找不到 GameClock")
		get_tree().quit(1)
		return
	GameClock.reset_day(1)
	clock.running = false
	print("[sleep_shot] before: day=%d %s" % [clock.day, clock.get_time_string()])

	# 真实链路：回店落位 → set_time(23,0) → 旁白 → 过场 → 跨天
	clock.set_time(23, 0)

	await get_tree().create_timer(0.8).timeout
	await _shot("01_narration.png")
	await get_tree().create_timer(GameClock.NARRATION_SEC - 0.8 + 0.5).timeout
	await _shot("02_black.png")
	await get_tree().create_timer(1.4).timeout
	await _shot("03_late.png")

	await get_tree().create_timer(SleepOverlay.FADE_OUT_SEC + 0.7).timeout
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
