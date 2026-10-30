extends Control
## 任务清单面板（按 Q）验收 —— 2026-10-30 改版【逐步揭示】：
##  1. 面板一次最多露**两条**：刚做完的那条 + 正在做的这条，没轮到的全藏着；
##  2. 做完一条 → 第三条补进来，同时把上上条挤掉（窗口往前滑一格）；
##  3. 留在屏上的"刚做完"那条：标题 ✓ 压暗，和正在做的 ◆ 火心色区分开；
##  4. 全部做完 → 屏上只剩最后一条（已完成态）；
##  5. 单个任务内容超长时仍然可以滚轮上下滑（ScrollContainer 那条链路没坏）。
##
## 窗口逻辑（数据层）在 QuestLog.visible()，这里盯「数据窗口」和「UI 呈现」两头都对。
## ⚠ pending() 仍是"所有未完成的段"（追踪卡要真实数量），别和 visible() 混。
##
## 纯逻辑 + 控件坐标断言，不需要渲染，headless 可跑（滚动条范围需等一帧布局）。

const QUEST_PANEL: String = "res://scenes/ui/quest_panel.tscn"
const FRAME_BOTTOM: int = 336        # FRAME(88,48,464,288) 的下沿
const CONTENT_TOP: float = 96.0       # 内容区第一行：FRAME.y(48)+描边2 + HEADER_H(42)+INNER_TOP(4)
const ROW_H: int = 14

var passed: int = 0
var failed: int = 0
var panel: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true

	_reset()
	_check_window_data()
	_check_window_ui()
	await _check_overflow_guard()
	_check_all_done()
	_check_tracking()
	QuestLog.reset()
	_finish()


## --- 1. 数据层：窗口怎么滑 -----------------------------------------------

func _check_window_data() -> void:
	QuestLog.reset()
	QuestLog.add("a", "任务A")
	QuestLog.add_step("a", "A步")
	QuestLog.add("b", "任务B")
	QuestLog.add_step("b", "B步")
	QuestLog.add("c", "任务C")
	QuestLog.add_step("c", "C步")

	_report("三条都没做完：只露第一条", _ids(QuestLog.visible()) == ["a"],
			"%s" % str(_ids(QuestLog.visible())))

	QuestLog.set_step_done("a", 0, true)
	_report("第一条做完：它留着，第二条补进来", _ids(QuestLog.visible()) == ["a", "b"],
			"%s" % str(_ids(QuestLog.visible())))

	QuestLog.set_step_done("b", 0, true)
	_report("第二条做完：第一条被挤掉，第三条出现", _ids(QuestLog.visible()) == ["b", "c"],
			"%s" % str(_ids(QuestLog.visible())))

	QuestLog.set_step_done("c", 0, true)
	_report("全部做完：屏上只剩最后一条", _ids(QuestLog.visible()) == ["c"],
			"%s" % str(_ids(QuestLog.visible())))

	# 窗口只管呈现，pending() 仍要真实的未完成数量（追踪卡用）
	QuestLog.reset()
	QuestLog.add("x", "X")
	QuestLog.add_step("x", "X步")
	QuestLog.add("y", "Y")
	QuestLog.add_step("y", "Y步")
	_report("pending() 不受窗口影响，仍是全部未完成段",
			QuestLog.pending().size() == 2 and QuestLog.visible().size() == 1,
			"pending=%d visible=%d" % [QuestLog.pending().size(), QuestLog.visible().size()])


## --- 2. UI： appears / 滑走 / 完成态 -------------------------------------

