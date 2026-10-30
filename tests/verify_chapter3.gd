extends Node
## 第三章「龙王传说」剧情导演验收（Chapter3Story）。
##   1) data/story_chapter3.json 骨架：10 幕、id/place/entries、next 链首尾相连、
##      每个非空 speaker 都在场（拜登 = 玩家，不算）；
##   2) 酒馆 2 幕（奇斯送密函 → 西蒙带路）；
##   3) 矿道入口 → 矿井（史莱姆 / 裂隙传送门）；
##   4) travel → 导演脚本化跳进龙巢（龙巢不在 map_graph）；
##   5) 龙巢 4 幕（爱德华会合 → 龙醒林格登场 → 圣剑 + 白幕 → 醒来告别）；
##   6) 回酒馆收尾 → 全篇终章（game_finished）。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_chapter3.tscn --quit-after 12000

const WORLD: String = "res://scenes/world.tscn"
const MINE_ENT: String = "res://scenes/mine_entrance.tscn"
const MINE: String = "res://scenes/mine.tscn"
const LAIR: String = "res://scenes/dragon_lair.tscn"

const QID: String = "ch3_dragon_king"

var passed: int = 0
var failed: int = 0
var _scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	ChapterStory.reset()
	Chapter2Story.reset()
	Chapter3Story.wait_for_talk = false  # 自动播，便于 headless 跑通
	Chapter3Story.reset()
	QuestLog.reset()
	await get_tree().process_frame

	_check_data()
	await _run()

	QuestLog.reset()
	print("[chapter3] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 数据 -------------------------------------------------------------

func _check_data() -> void:
	var beats: Array = Chapter3Story._beats
	_report("第三章数据 10 幕", beats.size() == 10, "beats=%d" % beats.size())

	var bad: String = ""
	var ids: Array[String] = []
	var bad_place: String = ""
	for b: Variant in beats:
		var beat: Dictionary = b as Dictionary
		var id: String = str(beat.get("id", ""))
		var place: String = str(beat.get("place", ""))
		if id == "" or place == "":
			bad += "%s(缺字段) " % id
		if (beat.get("entries", []) as Array).is_empty():
			bad += "%s(无台词) " % id
		if ids.has(id):
			bad += "%s(重复) " % id
		ids.append(id)
		if place != "travel" and not Chapter3Story.PLACE_SCENE.has(place):
			bad_place += "%s→%s " % [id, place]
	_report("每幕都有 id/place/entries，且 id 唯一", bad == "", bad)
	_report("place 都是已知场景或 travel", bad_place == "", bad_place)

	var chain: String = ""
	for i: int in beats.size():
		var nxt: Variant = (beats[i] as Dictionary).get("next", null)
		var want: Variant = null
		if i + 1 < beats.size():
			want = str((beats[i + 1] as Dictionary).get("id", ""))
		if nxt != want:
			chain += "%d:%s≠%s " % [i, str(nxt), str(want)]
	_report("10 幕 next 链首尾相连（末幕 next=null）", chain == "", chain)

	# 在场口径：entries 里每个非空 speaker（拜登 = 玩家）必须是本幕摆出来的人。
	var missing: String = ""
	for b: Variant in beats:
		var beat: Dictionary = b as Dictionary
		var cast: Array[String] = []
		for key: String in ["npc"]:
			var nid: String = str(beat.get(key, ""))
			if nid != "":
				cast.append(_npc_name(nid))
		var ex: Variant = beat.get("extras", null)
		if ex is Array:
			for e: Variant in ex as Array:
				cast.append(_npc_name(str((e as Dictionary).get("npc", ""))))
		for e: Variant in beat.get("entries", []) as Array:
			var who: String = str((e as Dictionary).get("speaker", ""))
			if who == "" or who == "拜登":
				continue
			if not cast.has(who):
				missing += "%s:%s " % [str(beat.get("id", "")), who]
	_report("每个说话人都在场（拜登=玩家除外）", missing == "", missing)


func _npc_name(id: String) -> String:
	var d: Dictionary = Chapter3Story._npc_defs.get(id, {}) as Dictionary
	return str(d.get("name", ""))


# ---- 2. 跑一遍 -----------------------------------------------------------

func _run() -> void:
	_report("未启动前导演不启动", not Chapter3Story.is_active(),
			"active=%s" % Chapter3Story.is_active())

	Chapter3Story.begin(0)
	await _tick()
	_report("begin() 后章节启动", Chapter3Story.is_active(),
			"active=%s" % Chapter3Story.is_active())
	_report("begin() 后发 ch3_dragon_king 任务并自动追踪",
			QuestLog.has(QID) and QuestLog.is_tracked(QID),
			"has=%s tracked=%s" % [QuestLog.has(QID), QuestLog.tracked_id()])
	_report("第一幕=奇斯送密函", _beat_id() == "ch3_tavern_chiss", "beat=%s" % _beat_id())

	await _mount(WORLD)
	var p0: Node = await _await_panel()
	_report("酒馆播第 1 幕（奇斯：贤者之石与超古代生物）",
			p0 != null and _beat_id() == "ch3_tavern_chiss",
			"beat=%s panel=%s" % [_beat_id(), p0 != null])
	_report("第 1 幕摆出奇斯",
			_npc_present("broker_chiss"), "chiss=%s" % _npc_present("broker_chiss"))
	await _close_current(p0)
	var p1: Node = await _await_panel()
	_report("接第 2 幕（西蒙：带我去你们的矿井）",
			p1 != null and _beat_id() == "ch3_tavern_simon",
			"beat=%s panel=%s" % [_beat_id(), p1 != null])
	await _close_current(p1)
	await _tick()
	_report("下一幕=矿道入口（等玩家走去）",
			_beat_id() == "ch3_mine_entrance", "beat=%s" % _beat_id())

	await _mount(MINE_ENT)
	var p2: Node = await _await_panel()
	_report("矿道入口播第 3 幕（西蒙：来这边）",
			p2 != null and _beat_id() == "ch3_mine_entrance",
			"beat=%s panel=%s" % [_beat_id(), p2 != null])
	await _close_current(p2)
	await _tick()
	_report("下一幕=矿井（等玩家下矿）", _beat_id() == "ch3_mine_slime", "beat=%s" % _beat_id())

	await _mount(MINE)
	var p3: Node = await _await_panel()
	_report("矿井播第 4 幕（史莱姆 → 裂隙传送门）",
			p3 != null and _beat_id() == "ch3_mine_slime",
			"beat=%s panel=%s" % [_beat_id(), p3 != null])
	await _close_current(p3)
	# 下一幕是 travel：打钩 + 开裂隙，但**不**替玩家换场景（要玩家自己踩门进去）。
	await _tick()
	_report("travel 结束后仍留在矿井（等玩家踩裂隙门）",
			_scene_path() == MINE, "scene=%s" % _scene_path())
	_report("裂隙门已打开（Chapter3Story.is_rift_open）",
			Chapter3Story.is_rift_open(), "open=%s" % Chapter3Story.is_rift_open())
	var gate: Node = get_tree().current_scene.get_node_or_null("Doors/LairGate") if get_tree().current_scene != null else null
	_report("矿井里有裂隙门 Doors/LairGate，且已启用监听",
			gate != null and bool(gate.get("monitoring")),
			"gate=%s monitoring=%s" % [gate != null, gate.get("monitoring") if gate else "-"])
	_report("裂隙门通向龙巢",
			gate != null and str(gate.get("target_scene")) == LAIR,
			"target=%s" % (gate.get("target_scene") if gate else "-"))

	await _mount(LAIR)
	var p4: Node = await _await_panel(240)
	_report("龙巢播第 6 幕（与爱德华会合）",
			p4 != null and _beat_id() == "ch3_lair_edward",
			"beat=%s panel=%s" % [_beat_id(), p4 != null])
	_report("这一幕摆出爱德华与卡兹",
			_npc_present("dwarf_war_edward") and _npc_present("ancient_kaz"),
			"edward=%s kaz=%s" % [_npc_present("dwarf_war_edward"), _npc_present("ancient_kaz")])
	await _close_current(p4)
	var p5: Node = await _await_panel()
	_report("接第 7 幕（龙醒 / 林格登场）",
			p5 != null and _beat_id() == "ch3_lair_awaken",
			"beat=%s panel=%s" % [_beat_id(), p5 != null])
	_report("这一幕摆出林格", _npc_present("knight_ringe"),
			"ringe=%s" % _npc_present("knight_ringe"))
	await _close_current(p5)
	var p6: Node = await _await_panel()
	_report("接第 8 幕（林格举圣剑）",
			p6 != null and _beat_id() == "ch3_lair_holy",
			"beat=%s panel=%s" % [_beat_id(), p6 != null])
	await _close_current(p6)
	# 白幕 3 秒（淡入 0.35 + 停 3 + 淡出 0.9），之后才推进到"醒来"那一幕。
	var p7: Node = await _await_panel(700)
	_report("白幕后接第 9 幕（醒来 / 与龙的皇帝告别）",
			p7 != null and _beat_id() == "ch3_lair_after",
			"beat=%s panel=%s" % [_beat_id(), p7 != null])
	_report("这一幕摆出龙的皇帝（特蕾西亚）",
			_npc_present("dragon_theresia"),
			"theresia=%s" % _npc_present("dragon_theresia"))
	await _close_current(p7)
	await _tick()
	_report("下一幕=回酒馆收尾", _beat_id() == "ch3_tavern_epilogue", "beat=%s" % _beat_id())

	await _mount(WORLD)
	var p8: Node = await _await_panel()
	_report("酒馆播末幕（尾声 / 孩子取名）",
			p8 != null and _beat_id() == "ch3_tavern_epilogue",
			"beat=%s panel=%s" % [_beat_id(), p8 != null])
	await _close_current(p8)
	await _tick()
	await _tick()

	_report("走完 10 幕 → 任务完成", QuestLog.is_complete(QID),
			"complete=%s" % QuestLog.is_complete(QID))
	_report("走完 10 幕 → 导演收尾", not Chapter3Story.is_active(),
			"active=%s" % Chapter3Story.is_active())
	_report("终章标记 game_finished", Chapter3Story.game_finished,
			"finished=%s" % Chapter3Story.game_finished)
	_report("收尾后不再追踪第三章", not QuestLog.is_tracked(QID),
			"tracked=%s" % QuestLog.tracked_id())


# ---- 工具 ---------------------------------------------------------------

func _beat_id() -> String:
	return str(Chapter3Story.current_beat().get("id", ""))


func _npc_present(id: String) -> bool:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return true
	return false


func _scene_path() -> String:
	var s: Node = get_tree().current_scene
	return s.scene_file_path if s != null else ""


func _await_scene(path: String, max_frames: int = 240) -> bool:
	for i: int in max_frames:
		if _scene_path() == path:
			return true
		await get_tree().process_frame
	return _scene_path() == path


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


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
