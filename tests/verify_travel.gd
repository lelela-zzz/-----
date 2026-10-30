extends Node
## 快速前往（跑路）验收：
##  · 跑路时长 = 地图图各跳 minutes 之和；同图 0；未知 -1；
##  · 遮罩里有「跑路中」和钟；
##  · **播完真的把游戏时钟推进了**（10 分钟 → 07:30 变 07:40），不是纯装饰；
##  · 遮罩播完自己销毁、且跑路期间占着 modal_ui（别的面板弹不出来）。
##
## 纯逻辑 + 一个独立 GameClock，不需要渲染，headless 可跑（含约 1.4s 真实等待）。

const WORLD: String = "res://scenes/world.tscn"
const VILLAGE: String = "res://scenes/village.tscn"

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_check_minutes()
	await _check_overlay_advances_clock()
	_finish()


## --- 用例 ---------------------------------------------------------------

func _check_minutes() -> void:
	_report("world → village 跑路 10 分钟（2+8）",
			MapGraph.travel_minutes(WORLD, VILLAGE) == 10,
			"%d" % MapGraph.travel_minutes(WORLD, VILLAGE))
	_report("village → world 跑路 10 分钟",
			MapGraph.travel_minutes(VILLAGE, WORLD) == 10,
			"%d" % MapGraph.travel_minutes(VILLAGE, WORLD))
	_report("同图 = 0 分钟（不用跑，直接瞬移）",
			MapGraph.travel_minutes(WORLD, WORLD) == 0,
			"%d" % MapGraph.travel_minutes(WORLD, WORLD))
	_report("未知去处 = -1（调用方自己兜底）",
			MapGraph.travel_minutes(WORLD, "res://scenes/nope.tscn") == -1,
			"%d" % MapGraph.travel_minutes(WORLD, "res://scenes/nope.tscn"))
	_report("跨图耗时随跳数增长（world→mine > world→village）",
			MapGraph.travel_minutes(WORLD, "res://scenes/mine.tscn")
					> MapGraph.travel_minutes(WORLD, VILLAGE),
			"%d > %d" % [MapGraph.travel_minutes(WORLD, "res://scenes/mine.tscn"),
					MapGraph.travel_minutes(WORLD, VILLAGE)])


func _check_overlay_advances_clock() -> void:
	var clock: GameClock = GameClock.new()
	clock.start_hour = 7
	clock.start_minute = 30
	clock.running = false
	add_child(clock)
	await get_tree().process_frame
	_report("测试时钟起点 07:30", clock.get_time_string() == "07:30", clock.get_time_string())

	var host: Control = Control.new()
	host.size = Vector2(640, 384)
	add_child(host)
	var ov: TravelOverlay = TravelOverlay.new()
	host.add_child(ov)
	await get_tree().process_frame

	_report("遮罩里有「跑路中」", _has_label(ov, "跑路中"), _labels(ov))
	_report("遮罩跑路期间占着 modal_ui（别让别的面板弹出来）",
			ov.is_in_group("modal_ui"), "")

	ov.begin(clock, 7, 30, 10, "", Vector2.ZERO)
	await get_tree().create_timer(TravelOverlay.SWEEP_SEC + 0.28).timeout

	_report("跑完 10 分钟后时钟到 07:40（时间真的被消耗）",
			clock.get_time_string() == "07:40", clock.get_time_string())
	clock.running = false
	_report("遮罩播完自己销毁（不残留）",
			not is_instance_valid(ov) or not ov.is_inside_tree(),
			"valid=%s" % str(is_instance_valid(ov)))


## --- 工具 ---------------------------------------------------------------

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
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _finish() -> void:
	print("[travel] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
