extends Node
## 离场寻路不得穿过家具 —— 「顾客离座时直接穿过长桌」的护栏（2026-10-29 修）。
##
## 判定口径：把离场折线逐段与 props.json 的 collision_rect 做**线段-矩形相交**。
##   · 出凳那一步允许穿过**自己这张长桌**：座椅点本身就落在长凳（长桌精灵的一部分）
##     的碰撞框里，人得先站起来走出来，这一步绕不开
##   · 其余每一段一律不许碰到任何家具（长桌 / 圆桌 / 吧台 / 酒桶 / 酒架 …）
##
## 还带一条"对照"用例：旧版那条 `座位 → (320,200) → 门口` 的直线必须被判为穿模，
## 否则说明这套判定根本没在检查东西。
##
## 跑法： "<godot>" --headless --path . res://tests/verify_seat_path.tscn --quit-after 9000

const PROPS_PATH: String = "res://assets/house/v4/objects/props.json"
const SEATS_PATH: String = "res://data/seats.json"

var _pass: int = 0
var _fail: int = 0
## [{name: String, rect: Rect2}]
var _rects: Array[Dictionary] = []
var _seats: Array[Dictionary] = []


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	await get_tree().process_frame

	_load_data()
	_report("读到家具碰撞框", _rects.size() >= 10, "rects=%d" % _rects.size())
	_report("读到 4 张座位", _seats.size() == 4, "seats=%d" % _seats.size())

	_check_old_path_would_clip()
	_check_seat_leaves()
	_check_seat_approach()
	_check_counter_leaves()
	await _check_integration()

	print("[seat_path] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---- 数据 ---------------------------------------------------------------

func _load_data() -> void:
	_rects.clear()
	var props: Variant = _read_json(PROPS_PATH)
	if props is Dictionary:
		for p: Variant in ((props as Dictionary).get("props", []) as Array):
			var e: Dictionary = p as Dictionary
			var c: Variant = e.get("collision_rect", null)
			if not (c is Array):
				continue
			var a: Array = c as Array
			if a.size() < 4:
				continue
			var r: Rect2 = Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				continue
			_rects.append({"name": str(e.get("name", "?")), "rect": r})

	_seats.clear()
	var s: Variant = _read_json(SEATS_PATH)
	if s is Array:
		for e: Variant in s as Array:
			if e is Dictionary:
				_seats.append(e as Dictionary)


func _read_json(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("读不到 %s" % path)
		return null
	return JSON.parse_string(f.get_as_text())


# ---- 判定 ---------------------------------------------------------------

## 线段与矩形是否有重叠（Liang–Barsky 裁剪；矩形收 0.01px，避免"擦边"当命中）。
func _seg_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var rect: Rect2 = Rect2(r.position + Vector2(0.01, 0.01), r.size - Vector2(0.02, 0.02))
	var d: Vector2 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	for axis: int in 2:
		var lo: float = rect.position[axis]
		var hi: float = lo + rect.size[axis]
		# 两个 slab：低边、高边
		for side: int in 2:
			var p: float = -d[axis] if side == 0 else d[axis]
			var q: float = (a[axis] - lo) if side == 0 else (hi - a[axis])
			if is_zero_approx(p):
				if q < 0.0:
					return false
				continue
			var t: float = q / p
			if p < 0.0:
				if t > t1:
					return false
				t0 = maxf(t0, t)
			else:
				if t < t0:
					return false
				t1 = minf(t1, t)
	return t0 <= t1


## 路径里从第 [param skip] 段之后，有没有撞上家具。返回撞上的描述。
func _violations(path: PackedVector2Array, skip: int = 0) -> Array[String]:
	var out: Array[String] = []
	for i: int in range(path.size() - 1):
		if i < skip:
			continue
		for e: Dictionary in _rects:
			if _seg_hits(path[i], path[i + 1], e["rect"] as Rect2):
				out.append("第%d段→%s" % [i, e["name"]])
	return out


## 某一段里撞到了哪些家具有名字。
func _hits_of_segment(a: Vector2, b: Vector2) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in _rects:
		if _seg_hits(a, b, e["rect"] as Rect2):
			out.append(str(e["name"]))
	return out


func _rect_owning(p: Vector2) -> String:
	for e: Dictionary in _rects:
		if (e["rect"] as Rect2).has_point(p):
			return str(e["name"])
	return ""


# ---- 1. 对照：旧直线路径必须被判为穿模 -----------------------------------

func _check_old_path_would_clip() -> void:
	var clippers: Array[String] = []
	for seat: Dictionary in _seats:
		var p: Vector2 = Vector2(float(seat.get("x", 0.0)), float(seat.get("y", 0.0)))
		var old: PackedVector2Array = PackedVector2Array([
			p, Vector2(320, 200), Vector2(320, 300),
		])
		if not _violations(old).is_empty():
			clippers.append(str(seat.get("id", "?")))
	_report("对照：旧的「座位→(320,200)→门口」直线会被判成穿模",
			clippers.size() == _seats.size(), "会穿的座位=%s" % str(clippers))


# ---- 2. 每个座位离场 -----------------------------------------------------

func _check_seat_leaves() -> void:
	for seat: Dictionary in _seats:
		var sid: String = str(seat.get("id", "?"))
		var p: Vector2 = Vector2(float(seat.get("x", 0.0)), float(seat.get("y", 0.0)))
		var path: PackedVector2Array = Customer.build_leave_path(
				p, seat, true, PackedVector2Array(), 0)

		_report("%s 离场路径从座位出发" % sid,
				not path.is_empty() and path[0].distance_to(p) < 0.5, "start=%s" % str(path[0]))
		_report("%s 离场路径走到门口" % sid,
				not path.is_empty() and path[path.size() - 1].distance_to(CustomerSpawner.ENTRY) < 0.5,
				"end=%s" % str(path[path.size() - 1] if not path.is_empty() else "空"))

		# 关键：从第二次抬脚起，一段都不许撞家具
		var bad: Array[String] = _violations(path, 1)
		_report("%s 离座后不再穿过任何家具" % sid, bad.is_empty(), "撞到：%s" % str(bad))

		# 出凳那一步只允许穿过自己这张长桌
		var own: String = _rect_owning(p)
		var hits: Array[String] = _hits_of_segment(path[0], path[1])
		var stray: Array[String] = []
		for h: String in hits:
			if h != own:
				stray.append(h)
		_report("%s 出凳只碰自己那张长桌（%s）" % [sid, own],
				own != "" and stray.is_empty() and hits.size() <= 1,
				"own=%s hits=%s" % [own, str(hits)])


# ---- 3. 入座路径（顺带验）：从 5 个槽位走到 4 张凳子 ---------------------

func _check_seat_approach() -> void:
	var bad: Array[String] = []
	for seat: Dictionary in _seats:
		var sid: String = str(seat.get("id", "?"))
		var sit: Vector2 = Vector2(float(seat.get("x", 0.0)), float(seat.get("y", 0.0)))
		var own: String = _rect_owning(sit)
		for x: float in CustomerSpawner.SLOTS:
			var queue: Vector2 = Vector2(x, CustomerSpawner.QUEUE_Y)
			var path: PackedVector2Array = PackedVector2Array([queue])
			for p: Variant in (seat.get("path", []) as Array):
				var a: Array = p as Array
				path.append(Vector2(float(a[0]), float(a[1])))
			# 最后一段是"从过道踏进凳子"，允许穿自己那张长桌；之前一律不许碰
			for v: String in _violations(path, 0):
				if not v.ends_with(own) or not v.begins_with("第%d段" % (path.size() - 2)):
					bad.append("%s←x%d %s" % [sid, int(x), v])
	_report("入座路径：4 张凳子 × 5 个槽位，只有踏进凳子那一步碰自己的长桌",
			bad.is_empty(), "问题：%s" % str(bad))


# ---- 4. 从吧台排队位离场 -------------------------------------------------
func _check_counter_leaves() -> void:
	var bad: Array[String] = []
	var idx: int = 0
	for x: float in CustomerSpawner.SLOTS:
		# 和 CustomerSpawner.path_for 同一套折线（那是实例方法，这里自己拼）
		var queue: PackedVector2Array = PackedVector2Array([
			CustomerSpawner.ENTRY, CustomerSpawner.CORNER_A, CustomerSpawner.CORNER_B,
			CustomerSpawner.CORNER_C, Vector2(x, CustomerSpawner.AISLE_Y),
			Vector2(x, CustomerSpawner.QUEUE_Y),
		])
		var leave: PackedVector2Array = Customer.build_leave_path(
				queue[queue.size() - 1], {}, false, queue, queue.size())
		for v: String in _violations(leave):
			bad.append("槽位%d %s" % [idx, v])
		if leave[leave.size() - 1].distance_to(CustomerSpawner.ENTRY) > 0.5:
			bad.append("槽位%d 没走到门口" % idx)
		idx += 1
	_report("从吧台排队位离场：5 个槽位都不穿家具、都能走到门口",
			bad.is_empty(), "问题：%s" % str(bad))


# ---- 4. 集成：真顾客坐下再被叫走 -----------------------------------------

func _check_integration() -> void:
	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame

	var sp: CustomerSpawner = scene.get_node_or_null("Customers") as CustomerSpawner
	if sp == null:
		_report("集成：拿到顾客生成器", false, "找不到 Customers")
		return
	var c: Customer = sp.spawn("miner_simon")
	if c == null:
		_report("集成：摆一位顾客", false, "spawn 失败")
		return

	# 手动摆到 s1 的凳子上（等价于 _arrive_seat 之后的状态）
	var seat: Dictionary = _seat_by_id("s1")
	var sit: Vector2 = Vector2(float(seat.get("x", 0.0)), float(seat.get("y", 0.0)))
	c.position = sit
	c.state = Customer.State.SITTING
	c.set("_seat", seat)
	c.set("_seated", true)
	SeatRegistry.claim_by_id("s1")

	c.call("_begin_leave")
	var path: PackedVector2Array = c.get("_path") as PackedVector2Array
	_report("集成：坐下被叫走后先回过道（不是直奔 320,200）",
			path.size() > 1 and path[1].distance_to(Vector2(105, 210)) < 1.0,
			"path[1]=%s" % str(path[1] if path.size() > 1 else "空"))
	_report("集成：离场状态为 LEAVING", c.state == Customer.State.LEAVING,
			"state=%d" % c.state)
	_report("集成：座位已释放", SeatRegistry.occupied_count() == 0,
			"occupied=%d" % SeatRegistry.occupied_count())
	_report("集成：整条离场路径不穿家具", _violations(path, 1).is_empty(),
			"撞到：%s" % str(_violations(path, 1)))


func _seat_by_id(id: String) -> Dictionary:
	for s: Dictionary in _seats:
		if str(s.get("id", "")) == id:
			return s
	return {}


# ---- 汇报 ---------------------------------------------------------------

func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s | %s" % [name, detail])
	else:
		_fail += 1
		print("[check] FAIL  %s | %s" % [name, detail])
