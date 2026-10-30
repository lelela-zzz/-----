extends Node
## 酒馆外观场景验收检查器：镜头限位 / 地图边界 / 建筑碰撞 / 遮挡顺序 /
## 门传送往返 / 马路东行去村 / 夜景。
##   "<godot.exe>" res://tests/extshot.tscn    （需要真实渲染，不要 --headless）
## 判定看 [check] 行（PASS/FAIL），结尾有 [extshot] FAIL 计数。
##
## 坐标约定：player.global_position 是脚底；身体中心 = 脚底 + (0, -24)。
## 场景常数（cut_tavern_ext_props.py 同源）：建筑碰撞 (34,0,462,321)，
## sort_y=320；门触发框 x210-250 / y339-351；东路口触发框 x502-512。

const DIR := "res://tests/ext_shots/"

var failures: int = 0


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	Engine.max_fps = 60
	await _wait(12)
	var clock: GameClock = _scene().get_node("Clock") as GameClock
	clock.running = false
	clock.set_time(12, 0)

	await _check_camera_limits()
	await _check_map_bounds()
	await _check_building_wall()
	await _check_occlusion()
	await _check_night()
	await _check_doors()

	print("[extshot] done FAIL=", failures)
	get_tree().quit()


func _check_camera_limits() -> void:
	var camera: PixelCamera = _player().get_node("Camera") as PixelCamera
	_place(Vector2(20.0, 20.0))
	await _wait(4)
	var c1: Vector2 = camera.get_screen_center_position()
	_report("镜头左上限位", c1 == Vector2(256.0, 192.0), "中心 = %s（期望 256,192）" % c1)
	await _shot("01_camera_topleft.png")

	_place(Vector2(500.0, 500.0))
	await _wait(4)
	var c2: Vector2 = camera.get_screen_center_position()
	_report("镜头右下限位", c2 == Vector2(256.0, 320.0), "中心 = %s（期望 256,320）" % c2)
	await _shot("02_camera_bottomright.png")


func _check_map_bounds() -> void:
	_place(Vector2(60.0, 100.0))
	Input.action_press("move_left")
	await _wait(90)
	Input.action_release("move_left")
	await _wait(6)
	var stop_x: float = _player().global_position.x
	_report("地图西界阻挡", absf(stop_x - 9.0) < 2.0, "停在 x = %.1f（期望 ≈9）" % stop_x)
	await _shot("03_map_west_bound.png")


func _check_building_wall() -> void:
	# 从酒馆墙正前方向上顶：碰撞下沿 321 + 脚框 6 → 停 327。
	# x=200：避开门口触发框（210-250）与东厢。
	_place(Vector2(200.0, 500.0))
	Input.action_press("move_up")
	await _wait(120)
	Input.action_release("move_up")
	await _wait(6)
	var stop_y: float = _player().global_position.y
	_report("酒馆外墙阻挡", absf(stop_y - 327.0) < 1.5, "停在 y = %.1f（期望 ≈327）" % stop_y)
	await _shot("04_tavern_wall_stop.png")


func _check_occlusion() -> void:
	# 2026-10-23 晚起玩家换成四方向行走角色（暖色调），旧的「占位块冷灰蓝
	# b>g>r」判色失效 —— 改成「藏人差分」：同一机位拍两张（人在 / 人藏），
	# 采样点颜色不变 = 前景盖住了人；变了 = 人盖在前景上。
	var behind: Array = await _probe(Vector2(387.0, 335.0), -6.0)
	var front: Array = await _probe(Vector2(156.0, 366.0), -24.0)

	# "柱后"：东厢柱基（掩膜 x381-393 / y323-339）是全场景唯一玩家可合法
	# 站到 prop 后面的位置 —— 柱基木色盖住腿部。
	# 屋前：脚 366 在门前石铺地上（碰撞下沿 340 以南），人盖建筑/台阶。
	var covered: bool = _near(behind[0], behind[1])
	var visible: bool = not _near(front[0], front[1])
	_report("遮挡顺序：柱后→柱盖人 / 屋前→人盖屋", covered and visible,
			"柱后 人在%s / 人藏%s（≈? %s）/ 屋前 人在%s / 人藏%s（≈? %s）"
					% [behind[0], behind[1], covered, front[0], front[1], not visible])
	await _shot("05_behind_post.png")
	await _shot("06_front_building.png")


## 在同一机位拍「人在 / 人藏」两张图，返回 [人在色, 人藏色]（同一世界坐标采样点）。
func _probe(place: Vector2, dy: float) -> Array:
	var player: Player = _player()
	_place(place)
	await _wait(6)
	var img_with: Image = await _capture()
	var body: Node2D = player.get_node_or_null("Body") as Node2D
	if body != null:
		body.visible = false
	await _wait(2)
	var img_without: Image = await _capture()
	if body != null:
		body.visible = true
	var camera: PixelCamera = player.get_node("Camera") as PixelCamera
	var world: Vector2 = player.global_position + Vector2(0.0, dy)
	var screen: Vector2 = world - camera.get_screen_center_position() + Vector2(320.0, 192.0)
	var sx: int = clampi(int(screen.x), 0, img_with.get_width() - 1)
	var sy: int = clampi(int(screen.y), 0, img_with.get_height() - 1)
	return [img_with.get_pixel(sx, sy), img_without.get_pixel(sx, sy)]


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= 0.06 and absf(a.g - b.g) <= 0.06 \
			and absf(a.b - b.b) <= 0.06


