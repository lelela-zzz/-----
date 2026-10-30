extends Node2D
## 开始界面（主菜单）—— 进游戏前的那一屏。
##
## 【为什么是 1280×768 而不是 640×384】世界和 HUD 走的是 640 逻辑 × 2 的
## 渲染路线，但这一屏是"海报"，不跟世界网格对齐更自由：设计坐标直接写
## 渲染原生尺寸（WindowScale.RENDER_SIZE），1 个源像素 = 1 个屏幕像素，
## 底图不用缩放、字也不经过相机 zoom，最锐。窗口再怎么拉都是 stretch 缩放。
##
## 【构图】底图（tools/make_title_bg.py 生成）已经把酒馆放在右半边、左半边
## 压黑；这一屏只负责"往暗处说话"：标题压左上，菜单贴左侧竖排。
##
## 【交互】W/S 或 ↑↓ 选，E / Enter / Space 确认，鼠标悬停即选、点击即确认。
## 设置面板复用游戏里的 scenes/ui/settings_panel.tscn（它自己会按容器算缩放）。
##
## 【存档位】「继续游戏 / 读取存档」按 `SaveGame.any_slot()` 决定亮不亮：
##   · 继续游戏 = 读 SaveGame.last_slot()（上次游玩那一格）
##   · 读取存档 = 弹 scenes/ui/save_panel.tscn（mode="load"），选格再读
## 没存档时两行置灰、右侧注「暂无存档」，按下去只闪一下标注、不改状态。

const BG_TEXTURE: Texture2D = preload("res://assets/title/v1/title_bg_2x.png")
const GLOW_TEXTURE: Texture2D = preload("res://assets/lighting/light_warm_radial_1x.png")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_panel.tscn")
const SAVE_PANEL_SCENE: PackedScene = preload("res://scenes/ui/save_panel.tscn")

const WORLD_SCENE: String = "res://scenes/world.tscn"

## 设计画布 = 内部渲染尺寸
const DESIGN: Vector2 = Vector2(1280, 768)

## 版式常数（全部写在这，改布局不用翻代码）
const TITLE_TEXT: String = "炉火镇"
const SUBTITLE_TEXT: String = "HEARTHVALE"
const TAGLINE_TEXT: String = "一间酒馆，一镇长夜"
const FOOTER_TEXT: String = "W / S 选择      E / Enter 确认"
const VERSION_TEXT: String = "序章 · 开张头一日"

const TITLE_POS: Vector2 = Vector2(88, 118)
const RULE_POS: Vector2 = Vector2(92, 258)
const RULE_W: int = 292
const SUBTITLE_POS: Vector2 = Vector2(92, 274)
const TAGLINE_POS: Vector2 = Vector2(92, 312)
const MENU_POS: Vector2 = Vector2(88, 372)
const ITEM_W: int = 424
const ITEM_H: int = 56
const ITEM_GAP: int = 4
const FOOTER_POS: Vector2 = Vector2(92, 706)
const VERSION_POS: Vector2 = Vector2(1188, 706)

const TITLE_FONT: int = 96     # 12 × 8
const ITEM_FONT: int = 36      # 12 × 3
const SMALL_FONT: int = 24     # 12 × 2

const FADE_IN_SEC: float = 0.85
const FADE_OUT_SEC: float = 0.55

## 没存档时，两行占位菜单的右侧标注
const NO_SAVE_NOTE: String = "暂无存档"

## 菜单项：文案 + 行为 key。`needs_save` = 存档系统接上、且真有存档才可用。
const MENU_ITEMS: Array[Dictionary] = [
	{"text": "继续游戏", "action": "continue", "needs_save": true},
	{"text": "读取存档", "action": "load", "needs_save": true},
	{"text": "开始游戏", "action": "start", "needs_save": false},
	{"text": "设置", "action": "settings", "needs_save": false},
	{"text": "退出游戏", "action": "quit", "needs_save": false},
]

## 没有存档时默认停在哪一项（「开始游戏」）——别让玩家一进来就停在一行灰字上
const DEFAULT_INDEX_NO_SAVE: int = 2

