extends Node
## 第一章 · 「人物登场等待交谈」的离场/回场验收。
##
## 病根：对话面板和摆进场景的 NPC 都挂在当前场景下，玩家一旦在"等人交谈"时踩门，
## 面板和人都随旧场景被释放；但 ChapterStory 的 _playing / _awaiting_talk 是
## autoload 变量，不会跟着清。留成 true 会让 _pump 永久早退 —— 剧情彻底卡死：
## 下一幕该登场的人永远不出现、travel 幕永远不结算（任务栏「前往矿道入口」永远 ○）。
##
## 本用例就把这条路走一遍：登场 → 不交谈直接走人 → 回来必须还能重新登场。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_ch1_leave_talk.tscn --quit-after 4000

const WORLD: String = "res://scenes/world.tscn"
const VILLAGE: String = "res://scenes/village.tscn"

var passed: int = 0
var failed: int = 0
var _scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	ChapterStory.wait_for_talk = true     # 本用例专测"摆人等交谈"这条路
	ChapterStory.auto_advance = true
	QuestLog.reset()
	ChapterStory.reset()
	await get_tree().process_frame

	await _run()

	ChapterStory.reset()
	QuestLog.reset()
	print("[leave_talk] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _run() -> void:
	# 从第 3 幕（奇斯·酒馆）起，省掉前面两条同构的幕
	ChapterStory.begin(2)
	await _tick()
	_report("从第 3 幕起（奇斯要绯色符文）", _beat_id() == "ch1_chiss_rune", "beat=%s" % _beat_id())

	await _mount(WORLD)
	_report("进酒馆：只摆人、不自动开口",
			ChapterStory.awaiting_talk() and _panel() == null,
			"awaiting=%s modal=%s" % [ChapterStory.awaiting_talk(), _panel() != null])
	_report("奇斯已登场", _npc_present("broker_chiss"), "")

	# 关键：不交谈，直接走人
	await _mount(VILLAGE)
	_report("离开后不再卡在等交谈（awaiting 归零）",
			not ChapterStory.awaiting_talk(), "awaiting=%s" % ChapterStory.awaiting_talk())
	_report("离开不算完成，幕序号没推进",
			_beat_id() == "ch1_chiss_rune" and ChapterStory.index() == 2,
			"beat=%s idx=%d" % [_beat_id(), ChapterStory.index()])
	_report("没交谈就不打钩", not _step_done("回银辉酒馆"),
			"steps=%s" % str(_step_texts()))

	# 回来：人必须重新登场，否则这条剧情就永远走不下去了
	await _mount(WORLD)
	_report("回到酒馆：奇斯重新登场",
			ChapterStory.awaiting_talk() and _npc_present("broker_chiss"),
			"awaiting=%s npc=%s" % [ChapterStory.awaiting_talk(), _npc_present("broker_chiss")])

	var npc: Node = _find_npc("broker_chiss")
	if npc != null:
		npc.call("talk")
	var p: Node = await _await_panel()
	_report("这次交谈能正常播本幕", p != null and _beat_id() == "ch1_chiss_rune",
			"panel=%s beat=%s" % [p != null, _beat_id()])
	await _close(p)
	await _tick()
	_report("谈完推进到下一幕（俄莉斯）", _beat_id() == "ch1_eris_permission",
			"beat=%s" % _beat_id())


# ---- 工具 ---------------------------------------------------------------

func _beat_id() -> String:
	return str(ChapterStory.current_beat().get("id", ""))


func _panel() -> Node:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n is UiPanel:
			return n
	return null


func _find_npc(id: String) -> Node:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return n
	return null


func _npc_present(id: String) -> bool:
	return _find_npc(id) != null


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


func _await_panel(max_frames: int = 40) -> Node:
	for i: int in max_frames:
		var p: Node = _panel()
		if p != null:
			return p
		await get_tree().process_frame
	return null


func _close(panel: Node) -> void:
	if panel == null:
		return
	var guard: int = 0
	while is_instance_valid(panel) and not panel.is_queued_for_deletion() and guard < 120:
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


func _step_done(prefix: String) -> bool:
	var q: Dictionary = QuestLog.quest("ch1_frost")
	for s: Variant in q.get("steps", []):
		var d: Dictionary = s as Dictionary
		if str(d.get("text", "")).begins_with(prefix):
			return bool(d.get("done", false))
	return false


func _step_texts() -> Array[String]:
	var out: Array[String] = []
	var q: Dictionary = QuestLog.quest("ch1_frost")
	for s: Variant in q.get("steps", []):
		var d: Dictionary = s as Dictionary
		out.append(("✓" if bool(d.get("done", false)) else "○") + str(d.get("text", "")))
	return out


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
