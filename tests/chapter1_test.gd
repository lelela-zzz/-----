extends Node
## 第一章「雾凇无虞」手动测试窗口（真实流程版）。
##
## 窗口模式运行（编辑器 F5 选本场景，或命令行）：
##   "<godot>" --path . res://tests/chapter1_test.tscn
##
## 设计：**不接管场景**，完全走游戏自带的 change_scene_to_file —— 传送门、地图远程移动、
## 旅行都恢复可用；本节点在 _ready 里把 current_scene 置空后常驻，切场景不会把自己
## 和 HUD 一起释放，所以 HUD 始终在。
##
## 流程：
##   1) 启动即在「集市」，凯瑟琳在场。走到她身边按 E（或点「① 与凯瑟琳交谈」），
##      进入**游戏现有的**集市管理处菜单，选「接取任务」正式接取（Story 原逻辑）。
##   2) 接取后，走进传送门 / 按 M 打开地图远程移动 / 点「切到 酒馆」——
##      进入该幕所在场景时 ChapterStory 自动播放本幕，该在场人物（哈特菲利亚等）由幕数据摆出。
##   3) 对话按 E 推进、Esc 跳过。
##
## 为什么改成这样：上一版为了防"重复主角"而禁用了传送门、又把 Story force_disable、
## 还把 auto_advance 关掉 —— 结果传送点全失效、地图用不了、进场景也不再推进剧情。
## 现在改用真实的场景切换，Godot 自己会释放旧场景，既不会重复主角，也不会挡住传送。

const SCENES: Dictionary = {
	"酒馆": "res://scenes/world.tscn",
	"酒馆门口": "res://scenes/tavern_exterior.tscn",
	"集市": "res://scenes/village.tscn",
	"矿道入口": "res://scenes/mine_entrance.tscn",
	"矿井": "res://scenes/mine.tscn",
}
const PLACE_NAME: Dictionary = {
	"world": "酒馆", "tavern_exterior": "酒馆门口", "village": "集市",
	"mine_entrance": "矿道入口", "mine": "矿井", "travel": "移动",
}
const QID: String = "ch1_frost"
const CATHERINE_ID: String = "market_catherine"

var _hud: Control = null
var _panel: Panel = null
var _btn_root: Control = null
var _status: Label = null
var _steps_label: Label = null
var _note: Label = null
var _switching: bool = false
## 面板是否显示。F1 切换 —— 相机贴地图边缘时玩家/本幕人物会落在屏幕右上角，
## 正好被按钮列盖住（矿道入口就是这个位置），必须能一键让开。
var _ui_visible: bool = true


