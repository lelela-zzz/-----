extends Node
## 「睡觉中」过场验收：
##  · 布局 —— 最上面「睡觉中」、床在字下面居中、钟表在右上角；
##  · 动画 —— 指针真的在转、省略号在跳、播完发 finished 并自己销毁；
##  · 接入 —— 有 UI 时宵禁跨天先演过场再跳时间；headless/无 UI 时退回同步瞬跳
##    （38 套回归里那批「调完立刻断言 day+1」的用例就靠这条保命）。
##
## 跑法： "<godot>" --headless --path . res://tests/verify_sleep.tscn --quit-after 9000

const TOTAL_SEC: float = SleepOverlay.FADE_IN_SEC + SleepOverlay.HOLD_SEC \
		+ SleepOverlay.FADE_OUT_SEC

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _check_layout_and_anim()
	_check_headless_sync()
	await _check_clock_drives_overlay()
	print("[sleep] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---- 1. 布局 + 动画 -----------------------------------------------------

func _check_layout_and_anim() -> void:
	var host: Control = Control.new()
	host.size = Vector2(640, 384)
	add_child(host)

	var ov: SleepOverlay = SleepOverlay.new()
	host.add_child(ov)
	await get_tree().process_frame

	_report("遮罩上有「睡觉中」三个字", _has_label(ov, SleepOverlay.TITLE_TEXT), _labels(ov))
	_report("睡觉期间占着 modal_ui（别的面板弹不出来）",
			ov.is_in_group("modal_ui"), "")

	var title: Label = _find_label(ov, SleepOverlay.TITLE_TEXT)
	var bed: TextureRect = _find_bed(ov)
	var face: Control = _find_clock(ov)

	_report("床在场景里", bed != null, "")
	if title != null and bed != null and face != null:
		var title_bottom: float = title.position.y + 24.0
		_report("「睡觉中」在最上面（y=%d）" % int(title.position.y),
				title.position.y < 60.0, "title_y=%.0f" % title.position.y)
		_report("床在字的下面（不重叠）",
				bed.position.y >= title_bottom,
				"bed_y=%.0f title_bottom=%.0f" % [bed.position.y, title_bottom])
		_report("床水平居中（±2px）",
				absf((bed.position.x + bed.size.x * 0.5) - 320.0) <= 2.0,
				"center=%.0f" % (bed.position.x + bed.size.x * 0.5))
		_report("床没有盖住钟（床右边缘 < 钟左边缘）",
				bed.position.x + bed.size.x <= face.position.x,
				"bed_right=%.0f clock_left=%.0f" % [bed.position.x + bed.size.x,
						face.position.x])
		_report("钟表在右上角",
				face.position.x >= 500.0 and face.position.y <= 40.0,
				"clock=(%.0f,%.0f)" % [face.position.x, face.position.y])

	ov.play()
	await get_tree().create_timer(0.42).timeout
	_report("指针转起来了（sweep>0）", ov.sweep_amount() > 0.0,
			"sweep=%.2f" % ov.sweep_amount())
	_report("省略号在跳（点数>0）", ov.dot_count() > 0, "dots=%d" % ov.dot_count())

	# 指针的 tween 跑完于「淡入 + 停留」；淡出期间还在，淡出结束才 queue_free。
	# 所以要赶在淡出结束前读 sweep，晚一步就是 previously freed。
	await get_tree().create_timer(SleepOverlay.FADE_IN_SEC + SleepOverlay.HOLD_SEC
			+ 0.05 - 0.42).timeout
	var final_sweep: float = ov.sweep_amount()
	_report("指针整段转完（≈%d 圈）" % int(SleepOverlay.SWEEPS),
			final_sweep >= SleepOverlay.SWEEPS - 0.01, "sweep=%.2f" % final_sweep)

	await get_tree().create_timer(SleepOverlay.FADE_OUT_SEC + 0.25).timeout
	_report("播完自己销毁（不残留）",
			not is_instance_valid(ov) or not ov.is_inside_tree(),
			"valid=%s" % str(is_instance_valid(ov)))
	host.queue_free()
	await get_tree().process_frame


# ---- 2. headless 默认不播（回归护栏） ------------------------------------

## ⚠️ 这个函数必须**全程同步**：它断言"调完立刻 day+1"，一旦插入 await
## 就会和后面的用例并发（_ready 不等它继续往下跑），allow_in_headless 被下一段
## 置 true 之后这里就变成异步过场了 —— 断言的同步性直接失效。
func _check_headless_sync() -> void:
	_report("headless 默认不播过场（保回归同步语义）",
			not SleepOverlay.can_play(), "can_play=%s" % str(SleepOverlay.can_play()))
	var clock: GameClock = GameClock.new()
	clock.running = false
	add_child(clock)          # add_child 同步触发 _ready，不用等 process_frame
	clock.call("_roll_over_curfew")
	_report("无过场时跨天是同步的（调完立刻 day+1 / 07:30）",
			clock.day == 2 and clock.hour == 7 and clock.minute == 30,
			"day=%d %02d:%02d" % [clock.day, clock.hour, clock.minute])
	remove_child(clock)
	clock.queue_free()


# ---- 3. 有 UI 时：先演过场，演完才跳时间 ---------------------------------

func _check_clock_drives_overlay() -> void:
	SleepOverlay.allow_in_headless = true
	# day 是 static 共享的（跨场景不回退），上一段已经把它推到 2 —— 这里要重新起表。
	GameClock.reset_day(1)
	var scene: Node = Node.new()
	var hud: CanvasLayer = CanvasLayer.new()
	hud.name = "HUD"
	var ui: Control = Control.new()
	ui.name = "UIRoot"
	ui.size = Vector2(640, 384)
	hud.add_child(ui)
	scene.add_child(hud)
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	var clock: GameClock = GameClock.new()
	clock.running = true          # 过场演完要把它原样恢复成 true
	scene.add_child(clock)
	await get_tree().process_frame

	clock.call("_roll_over_curfew")
	await get_tree().process_frame
	var ov: SleepOverlay = _find_overlay(ui)
	_report("宵禁跨天把「睡觉中」过场拉起来了", ov != null, "")
	_report("过场没演完之前时间不跳（还停在第 1 天）", clock.day == 1,
			"day=%d" % clock.day)
	_report("过场期间时钟被掐停（running=false）", not clock.running, "")

	await get_tree().create_timer(TOTAL_SEC + 0.3).timeout
	_report("过场演完 → 第 2 天 07:30",
			clock.day == 2 and clock.hour == 7 and clock.minute == 30,
			"day=%d %02d:%02d" % [clock.day, clock.hour, clock.minute])
	_report("过场演完时钟恢复走时", clock.running, "")

	SleepOverlay.allow_in_headless = false
	get_tree().root.remove_child(scene)
	scene.queue_free()
	await get_tree().process_frame


# ---- 工具 ---------------------------------------------------------------

func _find_overlay(root: Node) -> SleepOverlay:
	for c: Node in root.get_children():
		if c is SleepOverlay:
			return c as SleepOverlay
	return null


func _find_bed(root: Node) -> TextureRect:
	for c: Node in root.get_children():
		if c is TextureRect:
			return c as TextureRect
	return null


func _find_clock(root: Node) -> Control:
	for c: Node in root.get_children():
		if c is SleepOverlay.ClockFace:
			return c as Control
	return null


func _find_label(root: Node, needle: String) -> Label:
	for c: Node in root.get_children():
		if c is Label and (c as Label).text.contains(needle):
			return c as Label
	return null


func _has_label(root: Node, needle: String) -> bool:
	if root == null:
		return false
	if root is Label and (root as Label).text.contains(needle):
		return true
	for c: Node in root.get_children():
		if _has_label(c, needle):
			return true
	return false


func _labels(root: Node) -> String:
	var out: String = ""
	if root == null:
		return ""
	if root is Label:
		out += (root as Label).text + " | "
	for c: Node in root.get_children():
		out += _labels(c)
	return out


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
