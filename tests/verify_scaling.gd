extends Node
## 无窗口验收：为"以后还要加酒、加料"留的扩展位还能不能撑住。
## 跑法：godot --headless --path . res://tests/verify_scaling.tscn
##
## 测三件事：
##  1. ListWindow 的窗口算术（翻页、对齐、边界）；
##  2. ingredient_columns 在 1..8 味料时都能排进行宽、互不重叠；
##  3. 物品图标的规格（正方形、32 的整数倍），以及 ItemDB 的扩展查询。

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	print("[scale] ── 列表窗口 ──")
	_test_window_basic()
	_test_window_wrap()
	_test_window_align()

	print("[scale] ── 料位自动排布 ──")
	_test_columns()

	print("[scale] ── 采集点（未来地图的取料口）──")
	await _test_gather_spot()

	print("[scale] ── 数据与图形规格 ──")
	_test_item_data()
	_test_panel_geometry()
	_test_many_recipes()

	print("[scale] 结论：PASS %d / FAIL %d" % [_pass, _fail])
	print("[scale] 总判定: %s" % ("PASS" if _fail == 0 else "FAIL"))
	get_tree().quit()


func _test_window_basic() -> void:
	var w: ListWindow = ListWindow.new()
	w.configure(8, 5, false)
	_check("8 条 / 一屏 5 条：初始窗口在头部", w.first() == 0 and w.last() == 4)
	w.move(4)
	_check("选到第 5 条仍在首屏", w.index == 4 and w.first() == 0)
	w.move(1)
	_check("越过末行自动滚一格", w.index == 5 and w.first() == 1, "first=%d" % w.first())
	_check("滚动后该条落在第 5 行", w.slot_of(5) == 4, "slot=%d" % w.slot_of(5))
	_check("滚过之后上下都还有内容（8 条时窗口在中段）", w.has_above() and w.has_below())
	w.move(10)
	_check("顶到底时夹紧不越界", w.index == 7, "index=%d" % w.index)
	_check("滚到底时窗口贴合末尾", w.first() == 3, "first=%d" % w.first())
	_check("需要滚动时给出行号提示", w.indicator() == "8/8", w.indicator())

	var small: ListWindow = ListWindow.new()
	small.configure(3, 5, false)
	_check("条目比一屏少时不显示滚动提示", small.indicator() == "")


func _test_window_wrap() -> void:
	var w: ListWindow = ListWindow.new()
	w.configure(5, 5, true)
	w.set_index(4)
	w.move(1)
	_check("回绕模式：末条再往下回到第一条", w.index == 0 and w.first() == 0)
	w.move(-1)
	_check("回绕模式：第一条再往上回到末条", w.index == 4)


func _test_window_align() -> void:
	var w: ListWindow = ListWindow.new()
	w.configure(25, 10, false, 2)
	w.move(10)
	_check("两列模式：选中第 11 条时窗口起点仍是偶数",
			w.first() % 2 == 0 and w.first() <= 10 and 10 < w.first() + 10, "first=%d" % w.first())
	_check("两列模式：可见区间完整覆盖 10 格", w.last() - w.first() + 1 == 10)
	var text: String = w.range_text()
	_check("两列模式给出区间文案", text != "" and text.contains("/"), text)


func _test_columns() -> void:
	var start: int = 100
	var end: int = 382
	for n in [1, 2, 3, 4, 5, 6, 8]:
		var names: Array[String] = []
		var counts: Array[int] = []
		for i in n:
			names.append(["焦麦", "雪山泉", "月痕河泉", "白米", "生姜", "蜂蜜", "野莓", "麦茶"][i % 8])
			counts.append(2)
		var cols: Array[Dictionary] = BrewingPanel.ingredient_columns(names, counts, start, end)
		var count_ok: bool = cols.size() == n
		var inside: bool = true
		var overlap: bool = false
		var prev_right: int = -9999
		for c: Dictionary in cols:
			if int(c["icon_x"]) < start or int(c["icon_x"]) + 32 > end:
				inside = false
			if int(c["icon_x"]) < prev_right:
				overlap = true
			prev_right = int(c["icon_x"]) + 32
		_check("%d 味料：数量对、不越界、不重叠" % n, count_ok and inside and not overlap,
				"数量 %d / 越界 %s / 重叠 %s" % [cols.size(), not inside, overlap])

	# 放不下时会降级成更短的写法，最后兜底只留图标
	var many_names: Array[String] = []
	var many_counts: Array[int] = []
	for i in 8:
		many_names.append("月痕河泉")
		many_counts.append(1)
	var many: Array[Dictionary] = BrewingPanel.ingredient_columns(many_names, many_counts, start, end)
	var all_icon_only: bool = true
	for c: Dictionary in many:
		if str(c["text"]) != "":
			all_icon_only = false
	_check("8 味长名字料：降级到只画图标也不出界", all_icon_only and many.size() == 8, str(many.size()))