var _items: Array = []
var _index: int = 0
var _busy: bool = false

var _ui: Control = null
var _overlay: CanvasLayer = null
var _fade: ColorRect = null
var _glow_title: Sprite2D = null
var _glow_door: Sprite2D = null


# ---- 菜单项控件（内部类）---------------------------------------------------

## 一行菜单：选中时亮成火光色 + 左侧竖条 + 三角指示；未选中是暗亚麻。
## 不可用的行（暂无存档）整体压暗，右侧挂一句小字说明，按下去只闪一下说明。
class TitleMenuItem extends Control:
	signal hovered(index: int)
	signal activated(index: int)

	## 灰掉的行的字色（比 LINEN_DARK 再淡一档，一眼看出点不动）
	const DISABLED_INK: Color = Color(0.541176, 0.521569, 0.470588, 0.42)

	var index: int = 0
	var caption: String = ""
	var enabled: bool = true
	var note: String = ""

	var _accent: ColorRect
	var _back: ColorRect
	var _mark: Arrow
	var _label: Label
	var _note: Label
	var _focused: bool = false


	func _init(i: int, text: String, box: Vector2, usable: bool,
			note_text: String, font_size: int) -> void:
		index = i
		caption = text
		enabled = usable
		note = note_text
		mouse_filter = Control.MOUSE_FILTER_STOP
		size = box
		custom_minimum_size = box

		_back = UiStyle.rect(Color(UiStyle.BROWN.r, UiStyle.BROWN.g, UiStyle.BROWN.b, 0.62))
		_back.size = box
		_back.visible = false
		add_child(_back)

		_accent = UiStyle.rect(UiStyle.FIRE)
		_accent.position = Vector2(0, 0)
		_accent.size = Vector2(4, box.y)
		_accent.visible = false
		add_child(_accent)

		_mark = Arrow.new()
		_mark.position = Vector2(18, box.y * 0.5 - 8.0)
		_mark.visible = false
		add_child(_mark)

		_label = UiStyle.label(text, DISABLED_INK if not usable else UiStyle.LINEN_DARK,
				font_size)
		_label.position = Vector2(44, 0)
		_label.size = Vector2(box.x - 44, box.y)
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)

		if note != "":
			# 紧跟标题后面，而不是右对齐到行尾 —— 行尾那一截已经压到建筑的亮面上，
			# 小字会糊在窗光里。
			_note = UiStyle.label(note, DISABLED_INK, 24)
			_note.size = Vector2(box.x, box.y)
			_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_note.position = Vector2(
					44.0 + UiStyle.text_width(text, font_size) + 24.0, 0)
			add_child(_note)

		mouse_entered.connect(func() -> void: hovered.emit(index))


	func set_focused(on: bool) -> void:
		_focused = on
		_back.visible = on
		_accent.visible = on
		_mark.visible = on
		_label.position.x = 60.0 if on else 44.0
		_accent.color = UiStyle.FIRE if enabled else UiStyle.METAL_DARK
		_mark.color = UiStyle.FIRE if enabled else UiStyle.METAL_DARK
		_mark.queue_redraw()
		var ink: Color = DISABLED_INK
		if enabled:
			ink = UiStyle.FIRE_CORE if on else UiStyle.LINEN_DARK
		elif on:
			# 灰行被选中：只比平时亮一点点，别装成"能点"
			ink = Color(0.66, 0.64, 0.58, 1.0)
		_label.add_theme_color_override("font_color", ink)


	## 点了灰行：把右边那句"暂无存档"闪一下火光，告诉玩家为什么没反应。
	func flash_note() -> void:
		if _note == null:
			return
		_note.add_theme_color_override("font_color", UiStyle.FIRE)
		var tw: Tween = create_tween()
		tw.tween_interval(0.55)
		tw.tween_method(_set_note_alpha, 1.0, 0.42, 0.45)


	func _set_note_alpha(a: float) -> void:
		_note.add_theme_color_override("font_color",
				Color(UiStyle.FIRE.r, UiStyle.FIRE.g, UiStyle.FIRE.b, a))


	func _gui_input(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			activated.emit(index)


## 选中标记：一个 12×16 的实心三角（多边形的硬边正好是像素台阶）。
class Arrow extends Control:
	const W: float = 12.0
	const H: float = 16.0

	var color: Color = UiStyle.FIRE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(W, H)
		custom_minimum_size = Vector2(W, H)

	func _draw() -> void:
		draw_colored_polygon(
				PackedVector2Array([
					Vector2(0, 0), Vector2(W, H * 0.5), Vector2(0, H)]),
				color)


# ---- 搭界面 ----------------------------------------------------------------

func _ready() -> void:
	UiStyle.theme()
	_build_background()
	_build_ui()
	_build_overlay()
	_select(_default_index(), false)
	await _fade_in()
	# 焦点提示：让玩家知道这一屏能用键盘
	_pulse_title_glow()


func _build_background() -> void:
	var bg: Sprite2D = Sprite2D.new()
	bg.name = "Background"
	bg.texture = BG_TEXTURE
	bg.centered = false
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(bg)

	# 标题背后的火光（炉火感）：大而暗，脉动很慢
	_glow_title = _make_glow(Vector2(300, 330), 4.6,
			Color(1.0, 0.56, 0.22, 0.16))
	# 门口漏出来的那团光：小一点、亮一点、脉动快一点
	_glow_door = _make_glow(Vector2(768, 636), 2.2,
			Color(1.0, 0.62, 0.26, 0.20))

	# 火星：从门口地面往上飘
	var embers: CPUParticles2D = _make_embers(Vector2(768, 668),
			Vector2(300, 24), 30, 34.0, 0.07)
	add_child(embers)
	# 细小的浮尘：整屏慢慢飘，别太密
	var dust: CPUParticles2D = _make_embers(Vector2(640, 700),
			Vector2(1000, 120), 18, 12.0, 0.03)
	dust.lifetime = 9.0
	add_child(dust)


func _make_glow(pos: Vector2, scale_mul: float, color: Color) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.texture = GLOW_TEXTURE
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.position = pos
	s.scale = Vector2(scale_mul, scale_mul)
	s.modulate = color
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	add_child(s)
	return s


func _make_embers(pos: Vector2, box: Vector2, amount: int,
		speed: float, grain: float) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.position = pos
	p.texture = GLOW_TEXTURE
	p.amount = amount
	p.lifetime = 5.5
	p.preprocess = 4.0
	p.direction = Vector2(0, -1)
	p.spread = 22.0
	p.gravity = Vector2(0, -7)
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.scale_amount_min = grain * 0.6
	p.scale_amount_max = grain * 1.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = box * 0.5
	p.color = Color(1.0, 0.86, 0.58, 1.0)

	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.78, 0.40, 0.0))
	ramp.set_color(1, Color(1.0, 0.55, 0.20, 0.0))
	ramp.add_point(0.22, Color(1.0, 0.86, 0.56, 0.85))
	ramp.add_point(0.72, Color(1.0, 0.62, 0.26, 0.45))
	p.color_ramp = ramp

	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p


