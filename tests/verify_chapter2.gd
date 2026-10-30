extends Node
## 第二章「月痕将熄」剧情导演验收（Chapter2Story）。
##   1) data/story_chapter2.json 骨架：16 幕、每幕 id/place/entries、next 链首尾相连；
##   2) 酒馆连播 4 幕（俄莉斯委托 → EMT 缥色符文 → 俄莉斯教炼水 → 炼成）；
##   3) travel 幕跳过并存档 → 雪山（EMT 会合 → 雪崩/绯村）；
##   4) travel 解锁泉水 → 泉水（维兹 → 净化 → 取魔导石 → 宁芙/林格 → 醒来）；
##   5) travel 回城 → 酒馆（伊蕾娜/伊卡洛斯 → 伊织）→ 16 幕走完、任务完成、导演收尾。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_chapter2.tscn --quit-after 9000

const WORLD: String = "res://scenes/world.tscn"
const SNOW: String = "res://scenes/snow_mountain.tscn"
const SPRING: String = "res://scenes/spring.tscn"

const QID: String = "ch2_moon"

var passed: int = 0
var failed: int = 0
var _scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	ChapterStory.reset()                 # 第一章不参与本用例
	Chapter2Story.wait_for_talk = false  # 自动播（talk 幕也直接演），便于 headless 跑通
	Chapter2Story.reset()
	QuestLog.reset()
	await get_tree().process_frame

	_check_data()
	await _run()

	QuestLog.reset()
	print("[chapter2] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 数据 -------------------------------------------------------------

func _check_data() -> void:
	var beats: Array = Chapter2Story._beats
	_report("第二章数据 16 幕", beats.size() == 16, "beats=%d" % beats.size())

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
		if place != "travel" and not Chapter2Story.PLACE_SCENE.has(place):
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
	_report("16 幕 next 链首尾相连（末幕 next=null）", chain == "", chain)


# ---- 2. 跑一遍 -----------------------------------------------------------

func _run() -> void:
	_report("未启动前导演不启动", not Chapter2Story.is_active(),
			"active=%s" % Chapter2Story.is_active())

	Chapter2Story.begin(0)
	await _tick()
	_report("begin() 后章节启动", Chapter2Story.is_active(),
			"active=%s" % Chapter2Story.is_active())
	_report("begin() 后发 ch2_moon 任务并自动追踪",
			QuestLog.has(QID) and QuestLog.is_tracked(QID),
			"has=%s tracked=%s" % [QuestLog.has(QID), QuestLog.tracked_id()])
	_report("第一幕=俄莉斯委托", _beat_id() == "ch2_tavern_eris", "beat=%s" % _beat_id())

	# 酒馆：连播 4 幕
	await _mount(WORLD)
	var p0: Node = await _await_panel()
	_report("酒馆播第 1 幕（俄莉斯委托找魔导石）",
			p0 != null and _beat_id() == "ch2_tavern_eris",
			"beat=%s panel=%s" % [_beat_id(), p0 != null])
	await _close_current(p0)
	var p1: Node = await _await_panel()
	_report("接第 2 幕（EMT 带来缥色符文）",
			p1 != null and _beat_id() == "ch2_tavern_emt",
			"beat=%s panel=%s" % [_beat_id(), p1 != null])
	await _close_current(p1)
	var p2: Node = await _await_panel()
	_report("接第 3 幕（俄莉斯教用符文炼生命之水）",
			p2 != null and _beat_id() == "ch2_eris_lifewater",
			"beat=%s panel=%s" % [_beat_id(), p2 != null])
	await _close_current(p2)
	var p3: Node = await _await_panel()
	_report("接第 4 幕（炼成生命之水）",
			p3 != null and _beat_id() == "ch2_brew_lifewater",
			"beat=%s panel=%s" % [_beat_id(), p3 != null])
	await _close_current(p3)
	await _tick()
	_report("travel 跳过 → 下一幕=雪山与 EMT 会合",
			_beat_id() == "ch2_snow_meet_emt", "beat=%s" % _beat_id())

	# 雪山：会合 → 雪崩
	await _mount(SNOW)
	var p4: Node = await _await_panel()
	_report("雪山播第 6 幕（与 EMT 会合）",
			p4 != null and _beat_id() == "ch2_snow_meet_emt",
			"beat=%s panel=%s" % [_beat_id(), p4 != null])
	await _close_current(p4)
	var p5: Node = await _await_panel()
	_report("接第 7 幕（雪崩 / 绯村土龙闪）",
			p5 != null and _beat_id() == "ch2_snow_avalanche",
			"beat=%s panel=%s" % [_beat_id(), p5 != null])
	await _close_current(p5)
	await _tick()
	_report("travel 结算：解锁「泉水」", SideStory.is_unlocked("spring"),
			"unlocked=%s" % SideStory.is_unlocked("spring"))
	_report("travel 幕任务步打钩（前往泉水）",
			_step_done("前往雪山深处的泉水"), "steps=%s" % str(_step_texts()))
	_report("解锁后下一幕=泉水维兹",
			_beat_id() == "ch2_spring_wiz", "beat=%s" % _beat_id())

	# 泉水：维兹 → 净化 → 取石 → 宁芙/林格 → 醒来
	await _mount(SPRING)
	var p6: Node = await _await_panel()
	_report("泉水播第 9 幕（维兹）",
			p6 != null and _beat_id() == "ch2_spring_wiz",
			"beat=%s panel=%s" % [_beat_id(), p6 != null])
	await _close_current(p6)
	var p7: Node = await _await_panel()
	_report("接第 10 幕（净化泉水）",
			p7 != null and _beat_id() == "ch2_spring_purify",
			"beat=%s panel=%s" % [_beat_id(), p7 != null])
	await _close_current(p7)
	var p8: Node = await _await_panel()
	_report("接第 11 幕（取出两块魔导石）",
			p8 != null and _beat_id() == "ch2_spring_take_stone",
			"beat=%s panel=%s" % [_beat_id(), p8 != null])
	await _close_current(p8)
	var p9: Node = await _await_panel()
	_report("接第 12 幕（宁芙 / 林格现身）",
			p9 != null and _beat_id() == "ch2_void_nymph",
			"beat=%s panel=%s" % [_beat_id(), p9 != null])
	await _close_current(p9)
	var p10: Node = await _await_panel()
	_report("接第 13 幕（泉边醒来，给 EMT 魔导石）",
			p10 != null and _beat_id() == "ch2_spring_wake",
			"beat=%s panel=%s" % [_beat_id(), p10 != null])
	await _close_current(p10)
	await _tick()
	_report("travel 跳过 → 下一幕=回城伊蕾娜",
			_beat_id() == "ch2_tavern_elaina", "beat=%s" % _beat_id())

	# 酒馆：伊蕾娜/伊卡洛斯 → 伊织 → 完
	await _mount(WORLD)
	var p11: Node = await _await_panel()
	_report("酒馆播第 15 幕（伊蕾娜入伙 / 伊卡洛斯苏醒）",
			p11 != null and _beat_id() == "ch2_tavern_elaina",
			"beat=%s panel=%s" % [_beat_id(), p11 != null])
	_report("这一幕把伊蕾娜和伊卡洛斯都摆出来",
			_npc_present("brewer_greym") and _npc_present("reception_icarus"),
			"elaina=%s icarus=%s" % [_npc_present("brewer_greym"), _npc_present("reception_icarus")])
	await _close_current(p11)
	# 末幕带 wait_day：伊织是"第二天晌午"来的，同一天内不得登场。
	await _tick()
	var early: Node = await _await_panel(20)
	_report("wait_day：同一天内伊织不登场、无面板",
			early == null and not _npc_present("bartender_iori")
					and not Chapter2Story.is_done(),
			"panel=%s iori=%s" % [early != null, _npc_present("bartender_iori")])
	# 走真实跨天链路：时钟宵禁 roll over（23:00 → day+1 → 次日 07:30）。
	# day_changed 发出后导演的每帧 _pump 会自然放行末幕。
	# 走真实跨天链路：时钟宵禁 roll over（23:00 → day+1 → 次日 07:30）。
	# day_changed 发出后导演的每帧 _pump 会自然放行末幕。
	var clock: GameClock = get_tree().current_scene.get_node_or_null("Clock") as GameClock
	if clock != null:
		clock._roll_over_curfew()
	await _tick()
	var p12: Node = await _await_panel()
	_report("跨天后接末幕（伊织应聘调酒师）",
			p12 != null and _beat_id() == "ch2_tavern_iori",
			"beat=%s panel=%s" % [_beat_id(), p12 != null])
	await _close_current(p12)
	await _tick()
	await _tick()

	_report("走完 16 幕 → 任务完成", QuestLog.is_complete(QID),
			"complete=%s" % QuestLog.is_complete(QID))
	_report("走完 16 幕 → 导演收尾", not Chapter2Story.is_active(),
			"active=%s" % Chapter2Story.is_active())
	_report("收尾后不再追踪第二章", not QuestLog.is_tracked(QID),
			"tracked=%s" % QuestLog.tracked_id())


# ---- 工具 ---------------------------------------------------------------

func _beat_id() -> String:
	return str(Chapter2Story.current_beat().get("id", ""))


func _step_done(prefix: String) -> bool:
	var q: Dictionary = QuestLog.quest(QID)
	for s: Variant in q.get("steps", []):
		var d: Dictionary = s as Dictionary
		if str(d.get("text", "")).begins_with(prefix):
			return bool(d.get("done", false))
	return false


func _step_texts() -> Array[String]:
	var out: Array[String] = []
	var q: Dictionary = QuestLog.quest(QID)
	for s: Variant in q.get("steps", []):
		var d: Dictionary = s as Dictionary
		out.append(("✓" if bool(d.get("done", false)) else "○") + str(d.get("text", "")))
	return out


func _npc_present(id: String) -> bool:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return true
	return false


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