## 采集点：按地点自动出料、按固定顺序轮转、冷却期内不给。
func _test_gather_spot() -> void:
	var spot: GatherSpot = GatherSpot.new()
	spot.map_name = "黑松山脉"
	spot.spot = "矿道入口"
	spot.cooldown_minutes = 90.0
	add_child(spot)
	await get_tree().process_frame

	_check("采集池按地点自动从数据里取（3 种）", spot.pool.size() == 3, str(spot.pool))
	_check("提示词默认是「采集」", spot.prompt_text == "采集", spot.prompt_text)

	Inventory.clear()
	# 用 pool 的实际顺序来断言"按顺序轮转"，不写死具体是哪味料 ——
	# 否则一改 items.json 的价格（排序依据 price→name），这里就会假失败。
	var pool: Array[String] = spot.pool
	var a: String = spot.gather()
	_check("第一次采集给出池中第一味料", pool.size() > 0 and a == pool[0], a)
	_check("进库存了", Inventory.count(a) == 1, str(Inventory.count(a)))
	_check("采集后进入冷却", spot.cooldown_remaining() > 0.0, str(spot.cooldown_remaining()))
	_check("冷却期内再采给不出来", spot.gather() == "")

	spot.reset_cooldown()
	var b: String = spot.gather()
	_check("冷却结束后按池子顺序轮转（第二味）", pool.size() > 1 and b == pool[1], b)
	spot.reset_cooldown()
	var c: String = spot.gather()
	_check("第三味料", pool.size() > 2 and c == pool[2], c)
	spot.reset_cooldown()
	var d: String = spot.gather()
	_check("转回第一味（池子循环）", pool.size() > 0 and d == pool[0], d)

	var empty: GatherSpot = GatherSpot.new()
	empty.map_name = "不存在的地图"
	empty.spot = "不存在的地点"
	add_child(empty)
	await get_tree().process_frame
	_check("没有对应产地的地点采不出东西", empty.gather() == "")

	spot.queue_free()
	empty.queue_free()
	Inventory.clear()


func _test_item_data() -> void:
	_check("ItemDB 无校验错误", ItemDB.errors.is_empty(), str(ItemDB.errors))
	_check("图标全部合规格（正方形 + 32 的整数倍）", ItemDB.warnings.is_empty(), str(ItemDB.warnings))
	_check("现有配方里有三味料的（说明确实需要自适应）", ItemDB.max_inputs() >= 3,
			"最多 %d 味" % ItemDB.max_inputs())

	var all_ok: bool = true
	for id: String in ItemDB.items:
		var tex: Texture2D = ItemDB.icon(id)
		if tex == null:
			all_ok = false
			continue
		var s: Vector2 = tex.get_size()
		if s.x != s.y or int(s.x) % 32 != 0:
			all_ok = false
	_check("每个物品图标都能加载且尺寸合规", all_ok)


func _test_panel_geometry() -> void:
	# 一屏 N 行必须真的放得进正文区（正文到 262 为止）
	var bottom: int = BrewingPanel.ROW_TOP + (BrewingPanel.VISIBLE_ROWS - 1) * BrewingPanel.ROW_STEP \
			+ BrewingPanel.ROW_H
	_check("配方行池放得进正文（下沿 %d ≤ 262）" % bottom, bottom <= 262)
	_check("料位池够用（每行 %d 个 ≥ 现有最多 %d 味）" % [BrewingPanel.MAX_ING, ItemDB.max_inputs()],
			BrewingPanel.MAX_ING >= ItemDB.max_inputs())


## 塞 12 条配方进 ItemDB，确认"变多"以后窗口仍然只在可见范围内取值。
func _test_many_recipes() -> void:
	var added: Array[String] = []
	var base: Dictionary = ItemDB.recipe(ItemDB.recipe_ids()[0])
	for i in 7:
		var rid: String = "r_scale_test_%d" % i
		ItemDB.recipes[rid] = base.duplicate(true)
		ItemDB.recipe_order.append(rid)
		added.append(rid)

	var total: int = ItemDB.recipe_ids().size()
	_check("配方能扩到 12 条（现 %d 条）" % total, total == 12, str(total))

	var w: ListWindow = ListWindow.new()
	w.configure(total, BrewingPanel.VISIBLE_ROWS, true)
	w.move(-1)
	_check("12 条时首尾回绕正常", w.index == total - 1 and w.first() + w.visible <= total + 1)
	var idx_ok: bool = true
	for k in total:
		w.set_index(k)
		if not w.is_visible(k):
			idx_ok = false
	_check("任意一条被选中时都在可见窗口内", idx_ok)

	for rid: String in added:
		ItemDB.recipes.erase(rid)
		ItemDB.recipe_order.erase(rid)
	_check("测试配方已回收", ItemDB.recipe_ids().size() == 5)


func _check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		_pass += 1
		print("   [check] %s: PASS" % label)
	else:
		_fail += 1
		print("   [check] %s: FAIL  %s" % [label, extra])