func _build_ui() -> void:
	_ui = Control.new()
	_ui.name = "UI"
	_ui.size = DESIGN
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiStyle.theme()
	add_child(_ui)

	# 标题：先垫一层墨色偏移字当硬阴影，再压正色 —— 像素字不要用 outline，
	# outline 会在笔画的凹角糊成一团。
	var shadow: Label = UiStyle.label(TITLE_TEXT, UiStyle.INK, TITLE_FONT)
	shadow.position = TITLE_POS + Vector2(6, 6)
	_ui.add_child(shadow)

	var title: Label = UiStyle.label(TITLE_TEXT, UiStyle.FIRE_CORE, TITLE_FONT)
	title.name = "Title"
	title.position = TITLE_POS
	_ui.add_child(title)

	var rule: ColorRect = UiStyle.rect(UiStyle.FIRE)
	rule.position = RULE_POS
	rule.size = Vector2(RULE_W, 2)
	_ui.add_child(rule)

	var rule_dim: ColorRect = UiStyle.rect(Color(UiStyle.BROWN.r, UiStyle.BROWN.g, UiStyle.BROWN.b, 1.0))
	rule_dim.position = RULE_POS + Vector2(0, 2)
	rule_dim.size = Vector2(RULE_W, 1)
	_ui.add_child(rule_dim)

	var sub: Label = UiStyle.label(_spaced(SUBTITLE_TEXT), UiStyle.LINEN_DARK, SMALL_FONT)
	sub.position = SUBTITLE_POS
	_ui.add_child(sub)

	var tag: Label = UiStyle.label(TAGLINE_TEXT, UiStyle.LINEN, SMALL_FONT)
	tag.position = TAGLINE_POS
	_ui.add_child(tag)

	for i: int in MENU_ITEMS.size():
		var def: Dictionary = MENU_ITEMS[i]
		var needs_save: bool = bool(def.get("needs_save", false))
		var usable: bool = (not needs_save) or _has_save()
		var item: TitleMenuItem = TitleMenuItem.new(i, str(def["text"]),
				Vector2(ITEM_W, ITEM_H), usable, _note_for(str(def["action"]), usable),
				ITEM_FONT)
		item.position = MENU_POS + Vector2(0, i * (ITEM_H + ITEM_GAP))
		item.hovered.connect(_on_hover)
		item.activated.connect(_on_activate)
		_ui.add_child(item)
		_items.append(item)

	var hint: Label = UiStyle.label(FOOTER_TEXT, UiStyle.LINEN_DARK, SMALL_FONT)
	hint.position = FOOTER_POS
	_ui.add_child(hint)

	var ver: Label = UiStyle.label(VERSION_TEXT, UiStyle.LINEN_DARK, SMALL_FONT)
	ver.size = Vector2(0, 32)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.position = Vector2(VERSION_POS.x - UiStyle.text_width(VERSION_TEXT, SMALL_FONT),
			VERSION_POS.y)
	_ui.add_child(ver)


