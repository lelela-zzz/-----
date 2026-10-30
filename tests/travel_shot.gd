extends Node
## 「跑路中」遮罩观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/travel_shot.tscn --quit-after 9000
## 从 08:40 跑 25 分钟：
##   01_running_mid.png —— 指针转到中途
##   02_running_end.png —— 快到 09:05

const DIR := "res://tests/travel_shots/"

var scene: Node


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	await get_tree().process_frame

	await _mount("res://scenes/world.tscn")
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock != null:
		clock.set_time(8, 40)

	var hud: Node = scene.get_node_or_null("HUD/UIRoot")
	if hud == null:
		print("[travel_shot] 找不到 HUD/UIRoot")
		get_tree().quit(1)
		return
	var ov: TravelOverlay = TravelOverlay.new()
	hud.add_child(ov)
	# target_path 传空 = 只走时间不切场景（截图用）
	ov.begin(clock, 8, 40, 25, "", Vector2(240, 788))

	await get_tree().create_timer(0.45).timeout
	await _shot("01_running_mid.png")
	await get_tree().create_timer(0.60).timeout
	await _shot("02_running_end.png")

	print("[travel_shot] clock=%s" % (clock.get_time_string() if clock != null else "?"))
	get_tree().quit()


func _mount(path: String) -> Node:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		scene = null
		await get_tree().process_frame
	scene = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame
	return scene


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
