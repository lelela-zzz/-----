extends Node
## 村庄场景验收检查器：镜头限位 / 地图边界 / 建筑碰撞 / 遮挡顺序 / 门传送往返 / 夜景。
##   "<godot.exe>" res://tests/vshot.tscn    （需要真实渲染，不要 --headless）
## 判定看 [check] 行（PASS/FAIL），结尾有 [vshot] FAIL 计数。
##
## 坐标约定：player.global_position 是脚底；身体中心 = 脚底 + (0, -24)。

const DIR := "res://tests/village_shots/"
const TAVERN_TRIGGER := Rect2(608, 648, 40, 18)
const EXIT_TRIGGER := Rect2(298, 366, 42, 10)

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
	await _check_tavern_wall()
	await _check_occlusion()
	await _check_doors()
	await _check_night()

	print("[vshot] done FAIL=", failures)
	get_tree().quit()


func _check_camera_limits() -> void:
	var camera: PixelCamera = _player().get_node("Camera") as PixelCamera
	_place(Vector2(20.0, 20.0))
	await _wait(4)
	var c1: Vector2 = camera.get_screen_center_position()
	_report("镜头左上限位", c1 == Vector2(320.0, 192.0), "中心 = %s（期望 320,192）" % c1)
	await _shot("01_camera_topleft.png")

	_place(Vector2(860.0, 860.0))
	await _wait(4)
	var c2: Vector2 = camera.get_screen_center_position()
	_report("镜头右下限位", c2 == Vector2(546.0, 674.0), "中心 = %s（期望 546,674）" % c2)
	await _shot("02_camera_bottomright.png")


func _check_map_bounds() -> void:
	# y=150：避开左上角树的树干碰撞（y87-105），测纯地图西界
	_place(Vector2(60.0, 150.0))
	Input.action_press("move_left")
	await _wait(90)
	Input.action_release("move_left")
	await _wait(6)
	var stop_x: float = _player().global_position.x
	_report("地图西界阻挡", absf(stop_x - 13.0) < 2.0, "停在 x = %.1f（期望 ≈13）" % stop_x)
	await _shot("03_map_west_bound.png")


func _check_tavern_wall() -> void:
	# 从酒馆墙正前方向上顶：碰撞下沿 649 + 脚框 6 → 停 655。
	# x=600：避开左侧花槽（543-585）和门口触发框（608 起）。
	_place(Vector2(600.0, 700.0))
	Input.action_press("move_up")
	await _wait(120)
	Input.action_release("move_up")
	await _wait(6)
	var stop_y: float = _player().global_position.y
	_report("酒馆外墙阻挡", absf(stop_y - 655.0) < 1.5, "停在 y = %.1f（期望 ≈655）" % stop_y)
	await _shot("04_tavern_wall_stop.png")


func _check_occlusion() -> void:
	# 2026-10-23 起四栋建筑碰撞上扩至屋脊，酒馆屋后不可再站 → 遮挡检查改用水井：
	# 井后：脚 450 在井碰撞框（460-496）北侧，身体压进 A 字架 → 井盖人
	_place(Vector2(440.0, 450.0))
	await _wait(6)
	await _shot("05_behind_well.png")
	var behind: Color = _sample_at(0.0)

	# 井前：脚 555 在井台与花坛（碰撞 497-543）下方，人盖井台
	_place(Vector2(440.0, 555.0))
	await _wait(6)
	await _shot("06_front_well.png")
	var front: Color = _sample_at(0.0)

	# 占位块是冷灰蓝（b > g > r）；井架木色 r 最大、井石中性——都不是"b 最大"的占位灰蓝。
	var covered: bool = not _is_player_color(behind)
	var visible: bool = _is_player_color(front)
	_report("遮挡顺序：井后→井盖人 / 井前→人盖井", covered and visible,
			"井后采样 %s（非占位色? %s）/ 井前采样 %s（占位色? %s）"
					% [behind, covered, front, visible])


func _is_player_color(c: Color) -> bool:
	# 渲染后的占位块仍保持 b > g > r 的冷灰蓝次序（石台/花坛是 g>=b，木架是 r 最大）
	return c.b > c.g and c.g > c.r


func _check_doors() -> void:
	# 村 → 酒馆：从台阶下向上走进门口触发框（608-648, 648-666）。
	# 轮询到场景切换立刻松键，否则落点会带着残余位移漂走。
	_place(Vector2(628.0, 690.0))
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
	_report("村→酒馆传送", ok1, "场景 = %s / 落点 = %s" % [_scene().name, pos])
	await _shot("07_arrive_tavern.png")

	# 酒馆 → 外观：沿门洞向下，穿过门槛触发框（298-340, 366-376）。
	# 2026-10-22 起正门出口改指酒馆外观场景（tavern_exterior）。
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
	var ok2: bool = arrived2 and absf(pos2.x - 295.0) < 8.0 and pos2.y > 440.0 and pos2.y < 500.0
	_report("酒馆→外观传送", ok2, "场景 = %s / 落点 = %s" % [_scene().name, pos2])
	await _shot("08_arrive_exterior.png")

	# 外观 → 村：正门前面右转上路，沿马路向东走出东缘。
	_place(Vector2(600.0, 556.0))
	Input.action_press("move_right")
	var arrived3 := false
	for i in 180:
		await _wait(1)
		var s: Node = _scene()
		if s != null and s.name == "Village":
			arrived3 = true
			break
	Input.action_release("move_right")
	await _wait(6)
	var pos3: Vector2 = _player().global_position if arrived3 else Vector2.INF
	# 落点带 walking 残余速度会向右漂 ~12px（与 extcheck 同源），容差 ±20
	var ok3: bool = arrived3 and absf(pos3.x - 630.0) < 20.0 and pos3.y > 670.0 and pos3.y < 730.0
	_report("外观→村传送", ok3, "场景 = %s / 落点 = %s" % [_scene().name, pos3])
	await _shot("08b_arrive_village.png")


func _check_night() -> void:
	var lighting: LightingDirector = _scene().get_node("Lighting") as LightingDirector
	lighting.follow_clock = false
	lighting.set_phase_instant(LightingDirector.PHASE_NIGHT)
	await _wait(4)
	await _shot("09_village_night.png")

	_place(Vector2(630.0, 700.0))
	await _wait(6)
	await _shot("10_night_tavern_front.png")

	_place(Vector2(430.0, 540.0))
	await _wait(6)
	await _shot("11_night_market.png")


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
	# 采样必须先减去相机视野左上角（室内 world==screen 所以旧测试不用换算）。
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
