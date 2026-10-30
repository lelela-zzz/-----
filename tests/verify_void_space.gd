extends Node
## 灰空间（dark_space）位置场景验收 —— 宁芙那场戏。
##   1) scenes/dark_space.tscn 是能站人的位置场景：Node2D + Background + Sorted + Player + Camera + HUD/UIRoot；
##      特别注意它不再是 CanvasLayer 覆盖层（那个已经迁去 dark_room.tscn 了）；
##   2) 背景是一整片无缝灰底（Sprite2D，z_index = -10，带贴图）；
##   3) ch2_void_nymph 幕会脚本化跳进灰空间，并把宁芙、林格都摆出来；
##   4) 这一幕播完自动跳回泉水，接上「泉边醒来」。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_void_space.tscn --quit-after 15000

const VOID: String = "res://scenes/dark_space.tscn"
const SPRING: String = "res://scenes/spring.tscn"
const QID: String = "ch2_moon"

var passed: int = 0
var failed: int = 0
var _scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	ChapterStory.reset()                 # 第一章不参与本用例
	Chapter2Story.wait_for_talk = false  # 自动播，便于 headless 跑通
	Chapter2Story.reset()
	QuestLog.reset()
	await get_tree().process_frame

	await _part_scene()
	await _part_beat()

	QuestLog.reset()
	print("[void] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 场景结构 ---------------------------------------------------------

func _part_scene() -> void:
	var ps: PackedScene = load(VOID) as PackedScene
	_report("dark_space.tscn 可加载", ps != null, "ps=%s" % (ps != null))
	_scene = ps.instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	await _tick()

	_report("是位置场景（Node2D），不是 CanvasLayer 覆盖层",
			_scene is Node2D and not (_scene is CanvasLayer),
			"type=%s" % _scene.get_class())

	var bg: Sprite2D = _scene.get_node_or_null("Background") as Sprite2D
	_report("有无缝灰底背景（Sprite2D z=-10 且带贴图）",
			bg != null and bg.texture != null and int(bg.z_index) == -10,
			"bg=%s tex=%s z=%s" % [bg != null,
			(bg.texture != null) if bg != null else false,
			(bg.z_index) if bg != null else -99])

	var sorted: Node2D = _scene.get_node_or_null("Sorted") as Node2D
	_report("有 Sorted 排序层（NPC 挂这儿，y_sort 打开）",
			sorted != null and sorted.y_sort_enabled,
			"sorted=%s ysort=%s" % [sorted != null,
			sorted.y_sort_enabled if sorted != null else false])

	var player: Node = _scene.get_node_or_null("Sorted/Player")
	_report("有玩家且进了 player 组（导演要靠它定站位/朝向）",
			player != null and player.is_in_group("player"),
			"player=%s" % (player != null))

	var cam: Camera2D = _scene.get_node_or_null("Sorted/Player/Camera") as Camera2D
	_report("有跟随相机（map_rect 罩住整片地面）",
			cam != null and cam.map_rect.size.x >= 1280.0 and cam.map_rect.size.y >= 768.0,
			"cam=%s rect=%s" % [cam != null, cam.map_rect if cam != null else Rect2()])

	var ui: Node = _scene.get_node_or_null("HUD/UIRoot")
	_report("有 HUD/UIRoot 注入点（对话框挂这儿）", ui != null, "ui=%s" % (ui != null))


# ---- 2. 宁芙幕的进出 -----------------------------------------------------

func _part_beat() -> void:
	var idx: int = _beat_index("ch2_void_nymph")
	_report("第二章含 ch2_void_nymph 幕", idx >= 0, "idx=%d" % idx)
	_report("这一幕 place=dark_space",
			str(_beat_data("ch2_void_nymph").get("place", "")) == "dark_space",
			"place=%s" % str(_beat_data("ch2_void_nymph").get("place", "")))

	# 灰空间场景已在 _part_scene 里挂好，直接从这一幕起播
	# （注意别在这里再 _mount 一次：那会连刚弹出的对话框一起释放掉）
	Chapter2Story.begin(idx)
	var p: Node = await _await_panel()
	_report("进入灰空间即播出宁芙 / 林格这一幕",
			p != null and _beat_id() == "ch2_void_nymph",
			"beat=%s panel=%s" % [_beat_id(), p != null])
	_report("宁芙与林格都已入场",
			_npc_present("spring_nymph") and _npc_present("knight_ringe"),
			"nymph=%s ringe=%s" % [_npc_present("spring_nymph"), _npc_present("knight_ringe")])

	# 站位：一次性对话空间里玩家全程被冻结、转不了身，
	# 所以初始朝向必须一开始就对着两人，三人间距也得够短。
	var p_node: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var n_node: Node2D = _npc_node("spring_nymph")
	var r_node: Node2D = _npc_node("knight_ringe")
	if p_node != null:
		var f: Vector2i = p_node.get("facing")
		_report("主角面朝二人（初始朝上）", f == Vector2i.UP, "facing=%s" % str(f))
	else:
		_report("主角面朝二人（初始朝上）", false, "无玩家节点")
	if p_node != null and n_node != null and r_node != null:
		var d_pn: float = p_node.global_position.distance_to(n_node.global_position)
		var d_nr: float = n_node.global_position.distance_to(r_node.global_position)
		_report("主角↔宁芙 距离够短（<100）", d_pn < 100.0, "d=%.0f" % d_pn)
		_report("宁芙↔林格 距离够短（<80）", d_nr < 80.0, "d=%.0f" % d_nr)
	else:
		_report("主角↔宁芙 距离够短（<100）", false, "缺 NPC 节点")
		_report("宁芙↔林格 距离够短（<80）", false, "缺 NPC 节点")

	# 播完 → 自动跳回泉水接「泉边醒来」
	await _close_current(p)
	await _tick()
	_report("幕播完自动跳回泉水", _scene_id() == SPRING, "scene=%s" % _scene_id())
	var p2: Node = await _await_panel()
	_report("回到泉水即播第 13 幕（泉边醒来）",
			p2 != null and _beat_id() == "ch2_spring_wake",
			"beat=%s panel=%s" % [_beat_id(), p2 != null])

	# 落点必须是幕里指定的泉边（jump_spawn），而不是场景默认入口 (700,620)
	var wake: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if wake != null:
		var d_edge: float = wake.global_position.distance_to(Vector2(300.0, 400.0))
		_report("醒来落点在泉边（jump_spawn 生效）", d_edge < 24.0,
				"pos=(%.0f,%.0f) d=%.0f" % [wake.global_position.x,
				wake.global_position.y, d_edge])
	else:
		_report("醒来落点在泉边（jump_spawn 生效）", false, "无玩家节点")
	await _close_current(p2)


# ---- 工具 ---------------------------------------------------------------

func _beat_index(want: String) -> int:
	var beats: Array = Chapter2Story._beats
	for i: int in beats.size():
		if str((beats[i] as Dictionary).get("id", "")) == want:
			return i
	return -1


func _beat_data(want: String) -> Dictionary:
	var beats: Array = Chapter2Story._beats
	for b: Variant in beats:
		if str((b as Dictionary).get("id", "")) == want:
			return b as Dictionary
	return {}


func _beat_id() -> String:
	return str(Chapter2Story.current_beat().get("id", ""))


func _scene_id() -> String:
	var s: Node = get_tree().current_scene
	return s.scene_file_path if s != null else ""


func _mount(path: String) -> Node:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	var ps: PackedScene = load(path) as PackedScene
	_scene = ps.instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	await _tick()
	return _scene


func _await_panel(max_frames: int = 60) -> Node:
	for i: int in max_frames:
		for n: Node in get_tree().get_nodes_in_group("modal_ui"):
			if is_instance_valid(n) and not n.is_queued_for_deletion() and n is UiPanel:
				return n
		await get_tree().process_frame
	return null


func _close_current(panel: Node) -> void:
	if panel == null:
		return
	var guard: int = 0
	while is_instance_valid(panel) and not panel.is_queued_for_deletion() and guard < 160:
		_push_key(KEY_E)
		await get_tree().process_frame
		await get_tree().process_frame
		guard += 1
	await _tick()


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


func _tick() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _npc_present(id: String) -> bool:
	return _npc_node(id) != null


func _npc_node(id: String) -> Node2D:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return n as Node2D
	return null


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
