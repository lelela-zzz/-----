extends Node
## 第二章「月痕将熄」手动测试窗口。
##
## 运行： "<godot>" --path . res://tests/chapter2_test.tscn
##
## 与第一章测试窗口同一套思路：**不接管场景**，走真实 change_scene_to_file，
## 让传送门 / 地图 / 旅行都可用；本节点在 _ready 里把 current_scene 置空后常驻，
## 切场景不会把自己和 HUD 一起释放。
##
## 流程：启动即自动 begin(0) 并切到酒馆 —— 俄莉斯登场，玩家走过去按 E（或点
## 「与当前人物交谈」）开始第二章。后续顺序是：酒馆 4 幕 → 雪山会合/雪崩 →
## 泉水维兹/净化/取石/宁芙 → 醒来 → 回城伊蕾娜/伊织。F1 可隐藏面板。

const SCENES: Dictionary = {
	"酒馆": "res://scenes/world.tscn",
	"雪山": "res://scenes/snow_mountain.tscn",
	"泉水": "res://scenes/spring.tscn",
	"灰空间": "res://scenes/dark_space.tscn",
}
const PLACE_NAME: Dictionary = {
	"world": "酒馆", "snow_mountain": "雪山", "spring": "泉水",
	"dark_space": "灰空间", "travel": "移动",
}
const QID: String = "ch2_moon"

var _hud: Control = null
var _panel: Panel = null
var _btn_root: Control = null
var _status: Label = null
var _steps_label: Label = null
var _note: Label = null
var _switching: bool = false
var _ui_visible: bool = true


func _ready() -> void:
	CustomerSpawner.force_disable = true
	QuestLog.reset()
	ChapterStory.reset()                 # 第一章不参与
	Chapter2Story.reset()
	Chapter2Story.auto_advance = true
	Chapter2Story.wait_for_talk = true   # 正式流程：摆人、等玩家按 E 交谈
	Story.stage = StoryDirector.Stage.OPEN
	SideStory._story_day = 2
	_build_hud()
	# 关键：本节点不再是 current_scene → 之后 change_scene_to_file 不会释放它，HUD 常驻。
	get_tree().current_scene = null
	await get_tree().process_frame
	await _start_chapter2()
	_set_note("第二章已启动：在酒馆找俄莉斯，走过去按 E 交谈（F1 隐藏面板）")


# ---- HUD ------------------------------------------------------------------

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "TestHud"
	layer.layer = 128
	add_child(layer)

	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	_btn_root = Control.new()
	_btn_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_btn_root)

	var panel: Panel = UiStyle.panel(UiStyle.PANEL_BG, UiStyle.LEATHER_LIGHT)
	panel.position = Vector2(8, 8)
	panel.size = Vector2(600, 356)
	_hud.add_child(panel)
	_panel = panel

	var title: Label = UiStyle.label("第二章 · 月痕将熄 · 测试窗口", UiStyle.FIRE_CORE)
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)

	_status = UiStyle.label("", UiStyle.LINEN, UiStyle.BODY_SIZE)
	_status.position = Vector2(16, 32)
	_status.size = Vector2(568, 88)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)

	_steps_label = UiStyle.label("", UiStyle.LINEN_DARK, 9)
	_steps_label.position = Vector2(16, 124)
	_steps_label.size = Vector2(568, 224)
	_steps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_steps_label)

	_add_button("▶ 与当前人物交谈",  Vector2(900, 8),   func(): _talk_current())
	_add_button("切到 酒馆",        Vector2(900, 46),  func(): _go("酒馆"))
	_add_button("切到 雪山",        Vector2(900, 80),  func(): _go("雪山"))
	_add_button("切到 泉水",        Vector2(900, 114), func(): _go("泉水"))
	_add_button("解锁泉水 (测试)",   Vector2(900, 156), func(): _unlock_spring())
	_add_button("推进对话 (E)",     Vector2(900, 194), func(): _tap_key(KEY_E))
	_add_button("跳过对话 (Esc)",   Vector2(900, 228), func(): _tap_key(KEY_ESCAPE))
	_add_button("切到 灰空间",       Vector2(900, 302), func(): _go("灰空间"))
	_add_button("隐藏/显示面板 (F1)", Vector2(900, 340), func(): _toggle_ui())
	_add_button("重置（回第二章开始）", Vector2(900, 378), func(): _reset_chapter())

	var help: Label = UiStyle.label("走到人物身边按 E 交谈 · 可踩门 / 按 M 远行", UiStyle.FIRE_CORE, UiStyle.BODY_SIZE)
	help.position = Vector2(8, 368)
	_hud.add_child(help)
	_note = UiStyle.label("", UiStyle.GOLD, UiStyle.BODY_SIZE)
	_note.position = Vector2(8, 388)
	_note.size = Vector2(860, 20)
	_hud.add_child(_note)


