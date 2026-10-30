extends Node
## 跨场景门实测：矿道入口 -> 雪山 -> 回矿道入口。
## 本脚本挂在 root 下、手动加载场景，故切场景时自身不会被释放，可连续验证双向。

var _state: int = 0
var _frames: int = 0
var _failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _load("res://scenes/mine_entrance.tscn", Vector2(452, 1004))


func _load(path: String, at: Vector2) -> void:
	var scene: Node = load(path).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = scene.get_node_or_null("Sorted/Player")
	if player == null:
		_report("加载 %s 找到玩家" % path, false)
		get_tree().quit()
		return
	player.global_position = at
	# 等 DoorArea 触发 + change_scene_to_file（deferred）完成。
	# 注意 change_scene 期间 current_scene 会**瞬时为 null**（先卸旧再装新），
	# 所以要等"非 null 且已换人"，否则会在中间那一帧 break 出去拿到 null。
	for i in 180:
		await get_tree().physics_frame
		var cur: Node = get_tree().current_scene
		if cur != null and cur != scene:
			break
	_after_change()


func _after_change() -> void:
	var cur: Node = get_tree().current_scene
	if cur == null:
		_report("切场景后拿得到新场景", false, "current_scene=null")
		print("[verify_snow_door] done FAIL=%d" % _failures)
		get_tree().quit()
		return
	var path: String = cur.scene_file_path
	var player: Node2D = cur.get_node_or_null("Sorted/Player")
	var pos: Vector2 = player.global_position if player != null else Vector2(-1, -1)
	_frames += 1
	if _state == 0:
		# 期望：已从矿道入口切到雪山，落点 ~ (250,475)（雪山的默认落脚点）
		var ok_scene: bool = path == "res://scenes/snow_mountain.tscn"
		var ok_pos: bool = pos.distance_to(Vector2(250, 475)) < 48.0
		_report("矿道入口 -> 雪山（场景切换）", ok_scene, "scene=%s" % path)
		_report("到达雪山落点在 (250,475) 附近", ok_pos, "pos=%s" % pos)
		_state = 1
		# 继续：踩雪山的回程门（Doors/MineReturn 的触发框在 (325,478)）
		player.global_position = Vector2(325, 478)
		for i in 180:
			await get_tree().physics_frame
			var cur2: Node = get_tree().current_scene
			if cur2 != null and cur2 != cur:
				break
		_after_change()
	elif _state == 1:
		# 期望：从雪山切回矿道入口，落点 ~ (500,962)（底部土路上，雪山门正上方）
		var ok_scene: bool = path == "res://scenes/mine_entrance.tscn"
		var ok_pos: bool = pos.distance_to(Vector2(500, 962)) < 48.0
		_report("雪山 -> 矿道入口（场景切换）", ok_scene, "scene=%s" % path)
		_report("回到矿道入口落点在 (500,962) 附近", ok_pos, "pos=%s" % pos)
		print("[verify_snow_door] done FAIL=%d" % _failures)
		get_tree().quit()


func _report(name: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