func _check_window_ui() -> void:
	QuestLog.reset()
	QuestLog.add("a", "去集市", "备料。")
	QuestLog.add_step("a", "走出酒馆")
	QuestLog.add("b", "采购酿酒材料")
	QuestLog.add_step("b", "生姜", 4)
	QuestLog.add("c", "试试酿造机")
	QuestLog.add_step("c", "酿一瓶")

	panel = _open_panel()
	var rows: Array[Dictionary] = _rows()

	_report("初始只露第一条（后面两条藏着）",
			_has(rows, "◆ 去集市") and not _has(rows, "采购酿酒材料")
			and not _has(rows, "试试酿造机"),
			"%s" % _texts(rows))
	_report("第一条顶在内容区顶部", _y_of(rows, "去集市") == CONTENT_TOP,
			"y=%s" % _y_of(rows, "去集市"))

	# 做完第一条 → 第二条补进来，第一条留着但转成"已完成"
	QuestLog.set_step_done("a", 0, true)
	rows = _rows()
	_report("做完的那条留着、标题转完成态 ✓",
			_has(rows, "✓ 去集市") and not _has(rows, "◆ 去集市"), "%s" % _texts(rows))
	_report("新的一条是未完成态 ◆", _has(rows, "◆ 采购酿酒材料"), "%s" % _texts(rows))
	_report("已完成那条在上、正在做的在下",
			_y_of(rows, "✓ 去集市") < _y_of(rows, "◆ 采购酿酒材料"),
			"%s < %s" % [_y_of(rows, "✓ 去集市"), _y_of(rows, "◆ 采购酿酒材料")])
	_report("还没轮到的第三条仍然藏着", not _has(rows, "试试酿造机"), "%s" % _texts(rows))
	_report("所有行都在框内（不溢出）", _in_frame(rows), _overflow_detail(rows))

	# 做完第二条 → 第一条滑走，第二条转完成，第三条出现
	QuestLog.set_step_done("b", 0, true)
	rows = _rows()
	_report("再做完一条：上上条滑出窗口", not _has(rows, "去集市"), "%s" % _texts(rows))
	_report("刚做完的第二条转完成态 ✓", _has(rows, "✓ 采购酿酒材料"), "%s" % _texts(rows))
	_report("第三条出现且是未完成态 ◆", _has(rows, "◆ 试试酿造机"), "%s" % _texts(rows))
	_report("旧段的步骤不残留在画面上",
			not _has(rows, "走出酒馆") and not _has(rows, "生姜 0/4"), "%s" % _texts(rows))

	# 段内步骤：完成打 ✓、计数型带进度，照旧
	rows = _rows()
	_report("计数型步骤仍渲染", _has(rows, "· 生姜 0/4") or _has(rows, "✓ 生姜"),
			"%s" % _texts(rows))


## --- 3. 滚动：单段内容超长时仍要能滑 -------------------------------------

## 窗口最多两条之后，靠"段数"已经撑不爆面板了 —— 所以这条改用
## **一个任务塞很多步**来验证滚动链路没被这次改动弄坏。
func _check_overflow_guard() -> void:
	QuestLog.reset()
	QuestLog.add("big", "超长任务", "这是一条用来把面板撑爆的描述文字。")
	for k: int in 20:
		QuestLog.add_step("big", "步骤%d" % k)

	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = _open_panel()
	await get_tree().process_frame   # 等一帧让滚动条算出范围
	var sc: ScrollContainer = _find_scroll(panel)
	var inner: Control = _find_inner(sc)
	var bar: ScrollBar = sc.get_v_scroll_bar() if sc != null else null

	_report("内容超出框高 → 开启竖向滚动", sc != null
			and sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"v_mode=%s" % (sc.vertical_scroll_mode if sc != null else "无"))
	_report("横向滚动被禁用（只上下滑）", sc != null
			and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"h_mode=%s" % (sc.horizontal_scroll_mode if sc != null else "无"))
	_report("内层内容高于可视区 → 确实可滚",
			inner != null and sc != null and inner.size.y > sc.size.y,
			"inner=%s scroll=%s" % [inner.size.y if inner != null else "?", sc.size.y if sc != null else "?"])
	_report("滚动条存在且范围 > 一页", bar != null and bar.max_value > bar.page,
			"max=%s page=%s" % [bar.max_value if bar != null else "?", bar.page if bar != null else "?"])

	if sc != null and bar != null and bar.max_value > 0.0:
		sc.scroll_vertical = 0
		await get_tree().process_frame
		var before: float = sc.scroll_vertical
		sc.scroll_vertical = 50.0
		await get_tree().process_frame
		var after: float = sc.scroll_vertical
		_report("可滚动：偏移能被推到 >0（滚轮/拖动通道可用）", after > before,
				"before=%s after=%s" % [before, after])