## 菜单行右侧那句小字：有存档时告诉玩家"上次玩到哪"，没存档时说明为什么点不动。
func _note_for(action: String, usable: bool) -> String:
	if not usable:
		return NO_SAVE_NOTE
	match action:
		"continue":
			var meta: Dictionary = SaveGame.meta_of(SaveGame.last_slot())
			if meta.is_empty():
				return ""
			return "第 %d 天 %02d:%02d" % [int(meta.get("day", 1)),
					int(meta.get("hour", 0)), int(meta.get("minute", 0))]
		"load":
			return "共 %d 格" % _slot_count()
	return ""


func _slot_count() -> int:
	var n: int = 0
	for i: int in range(1, SaveGame.SLOT_COUNT + 1):
		if SaveGame.has_slot(i):
			n += 1
	return n


## 等宽像素字加字距：英文小标题按"字母 + 半角空格"排开，像招牌上的铜字。
func _spaced(text: String) -> String:
	var out: String = ""
	for i: int in text.length():
		if i > 0:
			out += " "
		out += text[i]
	return out


func _build_overlay() -> void:
	# 设置面板单独一层，盖在 UI 之上
	var modal: CanvasLayer = CanvasLayer.new()
	modal.name = "Modal"
	modal.layer = 10
	add_child(modal)

	_overlay = CanvasLayer.new()
	_overlay.name = "Fade"
	_overlay.layer = 20
	add_child(_overlay)

	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.02, 1.0)
	_fade.size = DESIGN
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)


# ---- 交互 ------------------------------------------------------------------

func _select(index: int, wrap: bool = true) -> void:
	if _items.is_empty():
		return
	var count: int = _items.size()
	var next: int = index
	if wrap:
		next = posmod(index, count)
	_index = clampi(next, 0, count - 1)
	for i: int in count:
		(_items[i] as TitleMenuItem).set_focused(i == _index)


func _on_hover(index: int) -> void:
	if _busy or _modal_open():
		return
	if index != _index:
		_select(index, false)


func _on_activate(index: int) -> void:
	if _busy or _modal_open():
		return
	_select(index, false)
	_confirm()


func _modal_open() -> bool:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and n.is_inside_tree():
			return true
	return false


