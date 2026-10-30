class_name ChoicePanel
extends UiPanel
## 通用选项菜单：W/S 选、E 确认、Esc 关闭，不可用的选项灰掉且跳过。
##
## 凯瑟琳的「采购物资 / 接取任务」用这一份；以后任何"对话完弹选择"的场合
## 都可以直接复用 —— 调用方填 options（text + enabled + hint），连 chosen 信号。

signal option_chosen(index: int)

const FRAME: Rect2 = Rect2(200, 118, 240, 148)
const ROW_TOP: int = 52
const ROW_H: int = 24

## {text: String, enabled: bool = true, hint: String = ""}，add_child 前填好。
var title: String = ""
var options: Array[Dictionary] = []

var _index: int = 0
var _rows: Array[Dictionary] = []


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	if title != "":
		var head: Label = UiStyle.label(title, UiStyle.FIRE_CORE)
		head.position = Vector2(14, 10)
		_frame.add_child(head)

	UiStyle.divider(_frame, 8, ROW_TOP - 12, int(FRAME.size.x) - 16)

	for i: int in options.size():
		var opt: Dictionary = options[i]
		var y: int = ROW_TOP + i * ROW_H
		var enabled: bool = bool(opt.get("enabled", true))

		var bg: ColorRect = UiStyle.rect(UiStyle.BROWN)
		bg.position = Vector2(8, y - 4)
		bg.size = Vector2(int(FRAME.size.x) - 16, ROW_H - 4)
		bg.visible = false
		_frame.add_child(bg)

		var accent: ColorRect = UiStyle.rect(UiStyle.FIRE)
		accent.position = Vector2(8, y - 4)
		accent.size = Vector2(2, ROW_H - 4)
		accent.visible = false
		_frame.add_child(accent)

		var color: Color = UiStyle.METAL_DARK if not enabled else UiStyle.LINEN
		var label: Label = UiStyle.label("%d. %s" % [i + 1, str(opt["text"])], color)
		label.position = Vector2(18, y)
		_frame.add_child(label)

		var hint: String = str(opt.get("hint", ""))
		if hint != "":
			var hint_label: Label = UiStyle.label(hint, UiStyle.LINEN_DARK)
			hint_label.position = Vector2(int(FRAME.size.x) - 14 - _text_width(hint), y)
			_frame.add_child(hint_label)

		_rows.append({"bg": bg, "accent": accent, "label": label, "enabled": enabled})

	_index = _first_enabled()
	_refresh()


func _text_width(s: String) -> int:
	var f: Font = UiStyle.theme().default_font
	return int(f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.BODY_SIZE).x)


func _first_enabled() -> int:
	for i: int in _rows.size():
		if bool(_rows[i]["enabled"]):
			return i
	return -1


func _refresh() -> void:
	for i: int in _rows.size():
		var ui: Dictionary = _rows[i]
		var selected: bool = i == _index
		(ui["bg"] as ColorRect).visible = selected
		(ui["accent"] as ColorRect).visible = selected
		var color: Color = UiStyle.METAL_DARK if not bool(ui["enabled"]) else UiStyle.LINEN
		if selected and bool(ui["enabled"]):
			color = UiStyle.FIRE_CORE
		(ui["label"] as Label).add_theme_color_override("font_color", color)


func _on_key(keycode: int) -> bool:
	match keycode:
		KEY_W, KEY_UP:
			_move(-1)
			return true
		KEY_S, KEY_DOWN:
			_move(1)
			return true
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			_confirm()
			return true
	return false


func _move(step: int) -> void:
	if _rows.is_empty():
		return
	# 不可用的选项直接滑过去，光标永远停在能按的东西上
	for _i: int in _rows.size():
		_index = wrapi(_index + step, 0, _rows.size())
		if bool(_rows[_index]["enabled"]):
			break
	_refresh()


func _confirm() -> void:
	if _index < 0 or _index >= _rows.size() or not bool(_rows[_index]["enabled"]):
		return
	var chosen: int = _index
	close()
	option_chosen.emit(chosen)