## --- 4. 全部完成 ---------------------------------------------------------

func _check_all_done() -> void:
	QuestLog.reset()
	QuestLog.add("z", "收尾任务")
	QuestLog.add_step("z", "最后一步")
	QuestLog.complete("z")
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = _open_panel()
	var rows: Array[Dictionary] = _rows()
	_report("全部做完：最后一条留在屏上，且是完成态 ✓",
			_has(rows, "✓ 收尾任务"), "%s" % _texts(rows))

	QuestLog.reset()
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = _open_panel()
	_report("一个任务都没有时给空态文案",
			_has(_rows(), "暂时没有任务。"), "%s" % _texts(_rows()))


## --- 5. 追踪 -------------------------------------------------------------

func _check_tracking() -> void:
	QuestLog.reset()
	QuestLog.add("a", "去集市", "备料。")
	QuestLog.add_step("a", "走出酒馆")
	QuestLog.add("b", "采购酿酒材料")
	QuestLog.add_step("b", "生姜", 4)
	QuestLog.add("c", "试试酿造机")
	QuestLog.add_step("c", "酿一瓶")
	QuestLog.set_step_done("a", 0, true)   # 让窗口有两条：a(完成) + b(进行)

	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = _open_panel()

	_report("初始未追踪任何任务", QuestLog.tracked_id() == "",
			"tracked=%s" % QuestLog.tracked_id())

	var btns: Array[Dictionary] = _buttons(panel)
	_report("窗口里两条 → 两枚追踪按钮", btns.size() == 2,
			"%d 枚" % btns.size())

	var rows0: Array[Dictionary] = _rows()
	_report("未追踪时正在做的那条用 ◆ 火心色",
			_has(rows0, "◆ 采购酿酒材料")
			and _color_of(rows0, "采购酿酒材料") == UiStyle.FIRE_CORE,
			"%s" % _texts(rows0))

	var yb: float = _y_of(rows0, "采购酿酒材料")
	var btn_b: Button = _button_near(btns, yb)
	_report("能定位到第二条（正在做的）的追踪按钮", btn_b != null, "y=%s" % yb)
	if btn_b != null:
		btn_b.pressed.emit()

	var rows1: Array[Dictionary] = _rows()
	_report("点追踪后 QuestLog.tracked_id = b", QuestLog.tracked_id() == "b",
			"tracked=%s" % QuestLog.tracked_id())
	_report("被追踪段标题加 ★", _has(rows1, "★ 采购酿酒材料"), "%s" % _texts(rows1))
	_report("被追踪段标题染金色", _color_of(rows1, "采购酿酒材料") == UiStyle.GOLD,
			"color=%s" % _color_of(rows1, "采购酿酒材料"))
	_report("被追踪段按钮变『取消追踪』", _has_btn(panel, "取消追踪"), "%s" % _btn_texts(panel))
	_report("另一条按钮仍是『追踪』", _has_btn(panel, "追踪"), "%s" % _btn_texts(panel))

	# 再点自己 → 取消（set_tracked 是切换语义）
	var btn_b2: Button = _button_near(_buttons(panel), _y_of(_rows(), "采购酿酒材料"))
	if btn_b2 != null:
		btn_b2.pressed.emit()
	_report("再点自己 → 取消追踪", QuestLog.tracked_id() == "",
			"tracked=%s" % QuestLog.tracked_id())


## --- 工具 ---------------------------------------------------------------

