class_name SettingsPanel
extends UiPanel
## 显示 + 音频设置面板（F6）：显示模式 / 窗口大小 / 全屏缩放 / 音乐音量。
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

## 音量行多一条 10 格音量条（放在名称和百分比之间）：
##   x=204..342 共 138 宽（10 格 ×12 + 9 缝 ×2），右边留出「70%」的位置。
const BAR_X: int = 204
const BAR_Y_OFF: int = 0      # 与行内名称同高（12px 字顶对齐）

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

	# 音量行（第 4 行）额外挂一条可点的音量条：光有一个百分比数字，玩家既看不出
	# 音量高低、也没法用鼠标调（2026-10-30 用户反馈"只能调大不能调小"）。
	var bar: VolumeBar = VolumeBar.new()
	bar.position = Vector2(BAR_X, ROW_TOP + 3 * ROW_H + BAR_Y_OFF)
	bar.volume_changed.connect(_on_bar_changed)
	_frame.add_child(bar)
	_rows[3]["bar"] = bar

	var hint: Label = UiStyle.label(
			"[W/S] 选   [A/D] 改（音量行可点/滚轮）   [E/Esc] 返回", UiStyle.LINEN_DARK)
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
	# 音量条跟着真实音量走（键盘改的、鼠标改的、读盘读进来的，都从这一个出口刷）
	if _rows.size() > 3 and _rows[3].has("bar"):
		(_rows[3]["bar"] as VolumeBar).set_volume_value(Music.volume())


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
		KEY_D, KEY_RIGHT:
			_change(1)
			return true
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			# E 在这游戏里到处都是"确认"。以前它也当"加一格"用 —— 玩家习惯性按 E
			# 就会觉得"音量只能调大"。现在 E = 改完返回。
			close()
			return true
		KEY_F6:
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


## 鼠标在音量条上改完 → 交给 Music（它负责即时生效 + 存盘），再刷一遍面板。
func _on_bar_changed(value: float) -> void:
	Music.set_volume(value)
	_refresh()


## 10 格音量条：既是显示，也是鼠标入口。
##
## 三种点法都通：
##   · 点某一格 → 音量设为该格（第 1 格 = 10%，第 10 格 = 100%）
##   · 按住左右拖 → 连续调（拖到条左边界外就是 0，静音）
##   · 滚轮 → 一格一格加减
## 键盘仍有 A/D 与 ←/→，两边共用一个出口（volume_changed → Music.set_volume）。
class VolumeBar extends Control:
	signal volume_changed(value: float)

	const CELLS: int = 10
	const CELL_W: int = 12
	const CELL_GAP: int = 2
	const CELL_H: int = 12
	const STEP: float = 0.1

	var _value: float = 0.7
	var _hover: bool = false


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var w: int = CELLS * CELL_W + (CELLS - 1) * CELL_GAP
		size = Vector2(w, CELL_H)
		custom_minimum_size = Vector2(w, CELL_H)
		tooltip_text = "点格子 / 拖动 / 滚轮 调音量"
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())


	## 外部（面板刷新）灌值：只重画，不回发信号 —— 否则会自己把自己写一遍盘
	func set_volume_value(v: float) -> void:
		_value = clampf(v, 0.0, 1.0)
		queue_redraw()


	func cell_count() -> int:
		return CELLS


	func _draw() -> void:
		var filled: int = roundi(_value * float(CELLS))
		for i: int in CELLS:
			var r: Rect2 = Rect2(i * (CELL_W + CELL_GAP), 0, CELL_W, CELL_H)
			if i < filled:
				draw_rect(r, UiStyle.FIRE, true)
			else:
				draw_rect(r, Color(UiStyle.BROWN.r, UiStyle.BROWN.g, UiStyle.BROWN.b, 0.60), true)
			draw_rect(r, UiStyle.LEATHER_LIGHT if _hover else UiStyle.INK, false, 1.0)


	func _gui_input(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_nudge(1)
					accept_event()
				MOUSE_BUTTON_WHEEL_DOWN:
					_nudge(-1)
					accept_event()
				MOUSE_BUTTON_LEFT:
					_set_at(mb.position.x)
					accept_event()
			return
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_set_at(mm.position.x)
			accept_event()


	func _set_at(x: float) -> void:
		if x <= 0.0:
			_emit(0.0)          # 拖出左边界 = 静音
			return
		if x >= size.x:
			_emit(1.0)
			return
		var idx: int = clampi(int(x / float(CELL_W + CELL_GAP)), 0, CELLS - 1)
		_emit(float(idx + 1) / float(CELLS))


	func _nudge(step: int) -> void:
		_emit(_value + float(step) * STEP)


	## 统一出口：吸到 10% 档、值没变就不发信号（拖动时不会每帧写盘）
	func _emit(v: float) -> void:
		var next: float = clampf(snappedf(v, STEP), 0.0, 1.0)
		if is_equal_approx(next, _value):
			return
		_value = next
		queue_redraw()
		volume_changed.emit(next)
