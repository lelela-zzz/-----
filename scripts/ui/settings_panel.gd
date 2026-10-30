class_name SettingsPanel
extends UiPanel
## 显示 + 音频设置面板（F10）：显示模式 / 窗口大小 / 全屏缩放 / 音乐音量。
##
## 显示项改动**立刻生效并写盘**（WindowScale 负责 apply + save），关掉面板不回滚 ——
## 玩家要的正是"边调边看"。音乐音量同样即时生效（Music 负责存 user://audio.cfg）。
##
## 这里改的只是"640×384 这张画面贴到屏幕上多大"，内部渲染分辨率不动，
## 所以面板开着的时候调分辨率也不会错位（面板自己也在 640×384 坐标系里）。

const FRAME: Rect2 = Rect2(120, 72, 400, 262)
const ROW_TOP: int = 58
const ROW_H: int = 44
const ROW_W: int = 384        # FRAME.size.x - 16
const VAL_RIGHT: int = 386    # 值的右对齐边（相对 _frame）

var _index: int = 0
var _rows: Array[Dictionary] = []


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	var title: Label = UiStyle.label("设置", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(14, 8)
	_frame.add_child(title)

	var note: Label = UiStyle.label("改动立即生效并保存", UiStyle.LINEN_DARK)
	note.position = Vector2(150, 22)
	_frame.add_child(note)

	UiStyle.divider(_frame, 8, 44, int(FRAME.size.x) - 16)

	for i: int in 4:
		var y: int = ROW_TOP + i * ROW_H

		var bg: ColorRect = UiStyle.rect(UiStyle.BROWN)
		bg.position = Vector2(8, y - 8)
		bg.size = Vector2(ROW_W, ROW_H - 6)
		bg.visible = false
		_frame.add_child(bg)

		var accent: ColorRect = UiStyle.rect(UiStyle.FIRE)
		accent.position = Vector2(8, y - 8)
		accent.size = Vector2(2, ROW_H - 6)
		accent.visible = false
		_frame.add_child(accent)

		var name_label: Label = UiStyle.label("", UiStyle.LINEN)
		name_label.position = Vector2(18, y)
		_frame.add_child(name_label)

		var value_label: Label = UiStyle.label("", UiStyle.FIRE)
		value_label.position = Vector2(0, y)
		_frame.add_child(value_label)

		_rows.append({
			"bg": bg, "accent": accent,
			"name": name_label, "value": value_label,
		})

	var hint: Label = UiStyle.label("[W/S] 选   [A/D] 改   [Esc] 返回", UiStyle.LINEN_DARK)
	hint.position = Vector2(18, 234)
	_frame.add_child(hint)

	WindowScale.changed.connect(_refresh)
	_refresh()


# ---- 行内容 ----------------------------------------------------------------

## 三行：0 显示模式 / 1 窗口大小 / 2 全屏缩放
func _row_name(i: int) -> String:
	match i:
		0: return "显示模式"
		1: return "窗口大小"
		2: return "全屏缩放"
		3: return "音乐音量"
	return ""


func _row_value(i: int) -> String:
	match i:
		0:
			return "全屏" if WindowScale.fullscreen else "窗口化"
		1:
			if WindowScale.fullscreen:
				return "— 全屏下不适用"
			return WindowScale.scale_text(WindowScale.display_scale)
		2:
			if not WindowScale.fullscreen:
				return "— 窗口化恒整数倍"
			return "铺满（像素轻微不均）" if WindowScale.fill_screen else "整数倍（像素最锐）"
		3:
			if Music.volume_percent() <= 0:
				return "静音"
			return "%d%%" % Music.volume_percent()
	return ""


## 全屏时"窗口大小"不可改；窗口化时"全屏缩放"不可改
func _row_enabled(i: int) -> bool:
	if i == 1:
		return not WindowScale.fullscreen
	if i == 2:
		return WindowScale.fullscreen
	return true


func _refresh() -> void:
	if _rows.is_empty():
		return
	for i: int in _rows.size():
		var ui: Dictionary = _rows[i]
		var selected: bool = i == _index
		var enabled: bool = _row_enabled(i)

		(ui["bg"] as ColorRect).visible = selected
		(ui["accent"] as ColorRect).visible = selected

		var name_label: Label = ui["name"] as Label
		name_label.text = _row_name(i)
		name_label.add_theme_color_override("font_color",
				UiStyle.LINEN if enabled else UiStyle.METAL_DARK)

		var value_label: Label = ui["value"] as Label
		value_label.text = _row_value(i)
		value_label.position.x = float(VAL_RIGHT - UiStyle.text_width(value_label.text))
		value_label.add_theme_color_override("font_color",
				(UiStyle.FIRE if enabled else UiStyle.METAL_DARK) if selected
				else (UiStyle.LINEN if enabled else UiStyle.METAL_DARK))


# ---- 输入 ------------------------------------------------------------------

func _on_key(keycode: int) -> bool:
	match keycode:
		KEY_W, KEY_UP:
			_move(-1)
			return true
		KEY_S, KEY_DOWN:
			_move(1)
			return true
		KEY_A, KEY_LEFT:
			_change(-1)
			return true
		KEY_D, KEY_RIGHT, KEY_E, KEY_ENTER, KEY_KP_ENTER:
			_change(1)
			return true
		KEY_F10:
			close()
			return true
	return false


func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, _rows.size())
	_refresh()


## 改当前行的值。step 只影响"窗口大小"档位的加减，两个开关类直接切换。
func _change(step: int) -> void:
	match _index:
		0:
			WindowScale.set_fullscreen(not WindowScale.fullscreen)
		1:
			if WindowScale.fullscreen:
				return
			var options: Array[float] = [0.0]
			options.append_array(WindowScale.scales())
			var cur: int = maxi(0, options.find(WindowScale.display_scale))
			WindowScale.set_display_scale(options[wrapi(cur + step, 0, options.size())])
		2:
			if not WindowScale.fullscreen:
				return
			WindowScale.set_fill_screen(not WindowScale.fill_screen)
		3:
			Music.nudge_volume(step)
	_refresh()
