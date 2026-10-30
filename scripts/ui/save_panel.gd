class_name SavePanel
extends UiPanel
## 存档面板：三个槽位，一行一个。
##
## 同一块面板两种用途（`mode`）：
##   · "save"：游戏里按 F5 / 点左上角提示条 → 选一格写进去。覆盖已有存档要按两次
##     E（第一次只提示"再按一次覆盖"），避免手滑把自己的一晚上抹掉。
##   · "load"：标题界面「读取存档」→ 选一格读。这里只发 `load_requested`，
##     真正的淡出 + 切场景交给标题界面（它才有淡入淡出层）。
##
## 空档也要能选中 —— 玩家需要看见"还有两格空着"，而不是列表忽然只剩一行。

signal load_requested(slot: int)
signal saved(slot: int)

const FRAME: Rect2 = Rect2(88, 38, 464, 306)
const ROW_X: int = 8
const ROW_W: int = 448
const ROW_H: int = 62
const ROW_TOP: int = 56
const ROW_GAP: int = 6
const STATUS_Y: int = 258

## "save" 或 "load"，必须在 add_child 之前设好（_build 里要用）
var mode: String = "save"

var _rows: Array = []
var _index: int = 0
## 已经按过一次 E 的格子（-1 = 没有）。存档模式下覆盖要按两次。
var _armed: int = -1
## 已经按过一次 X 的格子（-1 = 没有）。删除统一要按两次。
var _armed_delete: int = -1
var _status: Label = null
var _hint: Label = null
## 玩家动过鼠标没有。面板弹出的瞬间光标可能正压在 2 号槽上，Godot 会补发
## mouse_entered 把焦点顶过去 —— 键盘玩家一按 E 就存错了格子。所以动过鼠标前忽略悬停。
var _mouse_moved: bool = false


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	var title: Label = UiStyle.label(
			"存档" if mode == "save" else "读取存档",
			UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(16, 8)
	_frame.add_child(title)

	var note_text: String = "覆盖与删除都要按两次" if mode == "save" \
			else "选一格继续上次的进度"
	var note: Label = UiStyle.label(note_text, UiStyle.LINEN_DARK)
	# 右对齐到框内边：标题两字和四字宽度不同，左对齐会和标题叠字
	note.position = Vector2(
			FRAME.size.x - 16.0 - UiStyle.text_width(note_text, UiStyle.BODY_SIZE), 20)
	_frame.add_child(note)

	UiStyle.divider(_frame, 12, 44, int(FRAME.size.x) - 24)

	for i: int in SaveGame.SLOT_COUNT:
		var row: SlotRow = SlotRow.new(i + 1, Vector2(ROW_W, ROW_H))
		row.position = Vector2(ROW_X, ROW_TOP + i * (ROW_H + ROW_GAP))
		row.hovered.connect(_on_hover)
		row.activated.connect(_on_activate)
		_frame.add_child(row)
		_rows.append(row)

	_status = UiStyle.label("", UiStyle.LINEN_DARK)
	_status.position = Vector2(16, STATUS_Y)
	_status.size = Vector2(int(FRAME.size.x) - 32, 14)
	_frame.add_child(_status)

	_hint = UiStyle.label(_hint_text(), UiStyle.LINEN_DARK)
	_hint.position = Vector2(16, STATUS_Y + 18)
	_frame.add_child(_hint)

	_refresh()
	_select(0)          # 一开面板就站在 1 号槽上（不然三条都是灰的，看不出焦点在哪）


func _hint_text() -> String:
	if mode == "save":
		return "[W/S] 选   [E] 存入   [X] 删除   [Esc] 返回"
	return "[W/S] 选   [E] 读取   [X] 删除   [Esc] 返回"


# ---- 刷新 ------------------------------------------------------------------

func _refresh() -> void:
	for i: int in _rows.size():
		var slot: int = i + 1
		(_rows[i] as SlotRow).show_slot(SaveGame.meta_of(slot), mode)


func _set_status(text: String, hot: bool = false) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color",
			UiStyle.FIRE if hot else UiStyle.LINEN_DARK)


func _select(i: int) -> void:
	if _rows.is_empty():
		return
	var next: int = posmod(i, _rows.size())
	if next != _index:
		_armed = -1          # 换了格子，覆盖确认作废
		_armed_delete = -1   # 删除确认同样作废
	_index = next
	for n: int in _rows.size():
		(_rows[n] as SlotRow).set_focused(n == _index)


# ---- 交互 ------------------------------------------------------------------

func _on_hover(index: int) -> void:
	if _mouse_moved and index != _index:
		_select(index)


func _on_any_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_moved = true


func _on_activate(index: int) -> void:
	_select(index)
	_act()


func _on_key(keycode: int) -> bool:
	match keycode:
		KEY_W, KEY_UP:
			_select(_index - 1)
			return true
		KEY_S, KEY_DOWN:
			_select(_index + 1)
			return true
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_act()
			return true
		KEY_X, KEY_DELETE:
			_delete()
			return true
	return false


