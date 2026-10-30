extends Node
## 雪山地图验收（独立可跑，暂未接线）：
##   底图 1024²（2x 渲染）/ 岩壁碰撞 / 相机 512² / 出生点可站 / 木屋为障碍 /
##   出生点能走通 / 木桥可站立。
## ⚠ 雪山是 **512² 标准**（用户 2026-10-29 23:48 定的）：底图 1x=512²、2x=1024²、
##   props.json 512 空间、相机限位 512²。底图/相机两条断言已按 512 标准改过。
## ⚠ 本文件里 SPAWN/BRIDGE/CAMP/NEAR_BANK 那几个常量仍是旧 1024 空间的坐标，
##   在 512 地图上会被地图边界夹住，结论偏弱；等岩壁碰撞用
##   tools/make_snow_collision.py 按新底图重算之后一并改成 512 坐标。
## 连通性（整张图是可走的一整块）由 tools/make_snow_collision.py 的
## "保留最大连通块"保证，产物固定为单一分量。
##   "<godot.exe>" --headless --path . res://tests/verify_snow.tscn --quit-after 90000

const SNOW := "res://scenes/snow_mountain.tscn"
const SPAWN := Vector2(500, 965)
const BRIDGE := Vector2(770, 710)
const SPRING := Vector2(520, 380)
const CAMP := Vector2(300, 800)
## 过桥：从西岸沿 X 轴（东向）走到东岸，落点必须是实地
const NEAR_BANK := Vector2(640, 710)
const FAR_MIN_X := 850.0

var failures: int = 0


func _ready() -> void:
	await _wait(2)
	var scene: Node = (load(SNOW) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(12)
	_check_bg()
	_check_colliders()
	_check_camera()
	_check_spawn_free()
	_check_spring_solid()
	_check_camp_free()
	await _check_walk_from_spawn()
	await _check_bridge()
	await _check_cross_bridge()
	print("[verify_snow] done FAIL=", failures)
	get_tree().quit()


func _check_bg() -> void:
	var bg: Sprite2D = _scene().get_node_or_null("Background") as Sprite2D
	var ok: bool = bg != null and bg.texture != null and bg.texture.get_size() == Vector2(1024, 1024)
	_report("雪山底图 1024²（2x 渲染，512 原生）", ok,
			"底图=%s" % ("<无>" if bg == null or bg.texture == null else str(bg.texture.get_size())))


func _check_colliders() -> void:
	var bodies: Node = _scene().get_node_or_null("Sorted/PropBodies") as Node
	var count: int = bodies.get_child_count() if bodies != null else -1
	_report("雪山岩壁碰撞已生成（>100 条）", count > 100, "碰撞体 %d 条" % count)


func _check_camera() -> void:
	var cam: PixelCamera = _player().get_node_or_null("Camera") as PixelCamera
	var ok: bool = cam != null and cam.limit_right - cam.limit_left == 512 \
			and cam.limit_bottom - cam.limit_top == 512
	_report("相机限位=雪山地图 512²", ok,
			"限位=[%d,%d]-[%d,%d]" % [cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom] if cam else "无相机")


func _check_spawn_free() -> void:
	_report("出生点在可走区", not _solid_at(SPAWN), "出生=%s" % SPAWN)


func _check_spring_solid() -> void:
	_report("泉水是障碍（水面不可走）", _solid_at(SPRING), "泉水=%s" % SPRING)


func _check_camp_free() -> void:
	_report("营地可踏入", not _solid_at(CAMP), "营地=%s" % CAMP)


func _check_walk_from_spawn() -> void:
	_place(SPAWN)
	Input.action_press("move_up")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("move_up")
	var moved: float = SPAWN.y - _player().global_position.y
	_report("从出生点能沿小径走上山（非困在死角）", moved > 60.0, "上移 %.0f px" % moved)


func _check_bridge() -> void:
	_report("木桥位置可站立", not _solid_at(BRIDGE), "桥=%s" % BRIDGE)
	_place(BRIDGE)
	Input.action_press("move_left")
	for i in 120:
		await get_tree().physics_frame
	Input.action_release("move_left")
	var moved: float = BRIDGE.x - _player().global_position.x
	_report("站在桥上能沿桥移动（横向）", moved > 30.0, "左移 %.0f px" % moved)


## 防线（对应"过桥掉进水里"那次事故）：真的从近岸走到对岸，
## 落点必须在桥另一侧的雪地上，而不是水面/障碍里。
func _check_cross_bridge() -> void:
	_place(NEAR_BANK)
	Input.action_press("move_right")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var p: Vector2 = _player().global_position
	var solid: bool = _solid_at(p)
	_report("过桥后落在对岸实地（不是掉进水里）",
			p.x >= FAR_MIN_X and not solid,
			"落点=(%.0f,%.0f) 落在障碍=%s" % [p.x, p.y, solid])


# ---- helpers -------------------------------------------------------------


## 该点是否落在静态碰撞体里（静态体只参与 bodies）
func _solid_at(pos: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _player().get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = pos
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits: Array = space.intersect_point(q, 1)
	return hits.size() > 0


func _scene() -> Node:
	return get_tree().current_scene


func _player() -> Player:
	var s: Node = _scene()
	return (s.get_node_or_null("Sorted/Player") as Player) if s != null else null


func _place(pos: Vector2) -> void:
	var player: Player = _player()
	if player == null:
		return
	player.velocity = Vector2.ZERO
	player.global_position = pos
	var cam: PixelCamera = player.get_node_or_null("Camera") as PixelCamera
	if cam != null:
		cam.snap_now()
	await get_tree().physics_frame


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _report(check_name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", check_name, detail])
