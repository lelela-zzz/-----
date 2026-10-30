extends Node
## 时钟指针是否真的会走字：把 GameClock 先后设到 8:00 与 14:00，
## 各截一张钟面区域，再用 Python 检测指针像素的指向角度，对比是否变化。
##   "<godot.exe>" --path . res://tests/clock_shot.tscn --quit-after 9000

const DIR := "res://tests/clock_shots/"

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

	var clock: Node = scene.get_node_or_null("Clock")
	var panel: Node = scene.get_node_or_null("HUD/UIRoot/ClockPanel")
	if clock == null or panel == null:
		print("[clockshot] 找不到 Clock(%s) 或 ClockPanel(%s)" % [clock != null, panel != null])
		get_tree().quit(1)
		return
	print("[clockshot] clock=%s panel=%s" % [clock.get_class(), panel.get_class()])

	# 8:00
	clock.set_time(8, 0)
	await _wait(2)
	await _shot("clock_0800.png", panel)

	# 14:00（相差 180°，指针应指向正下方）
	clock.set_time(14, 0)
	await _wait(2)
	await _shot("clock_1400.png", panel)

	print("[clockshot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _shot(file_name: String, panel: CanvasItem) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# 视口可能因显示分数缩放而变大，按整数倍缩回 640×384 设计像素
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	# 钟面在 ClockPanel 局部 (0..64, 0..80)，转成屏幕像素并裁出
	var r: Rect2 = panel.get_global_rect()
	var x0: int = int(clampf(r.position.x, 0, img.get_width() - 1))
	var y0: int = int(clampf(r.position.y, 0, img.get_height() - 1))
	var w: int = int(clampf(r.size.x, 1, img.get_width() - x0))
	var h: int = int(clampf(r.size.y, 1, img.get_height() - y0))
	var crop: Image = img.get_region(Rect2(x0, y0, w, h))
	crop.save_png(DIR + file_name)