func _reset() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = null
	QuestLog.reset()


func _open_panel() -> Node:
	var ps: PackedScene = load(QUEST_PANEL) as PackedScene
	var p: Node = ps.instantiate()
	add_child(p)
	return p


func _ids(qs: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for q: Dictionary in qs:
		out.append(str(q["id"]))
	return out


## 面板里所有 Label 的 {text, y, color}（y 为相对视口的纵坐标）。
func _rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if panel == null or not is_instance_valid(panel):
		return out
	_collect(panel, out)
	return out


func _collect(node: Node, out: Array[Dictionary]) -> void:
	var c: Control = node as Control
	if c is Label:
		out.append({"text": (c as Label).text, "y": _abs_y(c),
				"color": (c as Label).get_theme_color("font_color")})
	for child: Node in node.get_children():
		_collect(child, out)


func _abs_y(c: Control) -> float:
	var y: float = c.position.y
	var p: Node = c.get_parent()
	while p is Control:
		y += (p as Control).position.y
		p = p.get_parent()
	return y


func _has(rows: Array[Dictionary], needle: String) -> bool:
	for r: Dictionary in rows:
		if str(r["text"]).contains(needle):
			return true
	return false


func _y_of(rows: Array[Dictionary], needle: String) -> float:
	for r: Dictionary in rows:
		if str(r["text"]).contains(needle):
			return float(r["y"])
	return -1.0


func _in_frame(rows: Array[Dictionary]) -> bool:
	for r: Dictionary in rows:
		if float(r["y"]) + ROW_H > float(FRAME_BOTTOM):
			return false
	return true


func _overflow_detail(rows: Array[Dictionary]) -> String:
	var worst: float = 0.0
	var worst_text: String = ""
	for r: Dictionary in rows:
		if float(r["y"]) > worst:
			worst = float(r["y"])
			worst_text = str(r["text"])
	return "最低行 y=%s 「%s」（框底 %d）" % [worst, worst_text, FRAME_BOTTOM]


func _texts(rows: Array[Dictionary]) -> String:
	var s: String = ""
	for r: Dictionary in rows:
		s += str(r["text"]) + " | "
	return s


func _buttons(p: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if p == null or not is_instance_valid(p):
		return out
	_collect_buttons(p, out)
	return out


func _collect_buttons(node: Node, out: Array[Dictionary]) -> void:
	var b: Button = node as Button
	if b != null:
		out.append({"text": b.text, "y": _abs_y(b), "node": b})
	for child: Node in node.get_children():
		_collect_buttons(child, out)


## 给定标题的纵坐标，找回同一段（y 几乎对齐）的那枚追踪按钮。
func _button_near(btns: Array[Dictionary], y: float) -> Button:
	var best: Button = null
	var best_d: float = 99.0
	for b: Dictionary in btns:
		var d: float = absf(float(b["y"]) - y)
		if d < best_d:
			best_d = d
			best = b["node"]
	return best


func _btn_texts(p: Node) -> String:
	var s: String = ""
	for b: Dictionary in _buttons(p):
		s += str(b["text"]) + " | "
	return s


func _has_btn(p: Node, needle: String) -> bool:
	for b: Dictionary in _buttons(p):
		if str(b["text"]).contains(needle):
			return true
	return false


func _color_of(rows: Array[Dictionary], needle: String) -> Color:
	for r: Dictionary in rows:
		if str(r["text"]).contains(needle):
			return r["color"]
	return Color.BLACK


func _find_scroll(p: Node) -> ScrollContainer:
	if p is ScrollContainer:
		return p as ScrollContainer
	for c: Node in p.get_children():
		var r: ScrollContainer = _find_scroll(c)
		if r != null:
			return r
	return null


func _find_inner(sc: ScrollContainer) -> Control:
	for c: Node in sc.get_children():
		if c is Control and not (c is ScrollBar):
			return c as Control
	return null


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _finish() -> void:
	print("[quest_panel] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
