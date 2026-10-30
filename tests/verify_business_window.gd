extends Node
## 营业时段验收（v2：玩家按 T 开关招牌 / 22:00 系统强制关张 / 23:00 跳到次日 07:30）
##   "<godot.exe>" --headless --path . res://tests/verify_business_window.tscn --quit-after 9000
##
## 覆盖七件事：
##   1) 序章没演完不能开张；
##   2) 挂招牌窗口 07:30–18:00（太早 / 天黑都拒绝）；
##   3) 开张后顾客闸门放行、spawner 进入营业状态；
##   4) 时段客流倍率（早市 0.4 / 晚市 1.4 / 22 点后 0）；
##   5) 打烊结算自洽：进账报得出、session 清零、灯油柴火 = 4 × 营业小时；
##   6) 22:00 强制关张、23:00 自动跳到次日 07:30；
##   7) 营业中走远（离开酒馆）自动打烊。

var _pass := 0
var _fail := 0


func _ready() -> void:
	CustomerSpawner.force_disable = false
	StoryDirector.force_disable = false
	CustomerSpawner.reset_session()
	Revenue.total = 0.0
	Revenue.best_session = 0.0
	Revenue.session_total = 0.0
	await get_tree().process_frame

	# 先把阶段设成 OPEN 再挂场景：否则 world.tscn 一进来就弹序言卡，
	# 那张卡是模态的，会顶掉后面"打烊小结"的弹出（实测踩过）。
	Story.stage = StoryDirector.Stage.OPEN
	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	# 让 Story 认领本场景时钟并连上 day_changed / hour_changed
	for i in 8:
		await get_tree().process_frame

	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	var spawner: CustomerSpawner = scene.get_node_or_null("Customers") as CustomerSpawner
	if clock == null or spawner == null:
		_report("场景结构完整（Clock / Customers）", false,
				"clock=%s spawner=%s" % [clock != null, spawner != null])
		_finish()
		return

	# ---- 1) 序章未完不能开张 ----
	Story.stage = StoryDirector.Stage.NONE
	Story.business_open = false
	_report("序章未完：拒绝挂招牌", Story.open_block_reason() != "",
			"reason=%s" % Story.open_block_reason())

	# ---- 2) 挂招牌窗口 07:30–18:00 ----
	Story.stage = StoryDirector.Stage.OPEN
	clock.set_time(6, 0)
	_report("06:00 太早：拒绝挂招牌", Story.open_block_reason() != "",
			"reason=%s" % Story.open_block_reason())
	clock.set_time(19, 0)
	_report("19:00 天黑：拒绝挂招牌", Story.open_block_reason() != "",
			"reason=%s" % Story.open_block_reason())
	clock.set_time(13, 0)
	_report("13:00 白天：允许挂招牌", Story.open_block_reason() == "",
			"reason=%s" % Story.open_block_reason())

	# ---- 3) 开张 → 闸门放行 ----
	Story.toggle_business()
	_report("开张后：business_open 且 tavern_open",
			Story.business_open and Story.tavern_open(),
			"open=%s tavern=%s" % [Story.business_open, Story.tavern_open()])
	for i in 20:
		await get_tree().physics_frame
	_report("开张后：spawner 进入营业状态", spawner._running,
			"running=%s" % spawner._running)
	_report("开场 rush 打了当天标记", CustomerSpawner._rush_day == clock.day,
			"rush_day=%d / day=%d" % [CustomerSpawner._rush_day, clock.day])

	# ---- 4) 时段客流倍率 ----
	clock.set_time(8, 0)
	var f_early: float = spawner.traffic_factor()
	clock.set_time(19, 0)
	var f_peak: float = spawner.traffic_factor()
	_report("客流倍率：早市 0.4 / 晚市 1.4",
			is_equal_approx(f_early, 0.4) and is_equal_approx(f_peak, 1.4),
			"early=%.2f peak=%.2f" % [f_early, f_peak])

	# ---- 5) 打烊结算自洽 ----
	clock.set_time(18, 0)
	Story._open_abs_min = clock.day * 1440 + 18 * 60   # 强制按 18:00 开张算，稳定可控
	var hours: int = Story.business_hours()            # 同 18:00，应算 1 小时
	var copper_before: int = Inventory.copper
	Inventory.earn(50)
	await get_tree().process_frame
	var session: float = Revenue.session_total
	Story.close_business(false)
	await get_tree().process_frame
	_report("打烊后：闸门关闭", not Story.business_open and not spawner._running,
			"open=%s running=%s" % [Story.business_open, spawner._running])
	_report("结算：本次进账记到了 session（50）", is_equal_approx(session, 50.0),
			"session=%.1f" % session)
	_report("结算：session 已清零、最高单次已刷新",
			is_zero_approx(Revenue.session_total) and Revenue.best_session >= 50.0,
			"session=%.1f best=%.1f" % [Revenue.session_total, Revenue.best_session])
	# 运营开支（灯油柴火）已按用户要求去掉：进账多少铜币就多多少，不再扣钱
	_report("结算：不再扣运营开支（铜币 = 原额 + 进账）",
			Inventory.copper == copper_before + 50,
			"copper %d → %d / 营业 %d 小时" % [copper_before, Inventory.copper, hours])
	var report_panel: Node = _find_day_report()
	var modal_desc: String = ""
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		modal_desc += "%s(%s) " % [n.name, n.get_script().resource_path if n.get_script() != null else "-"]
	_report("打烊弹出今日小结面板", report_panel != null,
			"panel=%s scene=%s modal=[%s]" % [report_panel != null, Story._scene_id(),
			modal_desc])
	if report_panel != null:
		report_panel.queue_free()
	await get_tree().process_frame

	# 关张后 22 点时段倍率为 0（深夜没人来）
	clock.set_time(22, 30)
	_report("22 点后客流倍率 0", is_zero_approx(spawner.traffic_factor()),
			"f=%.2f" % spawner.traffic_factor())

	# ---- 6) 22:00 强制关张 / 23:00 跳到次日 07:30 ----
	clock.set_time(21, 0)
	Story.open_business()
	await get_tree().process_frame
	clock.set_time(21, 59)
	clock.advance(0.6)          # 1 游戏分钟 = 0.5 现实秒 → 跨到 22:00
	await get_tree().process_frame
	_report("22:00 系统强制关张", not Story.business_open,
			"open=%s hour=%d" % [Story.business_open, clock.hour])

	var day_before: int = clock.day
	clock.set_time(22, 59)
	clock.advance(0.6)          # 跨到 23:00 → 宵禁跳天
	await get_tree().process_frame
	_report("23:00 进入第二天并从 07:30 起",
			clock.day == day_before + 1 and clock.hour == 7 and clock.minute == 30,
			"day %d → %d / %02d:%02d" % [day_before, clock.day, clock.hour, clock.minute])

	# ---- 7) 营业中走远 → 自动打烊 ----
	Story.open_business()
	await get_tree().process_frame
	_report("次日 07:30 可再次开张", Story.business_open,
			"open=%s" % Story.business_open)
	Story._on_scene_changed("res://scenes/village.tscn")
	await get_tree().process_frame
	_report("离开酒馆自动打烊", not Story.business_open,
			"open=%s" % Story.business_open)

	_finish()


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s | %s" % [name, detail])
	else:
		_fail += 1
		print("[check] FAIL  %s | %s" % [name, detail])


func _find_day_report() -> Node:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if n is DayReportPanel:
			return n
	return null


func _finish() -> void:
	print("[business_window] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
