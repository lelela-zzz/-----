extends Node
## 矿道入口地图验收：入口落点 / 碰撞数据 / 相机限位 / 双向传送 / 时间延续。
##   "<godot.exe>" --headless --path . res://tests/verify_mine_entrance.tscn --quit-after 6000

const MINE_ENTRANCE := "res://scenes/mine_entrance.tscn"
const VILLAGE := "res://scenes/village.tscn"

var failures: int = 0


func _ready() -> void:
	await _wait(2)
	# 先用村庄场景起步，验证「北出口 → 矿道入口」
	var village: Node = (load(VILLAGE) as PackedScene).instantiate()
	get_tree().root.add_child(village)
	get_tree().current_scene = village
	await _wait(12)
	_check_village_door_exists()
	await _check_village_to_snow()
	_check_snow_entry()
	_check_colliders()
	_check_camera()
	await _check_snow_back_to_village()
	_check_time_carry()

	print("[verify_mine_entrance] done FAIL=", failures)
	get_tree().quit()


func _check_village_door_exists() -> void:
	var door: Area2D = _scene().get_node_or_null("Doors/MineEntrancePath") as Area2D
	_report("村庄北出口存在", door != null and (door as DoorArea).target_scene == MINE_ENTRANCE,
			"目标=%s" % ("<无>" if door == null else (door as DoorArea).target_scene))


func _check_village_to_snow() -> void:
	_set_time(9, 30)
	_place(Vector2(447, 44))
	var arrived: bool = await _walk_up_until("MineEntrance", 120)
	await _wait(6)
	var pos: Vector2 = _player().global_position if _player() != null else Vector2.INF
	_report("村庄北出口 → 矿道入口", arrived and pos.distance_to(Vector2(875, 40)) < 10.0,
			"场景=%s 落点=%s" % [_scene_name(), pos])


func _check_snow_entry() -> void:
	var bg: Sprite2D = _scene().get_node_or_null("Background") as Sprite2D
	var ok: bool = bg != null and bg.texture != null and bg.texture.get_size() == Vector2(2048, 2048)
	_report("矿道入口底图 2048²（2x 渲染）", ok,
			"底图=%s" % ("<无>" if bg == null or bg.texture == null else str(bg.texture.get_size())))


func _check_colliders() -> void:
	var bodies: Node = _scene().get_node_or_null("Sorted/PropBodies") as Node
	var count: int = bodies.get_child_count() if bodies != null else -1
	_report("岩壁碰撞已生成（>300 条）", count > 300, "碰撞体 %d 条" % count)


func _check_camera() -> void:
	var cam: PixelCamera = _player().get_node_or_null("Camera") as PixelCamera
	var ok: bool = cam != null and cam.limit_right - cam.limit_left == 1024 \
			and cam.limit_bottom - cam.limit_top == 1024
	_report("相机限位=矿道入口地图 1024²", ok,
			"限位=[%d,%d]-[%d,%d]" % [cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom] if cam else "无相机")


func _check_snow_back_to_village() -> void:
	_place(Vector2(875, 52))
	var arrived: bool = await _walk_up_until("Village", 120)
	await _wait(6)
	var pos: Vector2 = _player().global_position if _player() != null else Vector2.INF
	_report("矿道入口北口 → 村庄", arrived and absf(pos.x - 447.0) < 10.0 and pos.y > 28.0 and pos.y < 60.0,
			"场景=%s 落点=%s" % [_scene_name(), pos])


func _check_time_carry() -> void:
	var clock: GameClock = _scene().get_node_or_null("Clock") as GameClock
	_report("跨场景时间延续", clock != null and clock.hour == 9,
			"当前 %s" % ("无 Clock" if clock == null else "%02d:%02d" % [clock.hour, clock.minute]))


# ---- helpers -------------------------------------------------------------


func _scene() -> Node:
	return get_tree().current_scene


func _scene_name() -> String:
	var s: Node = _scene()
	return s.name if s != null else "<null>"


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


func _set_time(hour: int, minute: int) -> void:
	var clock: GameClock = _scene().get_node_or_null("Clock") as GameClock
	if clock != null:
		clock.running = false
		clock.set_time(hour, minute)


func _await_scene(name: String, frames: int) -> bool:
	for i in frames:
		await _wait(1)
		var s: Node = _scene()
		if s != null and s.name == name:
			return true
	return false


## 按上方向键走，直到切到目标场景（或超时）。切场景当帧就松键，
## 否则在新场景里继续压着方向键，会立刻踩到对侧的传送口弹回去。
func _walk_up_until(target: String, frames: int) -> bool:
	Input.action_press("move_up")
	var hit: bool = false
	for i in frames:
		await get_tree().physics_frame
		var s: Node = get_tree().current_scene
		if s != null and s.name == target:
			hit = true
			break
	Input.action_release("move_up")
	return hit


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _report(check_name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", check_name, detail])