func _check_night() -> void:
	var lighting: LightingDirector = _scene().get_node("Lighting") as LightingDirector
	lighting.follow_clock = false
	lighting.set_phase_instant(LightingDirector.PHASE_NIGHT)
	await _wait(4)
	await _shot("07_exterior_night.png")

	_place(Vector2(230.0, 363.0))
	await _wait(6)
	await _shot("08_night_door_front.png")

	_place(Vector2(327.0, 436.0))
	await _wait(6)
	await _shot("09_night_road.png")

	# 恢复白天，避免影响后续传送检查的截图判读
	lighting.set_phase_instant(LightingDirector.PHASE_DAY)
	await _wait(4)


func _check_doors() -> void:
	# 外观 → 酒馆内部：从门前向上走进门口触发框（x210-250, y339-351）。
	# 轮询到场景切换立刻松键，否则落点会带着残余位移漂走。
	_place(Vector2(230.0, 366.0))
	Input.action_press("move_up")
	var arrived := false
	for i in 120:
		await _wait(1)
		var s: Node = _scene()
		if s != null and s.name == "World":
			arrived = true
			break
	Input.action_release("move_up")
	await _wait(6)
	var pos: Vector2 = _player().global_position if arrived else Vector2.INF
	var ok1: bool = arrived and absf(pos.x - 319.0) < 8.0 and pos.y > 330.0 and pos.y < 390.0
	_report("外观→酒馆传送", ok1, "场景 = %s / 落点 = %s" % [_scene().name, pos])
	await _shot("10_arrive_interior.png")

	# 酒馆内部 → 外观：沿门洞向下，穿过正门出口触发框（298-340, 366-376）。
	Input.action_press("move_down")
	var arrived2 := false
	for i in 120:
		await _wait(1)
		var s: Node = _scene()
		if s != null and s.name == "TavernExterior":
			arrived2 = true
			break
	Input.action_release("move_down")
	await _wait(6)
	var pos2: Vector2 = _player().global_position if arrived2 else Vector2.INF
	var ok2: bool = arrived2 and absf(pos2.x - 230.0) < 8.0 and pos2.y > 342.0 and pos2.y < 405.0
	_report("酒馆→外观传送", ok2, "场景 = %s / 落点 = %s" % [_scene().name, pos2])
	await _shot("11_arrive_exterior.png")

	# 外观 → 村：在横向路上向左走，撞上 RoadWest 触发条（x0.5-9.5, y418-514）。
	_place(Vector2(60.0, 466.0))
	Input.action_press("move_left")
	var arrived3 := false
	for i in 180:
		await _wait(1)
		var s: Node = _scene()
		if s != null and s.name == "Village":
			arrived3 = true
			break
	Input.action_release("move_left")
	await _wait(6)
	var pos3: Vector2 = _player().global_position if arrived3 else Vector2.INF
	# 落点带 walking 残余速度会向左漂 ~12px（与 vcheck 村→酒馆同源），容差 ±20
	var ok3: bool = arrived3 and absf(pos3.x - 440.0) < 20.0 and pos3.y > 770.0 and pos3.y < 830.0
	_report("外观→村传送", ok3, "场景 = %s / 落点 = %s" % [_scene().name, pos3])
	await _shot("12_arrive_village.png")


func _scene() -> Node:
	return get_tree().current_scene


func _player() -> Player:
	return _scene().get_node("Sorted/Player") as Player


func _place(pos: Vector2) -> void:
	var player: Player = _player()
	player.velocity = Vector2.ZERO
	player.global_position = pos
	var camera: PixelCamera = player.get_node("Camera") as PixelCamera
	camera.snap_now()


func _sample_at(dy: float) -> Color:
	# 世界坐标 → 屏幕坐标：大地图有相机，视口(640x384)只是世界的一小块，
	# 采样必须先减去相机视野左上角。
	var img: Image = get_viewport().get_texture().get_image()
	var camera: PixelCamera = _player().get_node("Camera") as PixelCamera
	var center: Vector2 = camera.get_screen_center_position()
	var world: Vector2 = _player().global_position + Vector2(0.0, dy)
	var screen: Vector2 = world - center + Vector2(320.0, 192.0)
	return img.get_pixel(clampi(int(screen.x), 0, img.get_width() - 1),
			clampi(int(screen.y), 0, img.get_height() - 1))


func _report(check_name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", check_name, detail])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var err: int = (get_viewport().get_texture().get_image()).save_png(DIR + file_name)
	if err != OK:
		print("save failed ", file_name, " err=", err)