func _add_button(text: String, pos: Vector2, cb: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(210, 30)
	b.theme = UiStyle.theme()
	b.add_theme_font_override("font", UiStyle.theme().default_font)
	b.add_theme_font_size_override("font_size", UiStyle.BODY_SIZE)
	b.pressed.connect(cb)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn_root.add_child(b)


func _toggle_ui() -> void:
	_ui_visible = not _ui_visible
	if _panel != null:
		_panel.visible = _ui_visible
	if _btn_root != null:
		_btn_root.visible = _ui_visible
	_set_note("面板已%s（F1 切换）" % ("显示" if _ui_visible else "隐藏"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		_toggle_ui()


# ---- 交互 ----------------------------------------------------------------

## 启动 / 重置：复位第二章导演，从第 0 幕开始，并切到酒馆。
func _start_chapter2() -> void:
	Chapter2Story.reset()
	Chapter2Story.begin(0)
	await _go_to(SCENES["酒馆"])


func _go(key: String) -> void:
	if _switching:
		return
	await _go_to(SCENES[key])
	var why: String = _why_not_here()
	if why == "":
		_set_note("已前往：%s（本幕可在此推进）" % key)
	else:
		_set_note("已前往：%s —— %s" % [key, why])


func _go_to(path: String) -> void:
	_switching = true
	await _close_modals()
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	_switching = false


## 本幕在当前场景推不动的原因（空 = 能推）。
func _why_not_here() -> String:
	if not Chapter2Story.is_active() or Chapter2Story.is_done():
		return ""
	var b: Dictionary = Chapter2Story.current_beat()
	var place: String = str(b.get("place", ""))
	if place == "travel" or _beat_playable_here(b):
		return ""
	if Chapter2Story.awaiting_talk():
		return ""
	return "本幕在「%s」，需先去那里（%s）" % [_place_name(place), str(b.get("id", ""))]


func _talk_current() -> void:
	if _switching:
		return
	if _find_modal() != null:
		_set_note("已有对话在播，先按 E/Esc 关掉")
		return
	if Chapter2Story.is_done():
		_set_note("章节已结束（可点「重置」重来）")
		return
	if not Chapter2Story.is_active():
		_set_note("章节未启动，请点「重置（回第二章开始）」")
		return
	var b: Dictionary = Chapter2Story.current_beat()
	var nid: String = str(b.get("npc", ""))
	var place: String = str(b.get("place", ""))
	if nid == "":
		_set_note("本幕没有可交谈的人物（旁白幕会自动播放）")
		return
	if not Chapter2Story.awaiting_talk():
		_set_note("本幕在「%s」，请先切到该场景（人物才会登场）" % _place_name(place))
		return
	var npc: Node = _find_npc(nid)
	if npc == null:
		_set_note("没找到本幕人物 %s，请重切场景" % nid)
		return
	npc.call("talk")


func _unlock_spring() -> void:
	SideStory.unlock("spring")
	_set_note("已解锁「泉水」（测试用：正式由第二章第 8 幕 travel 解锁）")


func _reset_chapter() -> void:
	if _switching:
		return
	QuestLog.reset()
	await _start_chapter2()
	_set_note("已重置：回到第二章第 1 幕（酒馆俄莉斯）")


func _tap_key(keycode: int) -> void:
	_push_key(keycode)


# ---- 实时状态 -------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_status()


func _update_status() -> void:
	if _status == null:
		return
	var lines: Array[String] = []
	if not Chapter2Story.is_active() and not Chapter2Story.is_done():
		lines.append("状态：未启动")
		lines.append("点「重置（回第二章开始）」启动第二章")
		_status.text = "\n".join(lines)
		_steps_label.text = "任务：（尚未建立）"
		return

	var active: bool = Chapter2Story.is_active()
	var done: bool = Chapter2Story.is_done()
	var total: int = Chapter2Story.beat_count()
	var idx: int = Chapter2Story.index()
	var beat: Dictionary = Chapter2Story.current_beat()
	var bid: String = str(beat.get("id", "—"))
	var place: String = str(beat.get("place", "—"))
	var state: String = "已结束" if done else ("进行中" if active else "未开始")
	var here: String
	if Chapter2Story.awaiting_talk():
		here = "等交谈（走过去按 E）"
	elif _beat_playable_here(beat):
		here = "可播"
	else:
		here = "需去「%s」" % _place_name(place)

	lines.append("状态：%s　｜　本幕：%s" % [state, here])
	lines.append("当前幕：%s（第 %d/%d 幕）" % [bid, idx + 1, total])
	lines.append("场景：%s → 当前 %s　｜　泉水：%s" % [
		_place_name(place), _current_scene_name(),
		"✓" if SideStory.is_unlocked("spring") else "○"])
	_status.text = "\n".join(lines)
	_steps_label.text = _build_steps()


func _beat_playable_here(beat: Dictionary) -> bool:
	if beat.is_empty():
		return false
	var brew: Variant = beat.get("brew", null)
	if brew is Dictionary:
		return Inventory.has(str((brew as Dictionary).get("wine", "")))
	var place: String = str(beat.get("place", ""))
	if place == "travel":
		return true
	return _current_scene_path() == str(Chapter2Story.PLACE_SCENE.get(place, ""))


func _build_steps() -> String:
	var q: Dictionary = QuestLog.quest(QID)
	if q.is_empty():
		return "（任务尚未建立）"
	var lines: Array[String] = ["任务步骤："]
	var steps: Array = q.get("steps", [])
	if steps.is_empty():
		lines.append("  （暂无步骤）")
	for s: Variant in steps:
		var d: Dictionary = s as Dictionary
		var mark: String = "✓" if bool(d.get("done", false)) else "○"
		lines.append("  %s %s" % [mark, str(d.get("text", ""))])
	return "\n".join(lines)


func _place_name(place: String) -> String:
	return str(PLACE_NAME.get(place, place))


func _current_scene_path() -> String:
	var s: Node = get_tree().current_scene
	return s.scene_file_path if s != null else ""


func _current_scene_name() -> String:
	var p: String = _current_scene_path()
	for k: String in SCENES:
		if SCENES[k] == p:
			return k
	return p if p != "" else "—"


# ---- 工具 -----------------------------------------------------------------

func _find_npc(id: String) -> Node:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return n
	return null


func _find_modal() -> Node:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n is UiPanel:
			return n
	return null


func _close_modals() -> void:
	Chapter2Story.abort_current_beat()
	for _i: int in 30:
		var p: Node = _find_modal()
		if p == null:
			return
		if p.has_method("close"):
			p.call("close")
		await get_tree().process_frame
		await get_tree().process_frame


func _push_key(keycode: int) -> void:
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


func _set_note(text: String) -> void:
	if _note != null:
		_note.text = text
	print("[chapter2_test] %s" % text)