func _ready() -> void:
	# 顾客关掉（免得随机客流干扰测试）；**Story 保持启用** —— 门/地图/凯瑟琳菜单都靠它。
	CustomerSpawner.force_disable = true
	QuestLog.reset()
	ChapterStory.reset()
	ChapterStory.auto_advance = true      # 进入对应场景即自动播该幕（正常推进）
	SideStory._story_day = 1              # 别在委托阶段冒出支线访客
	Story.stage = StoryDirector.Stage.OPEN
	Story.snow_offered = true             # 让「接取任务」选项可用（正式靠营业额达标次日弹）
	Story.snow_started = false
	_build_hud()
	# 关键：让本节点不再是 current_scene → 之后 change_scene_to_file 不会释放它，HUD 常驻。
	get_tree().current_scene = null
	await get_tree().process_frame
	get_tree().change_scene_to_file(SCENES["集市"])   # 测试从「接取委托」开始：进集市找凯瑟琳
	await get_tree().process_frame
	await get_tree().process_frame
	_set_note("测试从『接取委托』开始：与集市凯瑟琳交谈 → 选『接取任务』（F1 可隐藏面板）")


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

	# 按钮单独装一层：F1 隐藏面板时整列一起让开（状态面板另由 _panel 控制）。
	_btn_root = Control.new()
	_btn_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_btn_root)

	var panel: Panel = UiStyle.panel(UiStyle.PANEL_BG, UiStyle.LEATHER_LIGHT)
	panel.position = Vector2(8, 8)
	panel.size = Vector2(560, 258)
	_hud.add_child(panel)
	_panel = panel

	var title: Label = UiStyle.label("第一章 · 雾凇无虞 · 测试窗口", UiStyle.FIRE_CORE)
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)

	_status = UiStyle.label("", UiStyle.LINEN, UiStyle.BODY_SIZE)
	_status.position = Vector2(16, 30)
	_status.size = Vector2(528, 100)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)

	_steps_label = UiStyle.label("", UiStyle.LINEN_DARK, UiStyle.BODY_SIZE)
	_steps_label.position = Vector2(16, 134)
	_steps_label.size = Vector2(528, 118)
	_steps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_steps_label)

	_add_button("① 与凯瑟琳交谈",   Vector2(900, 8),   func(): _talk_catherine())
	_add_button("▶ 与当前人物交谈",  Vector2(900, 46),  func(): _talk_current())
	_add_button("切到 酒馆",        Vector2(900, 84),  func(): _go("酒馆"))
	_add_button("切到 酒馆门口",    Vector2(900, 118), func(): _go("酒馆门口"))
	_add_button("切到 集市",        Vector2(900, 152), func(): _go("集市"))
	_add_button("切到 矿道入口",    Vector2(900, 186), func(): _go("矿道入口"))
	_add_button("切到 矿井",        Vector2(900, 220), func(): _go("矿井"))
	_add_button("注入 暖身姜酒×1",   Vector2(900, 262), func(): _inject_wine())
	_add_button("推进对话 (E)",     Vector2(900, 296), func(): _tap_key(KEY_E))
	_add_button("跳过对话 (Esc)",   Vector2(900, 330), func(): _tap_key(KEY_ESCAPE))
	_add_button("隐藏/显示面板 (F1)", Vector2(900, 364), func(): _toggle_ui())
	_add_button("重置（回接取委托）", Vector2(1120, 364), func(): _reset_chapter())

	var help: Label = UiStyle.label("走到人物身边按 E 交谈 · 可踩门 / 按 M 远行 · 酿造幕自动播", UiStyle.FIRE_CORE, UiStyle.BODY_SIZE)
	help.position = Vector2(8, 270)
	_hud.add_child(help)
	_note = UiStyle.label("", UiStyle.GOLD, UiStyle.BODY_SIZE)
	_note.position = Vector2(8, 290)
	_note.size = Vector2(740, 20)
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


## F1：把状态面板 + 按钮列一起藏起来，露出被它们盖住的场景与人物。
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

## 与凯瑟琳交谈：打开她的对话，关掉后由 Story 的 _link_npcs 弹出「集市管理处」菜单。
func _talk_catherine() -> void:
	var npc: Node = _find_npc(CATHERINE_ID)
	if npc == null:
		_set_note("凯瑟琳不在这里，请先切到「集市」")
		return
	npc.call("talk")


## 去某场景：走真实的 change_scene_to_file（等同踩门 / 地图旅行），进场景自动播本幕。
func _go(key: String) -> void:
	if _switching:
		return
	_switching = true
	await _close_modals()
	get_tree().change_scene_to_file(SCENES[key])
	await get_tree().process_frame
	await get_tree().process_frame
	_switching = false
	# 别只说"已前往" —— 若本幕其实在别的场景，玩家会以为剧情坏了。这里直说。
	var why: String = _why_not_here()
	if why == "":
		_set_note("已前往：%s（本幕可在此推进）" % key)
	else:
		_set_note("已前往：%s —— %s" % [key, why])


## 本幕在当前场景推不动的原因（空 = 能推）。
func _why_not_here() -> String:
	if not ChapterStory.is_active() or ChapterStory.is_done():
		return ""
	var b: Dictionary = ChapterStory.current_beat()
	var place: String = str(b.get("place", ""))
	if place == "travel" or _beat_playable_here(b):
		return ""
	if ChapterStory.awaiting_talk():
		return ""
	return "本幕在「%s」，需先去那里（%s）" % [_place_name(place), str(b.get("id", ""))]


