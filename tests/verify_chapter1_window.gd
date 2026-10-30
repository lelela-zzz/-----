extends Node
## 回归验收：第一章测试窗口（"人物登场→玩家去交谈"版）。
## 覆盖：传送门/M 地图可用、凯瑟琳接取、哈特菲利亚在酒馆外→交谈→
## 奇斯/俄莉斯在酒馆内依次登场交谈、整章可跑完、无第二个主角。

var tester: Node = null
var passed: int = 0
var failed: int = 0

const PLACE_KEY := {
	"world": "酒馆", "tavern_exterior": "酒馆门口", "village": "集市",
	"mine_entrance": "矿道入口", "mine": "矿井",
}


func _ready() -> void:
	await get_tree().process_frame
	tester = (load("res://tests/chapter1_test.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(tester)
	await wait(80)

	# 1) 启动在集市、待接取、凯瑟琳在场、传送门/地图可用
	_check("启动在集市", current_scene_path().contains("village"), current_scene_path())
	_check("启动时未接取委托", not Story.snow_started, "snow_started=%s" % Story.snow_started)
	_check("启动时章节未启动", not ChapterStory.is_active(), "active=%s" % ChapterStory.is_active())
	_check("凯瑟琳在集市中", find_npc("market_catherine") != null, str(find_npc("market_catherine")))
	_check("传送门未被禁用", door_enabled(), "door=%s" % str(find_door()))
	_check("Story 未被 force_disable（地图/对话可用）", not StoryDirector.force_disable, "force_disable=%s" % StoryDirector.force_disable)
	_check("等待交谈模式开启", ChapterStory.wait_for_talk, "wait_for_talk=%s" % ChapterStory.wait_for_talk)

	# 2) M 地图
	push_key(KEY_M)
	await wait(14)
	var mp: Node = find_modal()
	_check("按 M 打开地图", mp != null and mp is MapPanel, str(mp))
	await close_modal_only()
	await wait(6)

	# 3) 凯瑟琳 → 现有菜单 → 接取
	tester._talk_catherine()
	await wait(14)
	_check("与凯瑟琳交谈打开对话", find_modal() != null, str(find_modal()))
	await close_current(find_modal())
	await wait(12)
	var cp: Node = find_choice_panel()
	_check("弹出集市管理处菜单", cp != null, str(cp))
	if cp != null:
		cp.call("_move", 1)
		cp.call("_confirm")
	await wait(16)
	_check("已正式接取委托", Story.snow_started, "snow_started=%s" % Story.snow_started)
	_check("接取后第一幕=哈特菲利亚", beat_id() == "ch1_tavern_hartfilia", beat_id())
	await drain_modals()   # 接取时播的委托台词

	# 4) 酒馆门口：哈特菲利亚登场，玩家交谈才开口
	tester._go("酒馆门口")
	await wait(55)
	_check("到达酒馆外（tavern_exterior）", current_scene_path().contains("tavern_exterior"), current_scene_path())
	_check("哈特菲利亚已在酒馆外登场", find_npc("explorer_lucy") != null, str(find_npc("explorer_lucy")))
	_check("此时尚未自动弹对话（等玩家交谈）", find_modal() == null and ChapterStory.awaiting_talk(),
			"awaiting=%s modal=%s" % [ChapterStory.awaiting_talk(), str(find_modal())])
	talk_beat()
	await wait(12)
	_check("与哈特菲利亚交谈后出对话", find_modal() != null, str(find_modal()))
	await close_current(find_modal())
	await wait(10)

	# 5) 进酒馆：奇斯登场 → 交谈
	tester._go("酒馆")
	await wait(55)
	_check("到酒馆后第二幕=奇斯", beat_id() == "ch1_chiss_rune", beat_id())
	_check("奇斯已在酒馆登场", find_npc("broker_chiss") != null, str(find_npc("broker_chiss")))
	talk_beat()
	await wait(12)
	_check("与奇斯交谈后出对话", find_modal() != null, str(find_modal()))
	await close_current(find_modal())
	await wait(12)

	# 6) 俄莉斯登场 → 交谈
	_check("俄莉斯已在酒馆登场", find_npc("thief_eris") != null, str(find_npc("thief_eris")))
	talk_beat()
	await wait(12)
	_check("与俄莉斯交谈后出对话", find_modal() != null, str(find_modal()))
	await close_current(find_modal())
	await wait(10)

	# 7) 走完余下各幕
	var ok: bool = await drive_all()
	_check("整章可跑完", ok and ChapterStory.is_done(),
			"done=%s idx=%d beat=%s" % [ChapterStory.is_done(), ChapterStory.index(), beat_id()])
	_check("跑完后只有一个主角", get_tree().get_nodes_in_group("player").size() == 1,
			"players=%d" % get_tree().get_nodes_in_group("player").size())

	# 8) 重置
	tester._reset_chapter()
	await wait(70)
	_check("重置后回到待接取", not Story.snow_started and not ChapterStory.is_active(),
			"snow_started=%s active=%s" % [Story.snow_started, ChapterStory.is_active()])
	_check("重置后在集市且有凯瑟琳", current_scene_path().contains("village") and find_npc("market_catherine") != null, current_scene_path())
	_check("重置后只有一个主角", get_tree().get_nodes_in_group("player").size() == 1,
			"players=%d" % get_tree().get_nodes_in_group("player").size())

	print("[verify] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


## 与"当前幕该交谈的人物"对话。
func talk_beat() -> void:
	var b: Dictionary = ChapterStory.current_beat()
	var npc: Node = find_npc(str(b.get("npc", "")))
	if npc != null:
		npc.call("talk")


func drive_all() -> bool:
	for _step: int in 200:
		if ChapterStory.is_done():
			return true
		var p: Node = find_modal()
		if p != null:
			await close_current(p)
			continue
		if not ChapterStory.is_active():
			return false
		var b: Dictionary = ChapterStory.current_beat()
		var place: String = str(b.get("place", ""))
		var brew: Variant = b.get("brew", null)
		if brew is Dictionary:
			Inventory.add(str((brew as Dictionary).get("wine", "")), 1)
			await wait(14)
			continue
		if place != "travel":
			var want: String = str(ChapterStory.PLACE_SCENE.get(place, ""))
			if current_scene_path() != want:
				tester._go(str(PLACE_KEY.get(place, "酒馆")))
				await wait(52)
				continue
		if ChapterStory.awaiting_talk():
			talk_beat()
			await wait(14)
			continue
		await wait(24)
	return ChapterStory.is_done()


func close_current(panel: Node) -> void:
	var guard: int = 0
	while is_instance_valid(panel) and not panel.is_queued_for_deletion() and guard < 200:
		push_key(KEY_E)
		await get_tree().process_frame
		await get_tree().process_frame
		guard += 1
	await wait(2)


func drain_modals() -> void:
	for _i: int in 60:
		var p: Node = find_modal()
		if p == null:
			return
		await close_current(p)


func close_modal_only() -> void:
	var p: Node = find_modal()
	if p != null and p.has_method("close"):
		p.call("close")
	await wait(4)


func beat_id() -> String:
	return str(ChapterStory.current_beat().get("id", ""))


func find_modal() -> Node:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n is UiPanel:
			return n
	return null


func find_choice_panel() -> Node:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n is ChoicePanel:
			return n
	return null


func find_npc(id: String) -> Node:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return n
	return null


func find_door() -> Node:
	var s: Node = get_tree().current_scene
	return _find_door(s) if s != null else null


func _find_door(n: Node) -> Node:
	if n is DoorArea:
		return n
	for c: Node in n.get_children():
		var r: Node = _find_door(c)
		if r != null:
			return r
	return null


func door_enabled() -> bool:
	var d: Node = find_door()
	return d != null and bool(d.get("monitoring"))


func current_scene_path() -> String:
	var s: Node = get_tree().current_scene
	return s.scene_file_path if s != null else ""


func push_key(k: int) -> void:
	var d: InputEventKey = InputEventKey.new()
	d.keycode = k
	d.pressed = true
	get_viewport().push_input(d)
	var u: InputEventKey = InputEventKey.new()
	u.keycode = k
	u.pressed = false
	get_viewport().push_input(u)


func wait(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
