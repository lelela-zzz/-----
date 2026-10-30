extends Node
## 音量调节验收：
##   "<godot.exe>" --headless --path . res://tests/verify_volume.tscn --quit-after 9000
##
## 背景：玩家反馈"音乐只能调大、不能调小"。查下来键位上 A/← 本来是能减的，
## 但 E 也被绑成"加一格"，而 E 在这游戏里到处是"确认"——习惯性按 E 就只会往上走；
## 另外音量行只有一个百分比数字，没有可点的控件。
## 所以这次补齐四件事，逐条验：
##   1) 音量行有 10 格可交互音量条（不是纯文字）
##   2) 键盘 A/D、←/→ 双向都对（不再是"只会加"）
##   3) 鼠标点格子 / 滚轮 也能改（新增的调节方式）
##   4) E 不再改音量，而是"改完返回"；0% 时文案写"静音"，且真的静到 -80dB
##
## 跑完把音量还原成进来时的值，别在开发机上留下奇怪的配置。

const PANEL: String = "res://scenes/ui/settings_panel.tscn"

var _pass: int = 0
var _fail: int = 0
var _panel: Node = null
var _backup: float = 0.7


func _ready() -> void:
	# 不用 logic_resolution：这个用例不比对像素，只要坐标系一致即可
	_backup = Music.volume()
	Music.set_volume(0.7)
	await get_tree().process_frame

	var ps: PackedScene = load(PANEL) as PackedScene
	_panel = ps.instantiate()
	add_child(_panel)
	await _wait(3)

	var bar: Control = _bar()
	_report("音量行有音量条控件", bar != null, "bar=%s" % bar)
	_report("音量条是 10 格", bar != null and int(bar.call("cell_count")) == 10,
			"cells=%s" % (bar.call("cell_count") if bar != null else "n/a"))
	_report("音量条与当前音量同步（70% = 7 格）",
			bar != null and is_equal_approx(float(bar.get("_value")), 0.7),
			str(bar.get("_value") if bar != null else "n/a"))

	# 走到音量行
	_panel._on_key(KEY_S)
	_panel._on_key(KEY_S)
	_panel._on_key(KEY_S)
	_report("W/S 能选到音量行", int(_panel.get("_index")) == 3,
			str(_panel.get("_index")))

	# ---- 键盘双向 ----
	_panel._on_key(KEY_A)
	_report("A 减一档 → 60%", Music.volume_percent() == 60,
			"%d%%" % Music.volume_percent())
	_panel._on_key(KEY_LEFT)
	_report("← 再减一档 → 50%", Music.volume_percent() == 50,
			"%d%%" % Music.volume_percent())
	_panel._on_key(KEY_D)
	_report("D 加一档 → 60%", Music.volume_percent() == 60,
			"%d%%" % Music.volume_percent())
	_panel._on_key(KEY_RIGHT)
	_report("→ 再加一档 → 70%", Music.volume_percent() == 70,
			"%d%%" % Music.volume_percent())
	_report("音量条跟着键盘走（7 格）",
			bar != null and is_equal_approx(float(bar.get("_value")), 0.7),
			str(bar.get("_value") if bar != null else "n/a"))

	# 一路减到 0：文案变"静音"，电平真的沉到 -80dB
	for i: int in 10:
		_panel._on_key(KEY_A)
	_report("连按 A 能减到 0（不再卡住）", Music.volume_percent() == 0,
			"%d%%" % Music.volume_percent())
	_report("0% 文案写「静音」", _has_label("静音"), "%s" % str(_labels()))
	_report("0% 时电平 = -80dB", is_equal_approx(Music.volume_db_now(),
			Music.SILENT_DB), "%.1f dB" % Music.volume_db_now())

	# 从 0 往回升
	_panel._on_key(KEY_D)
	_report("0% 按 D 能回到 10%", Music.volume_percent() == 10,
			"%d%%" % Music.volume_percent())

	# ---- 鼠标：点格子 ----
	var target: int = 2            # 0 基第 2 格 = 屏上第 3 格 → 30%
	_click_cell(bar, target)
	await _wait(2)
	_report("鼠标点第 3 格 → 30%", Music.volume_percent() == 30,
			"%d%%" % Music.volume_percent())
	_report("点完之后音量条也更新（3 格、30%）",
			bar != null and is_equal_approx(float(bar.get("_value")), 0.3),
			str(bar.get("_value") if bar != null else "n/a"))

	# ---- 鼠标：滚轮 ----
	_wheel(bar, true)
	await _wait(2)
	_report("滚轮上滚一档 → 40%", Music.volume_percent() == 40,
			"%d%%" % Music.volume_percent())
	_wheel(bar, false)
	_wheel(bar, false)
	await _wait(2)
	_report("滚轮下滚两档 → 20%", Music.volume_percent() == 20,
			"%d%%" % Music.volume_percent())

	# ---- E 不再加音量，而是返回 ----
	Music.set_volume(0.5)
	_panel._refresh()
	_panel._on_key(KEY_E)
	await _wait(2)
	_report("E 不再改音量（仍是 50%）", Music.volume_percent() == 50,
			"%d%%" % Music.volume_percent())
	_report("E 把面板关了（改完返回）", _modal() == null, "panel=%s" % _modal())

	Music.set_volume(_backup)
	print("[verify_volume] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---- 工具 ------------------------------------------------------------------

func _bar() -> Control:
	if _panel == null or not is_instance_valid(_panel):
		return null
	var rows: Array = _panel.get("_rows")
	if rows.size() <= 3 or not rows[3].has("bar"):
		return null
	return rows[3]["bar"] as Control


## 点音量条上的第 idx 格（0 基）。
## 注意：面板挂在带 render_scale 缩放的 UI 根下，push_input 吃的是**窗口坐标**，
## 所以要用 get_screen_transform() 把控件局部坐标一路换到窗口系。
func _cell_center(bar: Control, idx: int) -> Vector2:
	var step: float = float(bar.get("CELL_W")) + float(bar.get("CELL_GAP"))
	var local: Vector2 = Vector2(float(idx) * step + 6.0, bar.size.y * 0.5)
	return bar.get_screen_transform() * local


func _click_cell(bar: Control, idx: int) -> void:
	if bar == null:
		return
	var pos: Vector2 = _cell_center(bar, idx)
	_push_mouse_click(pos)


func _wheel(bar: Control, up: bool) -> void:
	if bar == null:
		return
	var pos: Vector2 = bar.get_screen_transform() * (bar.size * 0.5)
	_push_mouse_click(pos, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN)


## headless（dummy 显示驱动）下，Window 的 GUI 事件路由不稳定——同样的
## root.push_input 时通时不通。这里直接把合成事件喂给控件的 _gui_input：
## VolumeBar 的输入处理、信号、Music 落盘、面板刷新全链路照常走到，
## 只跳过"引擎把窗口事件投递给哪个控件"这一步引擎自身的行为。
## 位置一律用控件局部坐标。
func _push_mouse_click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var bar: Control = _bar()
	if bar == null:
		return
	var local: Vector2 = bar.get_screen_transform().affine_inverse() * pos
	var mv: InputEventMouseMotion = InputEventMouseMotion.new()
	mv.position = local
	bar._gui_input(mv)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	if button == MOUSE_BUTTON_LEFT:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = local
	bar._gui_input(ev)
	if button == MOUSE_BUTTON_LEFT:
		var up_ev: InputEventMouseButton = InputEventMouseButton.new()
		up_ev.button_index = button
		up_ev.pressed = false
		up_ev.position = local
		bar._gui_input(up_ev)


## 把窗口系坐标转回控件局部（_push_mouse_click 的调用方只拿到窗口系位置）。
func bar_screen_to_local(pos: Vector2) -> Vector2:
	var bar: Control = _bar()
	if bar == null:
		return Vector2.ZERO
	return bar.get_screen_transform().affine_inverse() * pos


func _modal() -> UiPanel:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n):
			return n as UiPanel
	return null


func _labels() -> Array[String]:
	var out: Array[String] = []
	_walk_labels(_panel, out)
	return out


func _walk_labels(root: Node, out: Array[String]) -> void:
	if root == null:
		return
	if root is Label:
		out.append((root as Label).text)
	for c: Node in root.get_children():
		_walk_labels(c, out)


func _has_label(needle: String) -> bool:
	for t: String in _labels():
		if t.find(needle) >= 0:
			return true
	return false


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s | %s" % [name, detail])
	else:
		_fail += 1
		print("[check] FAIL  %s | %s" % [name, detail])