func _input(event: InputEvent) -> void:
	if _busy or _modal_open():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_W, KEY_UP:
			get_viewport().set_input_as_handled()
			_select(_index - 1)
		KEY_S, KEY_DOWN:
			get_viewport().set_input_as_handled()
			_select(_index + 1)
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()
			_confirm()


func _confirm() -> void:
	var def: Dictionary = MENU_ITEMS[_index]
	var action: String = str(def["action"])
	# 灰行（暂无存档）：只闪一下"暂无存档"，不改状态、不切场景
	if bool(def.get("needs_save", false)) and not _has_save():
		(_items[_index] as TitleMenuItem).flash_note()
		return
	match action:
		"continue":
			_continue_game()
		"load":
			_load_game()
		"start":
			_start_game()
		"settings":
			_open_settings()
		"quit":
			_quit_game()


## 有没有存档可读（任意一格）。两行菜单据此亮/灰。
func _has_save() -> bool:
	return SaveGame.any_slot()


## 默认停靠项：有存档停「继续游戏」，没存档停「开始游戏」。
func _default_index() -> int:
	if _has_save():
		return 0
	return DEFAULT_INDEX_NO_SAVE


## 「继续游戏」= 直接读"上次游玩"的那一格（SaveGame 里记着指针）。
func _continue_game() -> void:
	var slot: int = SaveGame.last_slot()
	if slot <= 0:
		# 指针丢了（手动删档 / 换机器）但还有别的档：退而求其次读第一格有档的
		slot = _first_slot()
	if slot <= 0:
		return
	await _fade_out()
	if not SaveGame.load_slot(slot):
		# 档坏了读不出来：别把玩家留在黑屏上，退回去让 ta 选别的
		_busy = false
		await _fade_in()


## 「读取存档」= 弹存档列表，选完再读。
func _load_game() -> void:
	var layer: CanvasLayer = get_node_or_null("Modal") as CanvasLayer
	if layer == null:
		return
	var panel: SavePanel = SAVE_PANEL_SCENE.instantiate() as SavePanel
	panel.mode = "load"
	panel.load_requested.connect(_on_load_requested)
	layer.add_child(panel)


## 存档面板点了某一格：淡出后读档（面板自己会先关掉）
func _on_load_requested(slot: int) -> void:
	_busy = true
	# 等面板真的 free 掉再淡出，否则黑场上还压着一块面板
	await get_tree().process_frame
	await _fade_out()
	if not SaveGame.load_slot(slot):
		_busy = false
		await _fade_in()


func _first_slot() -> int:
	for i: int in range(1, SaveGame.SLOT_COUNT + 1):
		if SaveGame.has_slot(i):
			return i
	return 0


func _start_game() -> void:
	_busy = true
	await _fade_out()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _open_settings() -> void:
	var panel: UiPanel = SETTINGS_SCENE.instantiate() as UiPanel
	var layer: CanvasLayer = get_node_or_null("Modal") as CanvasLayer
	if layer == null:
		return
	layer.add_child(panel)


func _quit_game() -> void:
	_busy = true
	await _fade_out()
	get_tree().quit()


# ---- 动 --------------------------------------------------------------------

func _fade_in() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, FADE_IN_SEC)
	await tw.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fade_out() -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw: Tween = create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE_OUT_SEC)
	await tw.finished


## 火光呼吸：两个光斑各用一个无限循环的 Tween 来回拉亮度。
func _pulse_title_glow() -> void:
	if _glow_title != null:
		var a: Tween = create_tween().set_loops()
		a.tween_property(_glow_title, "modulate:a", 0.10, 2.6) \
				.set_trans(Tween.TRANS_SINE)
		a.tween_property(_glow_title, "modulate:a", 0.18, 2.6) \
				.set_trans(Tween.TRANS_SINE)
	if _glow_door != null:
		var b: Tween = create_tween().set_loops()
		b.tween_property(_glow_door, "modulate:a", 0.15, 1.1) \
				.set_trans(Tween.TRANS_SINE)
		b.tween_property(_glow_door, "modulate:a", 0.24, 0.9) \
				.set_trans(Tween.TRANS_SINE)