func _act() -> void:
	var slot: int = _index + 1
	if mode == "load":
		if not SaveGame.has_slot(slot):
			_set_status("存档位 %d 是空的" % slot, true)
			return
		load_requested.emit(slot)
		close()
		return

	# ---- 存档 ----
	var reason: String = SaveGame.block_reason()
	if not reason.is_empty():
		_set_status(reason, true)
		return
	if SaveGame.has_slot(slot) and _armed != slot:
		# 第一次按：只上膛，不动盘
		_armed = slot
		_armed_delete = -1
		_set_status("存档位 %d 已有记录，再按一次 E 覆盖" % slot, true)
		(_rows[_index] as SlotRow).flash()
		return
	if SaveGame.save_to(slot):
		_armed = -1
		_armed_delete = -1
		_refresh()
		_set_status("已存入存档位 %d" % slot, true)
		saved.emit(slot)
		# 让玩家看见那行摘要变了再收摊；浮字提示放到收摊之后，
		# 否则它会压在面板标题上，看着像排版错了。
		await get_tree().create_timer(0.45).timeout
		if is_inside_tree():
			close()
			if Story != null and Story.has_method("toast"):
				Story.toast("已存档 · 存档位 %d" % slot)
	else:
		_set_status("存档失败（写入被拒）", true)


## 删除一格（两种模式都能删：存档面板里清位、读取面板里清掉不想要的进度）。
## 同样按两次：第一次只上膛 —— 删存档是不可逆的，多按一次键换一次后悔药。
func _delete() -> void:
	var slot: int = _index + 1
	if not SaveGame.has_slot(slot):
		_set_status("存档位 %d 是空的，没什么可删" % slot, true)
		return
	if _armed_delete != slot:
		_armed_delete = slot
		_armed = -1
		_set_status("再按一次 X 删除存档位 %d（删了就找不回来）" % slot, true)
		(_rows[_index] as SlotRow).flash()
		return
	if SaveGame.delete_slot(slot):
		_armed_delete = -1
		_refresh()
		_set_status("已删除存档位 %d" % slot, true)
		if Story != null and Story.has_method("toast"):
			Story.toast("已删除 · 存档位 %d" % slot)


# ---- 一行 ------------------------------------------------------------------

## 一个存档位。左半边「存档 N」+ 摘要，右边一句"在哪儿存的"。
class SlotRow extends Control:
	signal hovered(index: int)
	signal activated(index: int)

	var slot: int = 1
	var _plate: Panel
	var _accent: ColorRect
	var _name: Label
	var _summary: Label
	var _where: Label
	var _empty: bool = true


	func _init(n: int, box: Vector2) -> void:
		slot = n
		mouse_filter = Control.MOUSE_FILTER_STOP
		size = box
		custom_minimum_size = box

		_plate = UiStyle.panel(Color(UiStyle.BROWN.r, UiStyle.BROWN.g, UiStyle.BROWN.b, 0.34),
				UiStyle.BROWN)
		_plate.size = box
		add_child(_plate)

		_accent = UiStyle.rect(UiStyle.FIRE)
		_accent.position = Vector2.ZERO
		_accent.size = Vector2(4, box.y)
		_accent.visible = false
		add_child(_accent)

		_name = UiStyle.label("存档 %d" % n, UiStyle.LINEN, UiStyle.TITLE_SIZE)
		_name.position = Vector2(16, 4)
		add_child(_name)

		_summary = UiStyle.label("", UiStyle.LINEN_DARK, UiStyle.BODY_SIZE)
		_summary.position = Vector2(16, 38)
		add_child(_summary)

		_where = UiStyle.label("", UiStyle.LINEN_DARK, UiStyle.BODY_SIZE)
		_where.size = Vector2(200, 14)
		_where.position = Vector2(box.x - 216, 38)
		_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_where)

		mouse_entered.connect(func() -> void: hovered.emit(slot - 1))


	## 灌一行数据。名字别叫 set_meta —— 那是 Object 的元数据接口，重名会编译不过。
	func show_slot(meta: Dictionary, mode: String) -> void:
		_empty = meta.is_empty()
		if _empty:
			_summary.text = "空存档位" if mode == "save" else "（还没有存档）"
			_where.text = "按 E 存入" if mode == "save" else ""
			_name.add_theme_color_override("font_color", UiStyle.LINEN_DARK)
			return
		_summary.text = SaveGame.summary_of(meta)
		_where.text = str(meta.get("saved_at", "")).substr(0, 16)
		_name.add_theme_color_override("font_color", UiStyle.LINEN)


	func set_focused(on: bool) -> void:
		_accent.visible = on
		_plate.add_theme_stylebox_override("panel",
				UiStyle.box(Color(UiStyle.BROWN.r, UiStyle.BROWN.g, UiStyle.BROWN.b,
						0.62 if on else 0.34),
						UiStyle.LEATHER_LIGHT if on else UiStyle.BROWN))
		if _empty:
			_name.add_theme_color_override("font_color",
					UiStyle.LINEN if on else UiStyle.LINEN_DARK)
		else:
			_name.add_theme_color_override("font_color",
					UiStyle.FIRE_CORE if on else UiStyle.LINEN)
		_summary.add_theme_color_override("font_color",
				UiStyle.LINEN if on else UiStyle.LINEN_DARK)


	## 覆盖提醒：整块闪一下，眼睛能跟到是按的哪一行
	func flash() -> void:
		var tw: Tween = create_tween()
		tw.tween_property(_plate, "modulate", Color(1.35, 1.15, 0.85), 0.08)
		tw.tween_property(_plate, "modulate", Color.WHITE, 0.28)


	func _gui_input(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			activated.emit(slot - 1)