## 与"本幕该交谈的人物"对话（等价于走到他身边按 E）。
func _talk_current() -> void:
	if _switching:
		return
	if _find_modal() != null:
		_set_note("已有对话在播，先按 E/Esc 关掉")
		return
	if not Story.snow_started:
		_set_note("还没接取委托：先在集市与凯瑟琳交谈，选『接取任务』")
		return
	if ChapterStory.is_done():
		_set_note("章节已结束（可点「重置（回接取委托）」重来）")
		return
	if not ChapterStory.is_active():
		_set_note("章节未启动，请点「重置（回接取委托）」")
		return
	var b: Dictionary = ChapterStory.current_beat()
	var nid: String = str(b.get("npc", ""))
	var place: String = str(b.get("place", ""))
	if nid == "":
		_set_note("本幕没有可交谈的人物（酿造/旁白幕会自动播放）")
		return
	if not ChapterStory.awaiting_talk():
		_set_note("本幕在「%s」，请先切到该场景（人物才会登场）" % _place_name(place))
		return
	var npc: Node = _find_npc(nid)
	if npc == null:
		_set_note("没找到本幕人物 %s，请重切场景" % nid)
		return
	npc.call("talk")


func _inject_wine() -> void:
	Inventory.add("wine_warm_ginger", 1)
	_set_note("已注入 暖身姜酒×1（若在酒馆，酿造幕会自动播放）")


func _reset_chapter() -> void:
	if _switching:
		return
	_switching = true
	await _close_modals()
	QuestLog.reset()
	ChapterStory.reset()
	Story.snow_started = false
	Story.snow_offered = true
	Story.stage = StoryDirector.Stage.OPEN
	get_tree().change_scene_to_file(SCENES["集市"])
	await get_tree().process_frame
	await get_tree().process_frame
	_switching = false
	_set_note("已重置：回到集市，与凯瑟琳对话重新接取委托")


func _tap_key(keycode: int) -> void:
	_push_key(keycode)


# ---- 实时状态 -------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_status()


func _update_status() -> void:
	if _status == null:
		return
	var wine: int = Inventory.count("wine_warm_ginger")
	var lines: Array[String] = []

	if not Story.snow_started:
		lines.append("状态：待接取委托")
		lines.append("下一步：与「集市」凯瑟琳交谈 → 选『接取任务』")
		lines.append("当前所在：%s    暖身姜酒：%d" % [_current_scene_name(), wine])
		lines.append("传送：可用（踩门 / 按 M 地图远程移动 均正常）")
		_status.text = "\n".join(lines)
		_steps_label.text = "任务：（接取委托后由 ChapterStory 建立）"
		return

	var active: bool = ChapterStory.is_active()
	var done: bool = ChapterStory.is_done()
	var total: int = ChapterStory.beat_count()
	var idx: int = ChapterStory.index()
	var beat: Dictionary = ChapterStory.current_beat()
	var bid: String = str(beat.get("id", "—"))
	var place: String = str(beat.get("place", "—"))
	var trigger: String = str(beat.get("trigger", ""))
	var state: String = "已结束" if done else ("进行中" if active else "未开始")
	var here: String
	if ChapterStory.awaiting_talk():
		here = "人物已到场，走过去按 E 交谈"
	elif _beat_playable_here(beat):
		here = "是"
	else:
		here = "否（需切到「%s」或补条件）" % _place_name(place)
	var trig: String = trigger if trigger != "" else "（自动 / 酿造完成）"
	if trig.length() > 28:
		trig = trig.substr(0, 28) + "…"

	lines.append("状态：%s    本幕在此可播：%s" % [state, here])
	lines.append("当前幕：%s（第 %d/%d 幕）" % [bid, idx + 1, total])
	lines.append("场景：%s → 当前 %s    暖身姜酒：%d" % [_place_name(place), _current_scene_name(), wine])
	lines.append("解锁：矿道入口=%s  粉发少女=%s" % [
		SideStory.is_unlocked("mine_entrance"), SideStory.is_unlocked("pink_haired_girl")])
	lines.append("触发：%s" % trig)
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
	return _current_scene_path() == str(ChapterStory.PLACE_SCENE.get(place, ""))


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
	ChapterStory.abort_current_beat()
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
	print("[chapter1_test] %s" % text)
