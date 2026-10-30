extends Node
## 2× 渲染观感图（A 路线）：酒馆白天 / 夜晚 / 设置面板。
##   "<godot.exe>" --path . res://tests/hd_shot.tscn --quit-after 9000
##
## 故意**不**调 TestView.logic_resolution()：这里要看的就是 1280×768 的真实渲染。
## 截图尺寸 = viewport 1280×768（窗口 1920×1152，150%）。

const DIR: String = "res://tests/hd_shots/"

var scene: Node2D


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	WindowScale.set_display_scale(1.5)
	await get_tree().process_frame

	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(30)

	var player: Node2D = scene.get_node("Sorted/Player") as Node2D
	player.global_position = Vector2(320, 200)
	await _wait(10)
	await _shot("01_day.png")

	# 夜晚：看火炉暖光 + 冷环境在 2× 下的层次
	# 注意：Lighting 跟着时钟走，直接 set_phase_instant 会被下一 tick 覆盖，
	# 所以要改时钟本身（memory 里记的那条教训）
	var clock: GameClock = scene.get_node("Clock") as GameClock
	clock.set_time(21, 0)
	# set_time 不发电台号，HUD 要等下一 tick 才跳字 —— 手动刷一次，图面才自洽
	var hud_clock: ClockHUD = scene.get_node("HUD/UIRoot/ClockPanel") as ClockHUD
	hud_clock._on_time_changed(clock.hour, clock.minute)
	await _wait(10)
	await _shot("02_night.png")

	# 设置面板（UI 也是 2× 渲染，字仍然锐利）
	clock.set_time(12, 0)
	await _wait(8)
	_push_key(KEY_F10)
	await _wait(8)
	await _shot("03_settings.png")

	# ---- 村庄（1732² 底图 + 2× 道具）----
	scene.queue_free()
	await _wait(4)
	scene = (load("res://scenes/village.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(24)

	var vplayer: Node2D = scene.get_node("Sorted/Player") as Node2D
	vplayer.global_position = Vector2(430, 500)
	var vcam: Camera2D = scene.get_node("Sorted/Player/Camera") as Camera2D
	vcam.snap_now()
	await _wait(10)
	await _shot("04_village_day.png")

	var vclock: GameClock = scene.get_node("Clock") as GameClock
	vclock.set_time(21, 0)
	var vhud: ClockHUD = scene.get_node("HUD/UIRoot/ClockPanel") as ClockHUD
	vhud._on_time_changed(vclock.hour, vclock.minute)
	await _wait(10)
	await _shot("05_village_night.png")

	vplayer.global_position = Vector2(300, 800)
	vcam.snap_now()
	await _wait(8)
	vclock.set_time(12, 0)
	vhud._on_time_changed(12, 0)
	await _wait(8)
	await _shot("06_village_market.png")

	WindowScale.reset_to_defaults()
	WindowScale.save_settings()
	print("[hdshot] done ", get_viewport().get_texture().get_image().get_size())
	get_tree().quit()


func _push_key(keycode: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_viewport().push_input(down)
	var up: InputEventKey = InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_viewport().push_input(up)


func _wait(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	(get_viewport().get_texture().get_image()).save_png(DIR + name)
