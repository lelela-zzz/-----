extends Node
## UI 验收（营业状态条 / 账簿 / 打烊小结）：
##   "<godot.exe>" --headless --path . res://tests/verify_ui_panels.tscn --quit-after 9000
##
## 覆盖：
##   1) BusinessHud 注入到 HUD/UIRoot，随营业状态改文案（未开张 → 营业中）
##   2) LedgerPanel：按酒种分列 收入 / 销售 / 剩余，不再有成本/毛利/用料/可酿明细
##   3) DayReportPanel：把 report 塞进去后，数值真的渲染到界面上
##
## 只查"标签文本里有没有这串字"，不比对像素 —— 版式调整不该让用例红。

var _pass := 0
var _fail := 0


func _ready() -> void:
	TestView.logic_resolution()
	CustomerSpawner.force_disable = true     # 不掺顾客，专心测 UI
	StoryDirector.force_disable = false
	await get_tree().process_frame

	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	for i in 6:
		await get_tree().process_frame

	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	var ui: Node = scene.get_node_or_null("HUD/UIRoot")
	if clock == null or ui == null:
		_report("场景结构完整（Clock / UIRoot）", false,
				"clock=%s ui=%s" % [clock != null, ui != null])
		_finish()
		return

	Story.stage = StoryDirector.Stage.OPEN
	clock.set_time(13, 0)
	await get_tree().process_frame

	# ---- 1) 营业状态条 ----
	var hud_node: Node = null
	for n: Node in _walk(ui):
		if n is BusinessHud:
			hud_node = n
			break
	_report("HUD 里有营业状态条", hud_node != null, "node=%s" % hud_node)
	if hud_node != null:
		await get_tree().process_frame
		var texts: Array[String] = _labels(hud_node)
		_report("未开张时状态条提示挂招牌", _any_contains(texts, "[T] 挂招牌"),
				"labels=%s" % [texts])
		_report("状态条显示今日预计客流", _any_contains(texts, "预计客流"),
				"labels=%s" % [texts])
		_report("身处酒馆（world）：状态条可见",
				(hud_node as Control).visible, "visible=%s" % (hud_node as Control).visible)

	Story.open_business()
	await get_tree().process_frame
	await get_tree().process_frame
	if hud_node != null:
		var texts2: Array[String] = _labels(hud_node)
		_report("开张后状态条写「营业中」并带今日进账",
				_any_contains(texts2, "营业中") and _any_contains(texts2, "今日"),
				"labels=%s" % [texts2])
		_report("营业中显示已来人数", _any_contains(texts2, "已来"),
				"labels=%s" % [texts2])

	# ---- 2) 账簿（按酒种分列：今日收入 / 销售 / 剩余）----
	var ps: PackedScene = load("res://scenes/ui/ledger_panel.tscn") as PackedScene
	var ledger: LedgerPanel = ps.instantiate() as LedgerPanel
	ui.add_child(ledger)
	await get_tree().process_frame
	await get_tree().process_frame

	# 造一份"经营台账"数据：累计营业额 118；姜酒累计卖 4 剩 5、淡啤卖 3 剩 3、烈啤剩 2
	Inventory.clear()
	Inventory.add("wine_warm_ginger", 5)
	Inventory.add("wine_river_ale", 3)
	Inventory.add("wine_burnt_ale", 2)
	Revenue.total = 118.0
	Revenue.total_wines_by_id = {"wine_warm_ginger": 4, "wine_river_ale": 3}
	await get_tree().process_frame
	var ltext: Array[String] = _labels(ledger)
	_report("账簿显示累计营业额 118 铜", _any_contains(ltext, "118"),
			"labels=%s" % [ltext])
	_report("账簿按酒种列出（出现酒名）", _any_contains(ltext, "暖身姜酒"),
			"labels=%s" % [ltext])
	_report("销售列按酒种拆分（姜酒卖出 ×4）", _any_contains(ltext, "×4"),
			"labels=%s" % [ltext])
	_report("剩余列按酒种拆分（姜酒剩余 ×5）", _any_contains(ltext, "×5"),
			"labels=%s" % [ltext])
	_report("账簿不再列成本/毛利/用料/可酿明细",
			not _any_contains(ltext, "成本") and not _any_contains(ltext, "毛利")
			and not _any_contains(ltext, "用料") and not _any_contains(ltext, "可酿"),
			"labels=%s" % [ltext])
	ledger.close()
	await get_tree().process_frame

	# ---- 3) 打烊小结 ----
	var rps: PackedScene = load("res://scenes/ui/day_report_panel.tscn") as PackedScene
	var report: DayReportPanel = rps.instantiate() as DayReportPanel
	report.report = {
		"day": 3, "revenue": 235, "wines": 13, "hours": 4,
		"best": 235, "forced": true,
	}
	ui.add_child(report)
	await get_tree().process_frame
	await get_tree().process_frame
	var rtext: Array[String] = _labels(report)
	_report("小结卡写出今日进账 235 铜", _any_contains(rtext, "235"), "labels=%s" % [rtext])
	_report("小结卡写出售出 13 瓶", _any_contains(rtext, "13 瓶"), "labels=%s" % [rtext])
	# 2026-10-30：解锁进度（营业额 / 认识名单）搬进任务栏的「准备清单」，
	# 结算卡只报"今晚赚了多少"，不该再兼职当进度条。
	_report("小结卡不再显示雪山委托进度", not _any_contains(rtext, "雪山委托"),
			"labels=%s" % [rtext])
	report.close()

	# ---- 4) 离开酒馆：状态条必须整个收起来 ----
	# 村庄也有 HUD/UIRoot（状态条同样会被注进去），所以这里验的是"不可见"
	# 而不是"不存在" —— 只看有没有节点会漏判。
	var village_scene: Node = (load("res://scenes/village.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(village_scene)
	get_tree().current_scene = village_scene
	scene.queue_free()
	for i in 6:
		await get_tree().process_frame
	var v_ui: Node = village_scene.get_node_or_null("HUD/UIRoot")
	var v_hud: Node = null
	if v_ui != null:
		for n: Node in _walk(v_ui):
			if n is BusinessHud:
				v_hud = n
				break
	var v_vis: bool = (v_hud as Control).visible if v_hud != null else false
	_report("离开酒馆后状态条不显示", v_hud == null or not v_vis,
			"village: found=%s visible=%s" % [v_hud != null, v_vis])

	_finish()


## 递归收集子节点（面板里 new() 出来的节点名字不确定，只能按类型/内容找）。
func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c: Node in root.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _labels(root: Node) -> Array[String]:
	var out: Array[String] = []
	if root is Label:
		out.append((root as Label).text)
	for c: Node in root.get_children():
		out.append_array(_labels(c))
	return out


func _any_contains(texts: Array[String], needle: String) -> bool:
	for t: String in texts:
		if t.find(needle) >= 0:
			return true
	return false


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s | %s" % [name, detail])
	else:
		_fail += 1
		print("[check] FAIL  %s | %s" % [name, detail])


func _finish() -> void:
	print("[ui_panels] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
