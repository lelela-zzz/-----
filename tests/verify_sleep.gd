extends Node
## 「睡觉中」过场验收：
##  · 布局 —— 最上面「睡觉中」、床在字下面居中、钟表在右上角、背景全黑；
##  · 动画 —— 指针真的在转、省略号在跳、播完发 finished 并自己销毁；
##  · 接入 —— headless/无 UI 时同步瞬跳（38 套回归的保命语义）；
##  · 回店 —— 23:00 后回到酒馆：先旁白「累了一天了…」再进过场，最后才跨天；
##  · 钉住 —— 不在酒馆熬到 23:00：时间挂起、day 不变，advance 也推不动。
##
## 跑法： "<godot>" --headless --path . res://tests/verify_sleep.tscn --quit-after 9000

const WORLD: String = "res://scenes/world.tscn"
const VILLAGE: String = "res://scenes/village.tscn"
## 旁白 + 过场的总等待（旁白 3.0 + 淡入 0.28 + 停留 2.0 + 淡出 0.32 + 余量）
const ENTRANCE_WAIT: float = 3.0 + SleepOverlay.FADE_IN_SEC + SleepOverlay.HOLD_SEC \
		+ SleepOverlay.FADE_OUT_SEC + 0.35

var _pass: int = 0
var _fail: int = 0
var _scene: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await _check_layout_and_anim()
	_check_headless_sync()
	await _check_entrance_sleep()
	await _check_pinned_outside()
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
	var dim: ColorRect = _find_dim(ov)

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
	_report("背景是完全遮死的暗色（alpha=1.0）",
			dim != null and dim.color.a >= 0.999,
			"dim=%s" % ("null" if dim == null else str(dim.color)))

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


# ---- 3. 回店睡觉：旁白 → 过场 → 跨天 -------------------------------------

func _check_entrance_sleep() -> void:
	SleepOverlay.allow_in_headless = true
	GameClock.reset_day(1)    # day 是 static 共享的，先起表
	await _mount(WORLD)
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = false

	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	_report("world 场景有时钟", clock != null, "")
	if clock == null:
		SleepOverlay.allow_in_headless = false
		return

	# 序章卡片是 UiPanel（modal 组），测试里没人按 E 翻页 → 会一直挂着，
	# 把 _sleep_sequence 的「等 modal 让位」卡死。真实游戏里玩家随手就关了。
	var ui: Node = UiStyle.ui_layer(clock)
	for c: Node in (ui.get_children() if ui != null else []):
		if c is PrologueCard:
			(c as PrologueCard).queue_free()
	await get_tree().process_frame

	# 模拟"23:00 后从村里走门回酒馆"：走门会经 SceneBootstrap.set_time 落时刻
	clock.set_time(23, 0)
	await get_tree().process_frame
	await get_tree().process_frame

	_report("回店先弹旁白（累了一天了…）",
			_has_label(ui, GameClock.NARRATION_TEXT), _labels(ui))
	_report("旁白阶段时间还没跳（仍是第 1 天 23:00）",
			clock.day == 1 and clock.hour == 23 and clock.minute == 0,
			"day=%d %s" % [clock.day, clock.get_time_string()])

	await get_tree().create_timer(GameClock.NARRATION_SEC + 0.4).timeout
	var ov: SleepOverlay = _find_overlay(ui)
	_report("旁白之后过场接上（睡觉中）", ov != null, "")
	_report("过场期间时钟被掐停", clock != null and not clock.running, "")

	await get_tree().create_timer(ENTRANCE_WAIT).timeout
	# 分钟放宽：跨天完成到断言之间时钟已恢复走时，会多走几分钟 —— 起跳点必然是 07:30+
	_report("睡完 → 第 2 天早晨（07:30 起跳）",
			clock.day == 2 and clock.hour == 7 and clock.minute >= 30,
			"day=%d %s" % [clock.day, clock.get_time_string()])
	_report("睡完时钟恢复走时", clock.running, "")

	SleepOverlay.allow_in_headless = false
	await _unmount()


# ---- 4. 不在酒馆：23:00 钉住，推不动 --------------------------------------

func _check_pinned_outside() -> void:
	SleepOverlay.allow_in_headless = true
	GameClock.reset_day(1)
	await _mount(VILLAGE)

	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	_report("village 场景有时钟", clock != null, "")
	if clock == null:
		SleepOverlay.allow_in_headless = false
		return

	clock.running = false
	clock.set_time(22, 59)
	# 1 游戏分钟 = seconds_per_hour/60 现实秒 → 跨进 23:00
	clock.advance(clock.seconds_per_hour / 60.0)
	_report("村外熬到 23:00：day 不变（没人替你睡）", clock.day == 1,
			"day=%d %s" % [clock.day, clock.get_time_string()])

	# 再硬推一小时：应该被钉住，纹丝不动
	clock.advance(30.0)
	_report("23:00 后 advance 推不动（时间钉住）",
			clock.hour == 23 and clock.minute == 0 and clock.day == 1,
			"day=%d %s" % [clock.day, clock.get_time_string()])
	_report("钉住时没拉过场（村外不睡）", _find_overlay(_top_ui()) == null, "")

	SleepOverlay.allow_in_headless = false
	await _unmount()


# ---- 场景装卸 / 工具 -----------------------------------------------------

func _mount(path: String) -> void:
	if _scene != null and is_instance_valid(_scene):
		get_tree().root.remove_child(_scene)
		_scene.queue_free()
		await get_tree().process_frame
	_scene = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	await get_tree().process_frame
	await get_tree().process_frame


func _unmount() -> void:
	if _scene != null and is_instance_valid(_scene):
		get_tree().root.remove_child(_scene)
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame


func _top_ui() -> Node:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("HUD/UIRoot")


func _find_overlay(root: Node) -> SleepOverlay:
	if root == null:
		return null
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


func _find_dim(root: Node) -> ColorRect:
	for c: Node in root.get_children():
		if c is ColorRect:
			return c as ColorRect
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
