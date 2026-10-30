extends Node
## 「睡到明天」跳天验收：
##   1) can_skip_day 门：序章未完 / 营业中 → false；关门 + 在店里 → true
##   2) [X] 双按确认：第一按只武装（天不翻），窗口内第二按才跳
##   3) headless 同步跳：skip_to_morning → day+1、早上 07:30
## 运行： "<godot.exe>" --headless --path . res://tests/verify_skip_day.tscn --quit-after 9000

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = false
	await get_tree().process_frame
	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	for i in 8:
		await get_tree().process_frame
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	Story.stage = StoryDirector.Stage.OPEN
	Story.business_open = false
	await get_tree().process_frame

	_report("关门 + 在店里 + 序章完：可以睡到明天", Story.can_skip_day(),
			"can=%s" % Story.can_skip_day())

	Story.business_open = true
	_report("营业中不能跳", not Story.can_skip_day(), "")
	Story.business_open = false

	Story.stage = StoryDirector.Stage.BREW
	_report("序章未完不能跳", not Story.can_skip_day(), "")
	Story.stage = StoryDirector.Stage.OPEN

	# ---- [X] 双按确认 ----
	var day0: int = clock.day
	Story._skip_armed_at = -1_000_000   # 从"未武装"开始
	Story._try_skip_day()
	await get_tree().process_frame
	_report("第一按只确认，天没翻", clock.day == day0,
			"day=%d (期望 %d)" % [clock.day, day0])
	Story._try_skip_day()
	await get_tree().process_frame
	await get_tree().process_frame
	_report("第二按翻天：day+1、早上 07:30",
			clock.day == day0 + 1 and clock.hour == 7 and clock.minute == 30,
			"day=%d time=%s" % [clock.day, clock.get_time_string()])

	_finish()


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s" % name)
	else:
		_fail += 1
		print("[check] FAIL  %s  (%s)" % [name, detail])


func _finish() -> void:
	print("[skip_day] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
