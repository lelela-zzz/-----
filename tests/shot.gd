extends Node
## 基础模块验收驱动：真机跑一遍移动 / 碰撞 / 遮挡 / 时段，抓 PNG 供人眼检查。
##   "<godot.exe>" res://tests/shot.tscn      （不要加 --headless，需要真实渲染）
## 判定看打印出来的 [check] 行（PASS/FAIL）。
##
## 坐标系约定：player.global_position 是**脚底**（节点原点在脚下），
## 所以"角色身体中心"= position + (0, -24)。

const ENTRY_SCENE := "res://scenes/world.tscn"
const DIR := "res://tests/shots/"
const BODY_CENTER_OFFSET := Vector2(0.0, -24.0)

var scene: Node2D
var player: Player


func _ready() -> void:
	TestView.logic_resolution()
	# 顾客是随机刷新的动态层，会站进吧台通道、也会挡采样点 ——
	# 本用例要的是确定的画面和位移，所以整个顾客层关掉。
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	scene = (load(ENTRY_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	player = scene.get_node("Sorted/Player") as Player
	Engine.max_fps = 60
	print("[check] move_right 绑定数 = ", InputMap.action_get_events("move_right").size())
	await _wait(8)
	await _shot("01_day_spawn.png")

	await _check_prop_layer()
	await _check_horizontal()
	await _check_four_direction()
	await _check_room_bounds()
	await _check_door()
	await _check_furniture_block()
	await _check_occlusion()
	await _check_aisle()
	await _check_bar_blockers()
	await _check_lighting()
	await _check_clock()
	await _check_gradient()

	print("shots: ", DirAccess.get_files_at(DIR))
	get_tree().quit()


func _check_prop_layer() -> void:
	var sorted: Node2D = scene.get_node("Sorted") as Node2D
	var bodies: Node = sorted.get_node_or_null("PropBodies")
	var shapes: int = 0
	if bodies != null:
		for child: Node in bodies.get_children():
			if child is CollisionShape2D:
				shapes += 1
	_report("家具层生成（精灵+碰撞框）", shapes > 0 and sorted.get_child_count() > 10,
			"Sorted 子节点 %d 个 / 碰撞框 %d 个" % [sorted.get_child_count(), shapes])


func _check_horizontal() -> void:
	_place(Vector2(300.0, 270.0))
	var p0: Vector2 = player.global_position
	Input.action_press("move_right")
	await _wait(30)
	Input.action_release("move_right")
	await _wait(20)
	var d: Vector2 = player.global_position - p0
	_report("单键右移", d.x > 20.0 and absf(d.y) < 0.01, "位移 = %s" % d)
	await _shot("02_moved.png")


func _check_four_direction() -> void:
	_place(Vector2(300.0, 270.0))
	var p0: Vector2 = player.global_position
	Input.action_press("move_up")
	Input.action_press("move_right")
	await _wait(24)
	Input.action_release("move_up")
	Input.action_release("move_right")
	await _wait(16)
	var d: Vector2 = player.global_position - p0
	_report("双键同按仍只走单轴", absf(d.y) < 0.01 and d.x > 10.0, "位移 = %s" % d)


func _check_room_bounds() -> void:
	_place(Vector2(200.0, 270.0))
	Input.action_press("move_down")
	await _wait(150)
	Input.action_release("move_down")
	await _wait(20)
	var stop_y: float = player.global_position.y
	# 可行走框下沿 306（x=200 在两列长桌之间，非门洞），脚底就是节点原点 → 应停在 306
	_report("下边界阻挡（脚部判定）", absf(stop_y - 306.0) < 1.5, "停在 y = %.2f（期望 ≈306）" % stop_y)
	await _shot("03_bounds.png")


func _check_door() -> void:
	# 门洞 x296-342 现在是通往酒馆外观的传送触发框（298-340, 366-376）：
	# 走进去会切场景而不是停在门槛 378。行为级测试归 tests/extshot.tscn
	#（外观↔酒馆往返 PASS 即"门洞可通行"），这里只验触发框接线。
	# 2026-10-22 起正门出口改指 tavern_exterior（村子经外观马路到达）。
	var door: DoorArea = scene.get_node_or_null("Doors/ExitSouth") as DoorArea
	_report("出口传送框接线", door != null and door.target_scene == "res://scenes/tavern_exterior.tscn"
			and door.spawn_position == Vector2(230, 363),
			"target = %s / spawn = %s" % [door.target_scene if door else "<无>",
			door.spawn_position if door else "-"])


func _check_furniture_block() -> void:
	_place(Vector2(380.0, 270.0))
	Input.action_press("move_up")
	await _wait(180)
	Input.action_release("move_up")
	await _wait(20)
	var stop_y: float = player.global_position.y
	# 酒桶画面底 134 → sort_y 134、碰撞下沿 135；脚框高 6 → 应停在 141
	_report("家具阻挡（酒桶）", absf(stop_y - 141.0) < 1.5, "停在 y = %.2f（期望 ≈141）" % stop_y)
	await _shot("04_blocked_by_barrels.png")


func _check_occlusion() -> void:
	# 用长桌 1（画面 y132..220、sort_y≈218）：人能站到「脚在碰撞框外、身体压在桌面上」处检验遮挡。
	# 新角色是暖色（不像占位块那样 b>r），改用「无玩家基线差分」判定谁在上面：
	#   桌后 → 桌面盖住角色 → 该像素 ≈ 空地基线；桌前 → 角色盖住桌面 → 该像素 ≠ 基线。
	var behind_pt: Vector2 = Vector2(150.0, 152.0 - 6.0)
	var front_pt: Vector2 = Vector2(150.0, 228.0 - 14.0)

	# 基线：角色挪到空地，采同一世界像素（此时没有角色遮挡）
	_place(Vector2(300.0, 200.0))
	await _wait(6)
	var base_behind: Color = _sample_world(behind_pt)
	var base_front: Color = _sample_world(front_pt)

	_place(Vector2(150.0, 152.0))
	await _wait(8)
	await _shot("13_occlusion_behind_table.png")
	var behind: Color = _sample_world(behind_pt)

	_place(Vector2(150.0, 228.0))
	await _wait(8)
	await _shot("14_occlusion_front_table.png")
	var front: Color = _sample_world(front_pt)

	var prop_on_top: bool = _color_close(behind, base_behind, 0.06)
	var player_on_top: bool = not _color_close(front, base_front, 0.06)
	_report("遮挡顺序：人在桌后→桌盖人；人在桌前→人盖桌", prop_on_top and player_on_top,
			"桌后 %s≈基线 %s(%s) / 桌前 %s≠基线 %s(%s)"
					% [behind, base_behind, prop_on_top, front, base_front, player_on_top])


## 通道检查：吧台前横向 28px、两列长桌之间 20px、前后两排之间 20px
func _check_aisle() -> void:
	# 1) 沿吧台前通道从东往西走，应该能一路走到左侧
	_place(Vector2(300.0, 145.0))
	Input.action_press("move_left")
	await _wait(200)
	Input.action_release("move_left")
	await _wait(16)
	var west_x: float = player.global_position.x
	await _shot("15_aisle_in_front_of_bar.png")
	_report("吧台前通道可横穿", west_x < 150.0, "从 x=300 向西走到 x=%.1f" % west_x)

	# 通道中段的观感（站在吧台正前方）
	_place(Vector2(200.0, 145.0))
	await _wait(6)
	await _shot("15b_aisle_mid.png")

	# 2) 从房间下方沿两列长桌之间的缝上行，应该能一直走到吧台前
	_place(Vector2(204.0, 300.0))
	Input.action_press("move_up")
	await _wait(240)
	Input.action_release("move_up")
	await _wait(16)
	var north_y: float = player.global_position.y
	await _shot("16_aisle_between_tables.png")
	_report("桌间纵向通道可穿行", north_y < 148.0, "从 y=300 向北走到 y=%.1f（吧台碰撞下沿 132 + 脚框 6 = 138）" % north_y)


## 吧台碰撞专项：左侧通道不被横断、人不会站到柜面上
func _check_bar_blockers() -> void:
	# 1) 沿立柱与长桌之间的左侧通道往下走：旧碰撞框（03 回折外伸 63px）会在 y≈194 隐形拦断
	_place(Vector2(112.0, 140.0))
	Input.action_press("move_down")
	await _wait(200)
	Input.action_release("move_down")
	await _wait(16)
	var down_y: float = player.global_position.y
	await _shot("17_left_strip_passable.png")
	_report("左侧通道贯通（无隐形墙）", down_y > 280.0, "从 y=140 走到 y=%.1f（旧版会被 03 的隐形框卡在 ~194）" % down_y)

	# 2) 从南往北顶吧台：应该停在台面前沿之外，而不是站到柜面上
	_place(Vector2(110.0, 200.0))
	Input.action_press("move_up")
	await _wait(150)
	Input.action_release("move_up")
	await _wait(16)
	var up_y: float = player.global_position.y
	await _shot("18_bar_front_stop.png")
	_report("停吧台前沿", absf(up_y - 138.0) < 1.5, "停在 y = %.1f（期望 ≈138 = 碰撞下沿 132 + 脚框 6）" % up_y)

func _check_lighting() -> void:
	var lighting: LightingDirector = scene.get_node("Lighting") as LightingDirector
	# 手动切档前要先断开跟随时钟，否则下一个游戏分钟就会被时钟覆盖回去
	lighting.follow_clock = false
	lighting.set_phase_instant(LightingDirector.PHASE_DUSK)
	await _wait(4)
	await _shot("05_dusk.png")

	lighting.set_phase_instant(LightingDirector.PHASE_NIGHT)
	await _wait(4)
	await _shot("06_night.png")

	# 同一时段、同一颜色，只改离炉火的距离 → 亮度必须不同。
	# 采样点从 (327,174) 右移到 (360,174)：锅（BrewingPot，x284..344）加进来以后，
	# 原来那一点被锅的贴图盖住，采到的是锅不是角色。
	_place(Vector2(360.0, 174.0))
	await _wait(6)
	await _shot("07_night_at_hearth.png")
	var near_hearth: float = _sample_body_lum()

	_place(Vector2(300.0, 294.0))
	await _wait(6)
	await _shot("08_night_far_corner.png")
	var far: float = _sample_body_lum()

	var ambient: Color = player.modulate
	# 单像素判定在这套角色贴图上不稳：身体中心正外侧常是描边的近黑像素，
	# 角色朝向/动画帧一动，采样值就能差一倍。改成取身体中心的 7x7 平均亮度。
	_report("角色响应炉火光",
			near_hearth > far + 0.04,
			"夜间环境色 %s / 火边 %.3f vs 远角 %.3f（7x7 平均）"
					% [ambient, near_hearth, far])


func _check_clock() -> void:
	# 30 现实秒 = 1 游戏小时 → advance(30) 应该整点 +1
	var clock: GameClock = scene.get_node("Clock") as GameClock
	var h0: int = clock.hour
	clock.advance(30.0)
	await _wait(2)
	_report("时钟 30 秒 = 1 小时", clock.hour == (h0 + 1) % 24, "%02d 点 → %02d 点" % [h0, clock.hour])

	clock.set_time(8, 30)
	await _wait(3)
	await _shot("09_clock_0830.png")

	clock.set_time(21, 0)
	await _wait(4)
	await _shot("10_clock_21.png")


func _check_gradient() -> void:
	var lighting: LightingDirector = scene.get_node("Lighting") as LightingDirector
	var clock: GameClock = scene.get_node("Clock") as GameClock

	# 5:00 正好落在"夜 → 黎明"的过渡中段，权重应在 0~1 之间
	lighting.follow_clock = true
	clock.set_time(5, 0)
	await _wait(3)
	var mid_weight: float = lighting.last_weight
	var mid_amb: Color = player.modulate
	await _shot("11_gradient_sunrise_mid.png")

	clock.set_time(12, 0)
	await _wait(3)
	var noon_amb: Color = player.modulate
	await _shot("12_gradient_noon.png")

	_report("日出是渐变中间态",
			mid_weight > 0.05 and mid_weight < 0.95 and mid_amb.g < noon_amb.g - 0.05,
			"5 点权重 %.2f / 环境绿 %.2f（正午 %.2f）" % [mid_weight, mid_amb.g, noon_amb.g])

	# 平台段应该完全等于白天的帧（权重 0，不残留过渡层）
	_report("稳定平台无残留过渡",
			lighting.last_weight == 0.0 and is_equal_approx(noon_amb.g, 1.0),
			"12 点权重 %.2f / 环境绿 %.2f" % [lighting.last_weight, noon_amb.g])


func _place(pos: Vector2) -> void:
	player.velocity = Vector2.ZERO
	player.global_position = pos


## 采样角色身体中心那一像素（脚底上方 24px）
func _sample_body() -> Color:
	return _sample_at(BODY_CENTER_OFFSET.y)


## 身体中心 7x7 区域的平均亮度（抗贴图里的近黑描边像素）。
func _sample_body_lum() -> float:
	var img: Image = get_viewport().get_texture().get_image()
	var c: Vector2i = Vector2i((player.global_position + BODY_CENTER_OFFSET).round())
	var acc: float = 0.0
	var n: int = 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var x: int = clampi(c.x + dx, 0, img.get_width() - 1)
			var y: int = clampi(c.y + dy, 0, img.get_height() - 1)
			acc += img.get_pixel(x, y).get_luminance()
			n += 1
	return acc / float(n)


## 采样角色身上某一点（dy 相对脚底，例如 -24 = 身体中心）
func _sample_at(dy: float) -> Color:
	var img: Image = get_viewport().get_texture().get_image()
	var p: Vector2i = Vector2i((player.global_position + Vector2(0.0, dy)).round())
	return img.get_pixel(clampi(p.x, 0, img.get_width() - 1), clampi(p.y, 0, img.get_height() - 1))


## 采样屏幕(=世界，本场景无相机)上任意一点的颜色。
func _sample_world(pos: Vector2) -> Color:
	var img: Image = get_viewport().get_texture().get_image()
	var p: Vector2i = Vector2i(pos.round())
	return img.get_pixel(clampi(p.x, 0, img.get_width() - 1), clampi(p.y, 0, img.get_height() - 1))


## 两色是否足够接近（逐通道容差）。
func _color_close(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol


func _report(name: String, ok: bool, detail: String) -> void:
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var err: int = (get_viewport().get_texture().get_image()).save_png(DIR + file_name)
	if err != OK:
		print("save failed ", file_name, " err=", err)
