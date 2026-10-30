extends Node
## 地图拓扑一致性验收 —— data/map_graph.json（表）↔ 各场景里的 DoorArea（真身）。
##
## 指引系统算路线的可信度全靠这里钉住：
##  · 表里写了某扇门，场景里必须真有这个节点；
##  · 门的 target_scene / spawn_position 必须和表里的 to / spawn 一致。
## 以后挪了门、改了落点、加了新地图却忘了同步表 → 这里立刻红。
##
## 纯逻辑 + 实例化场景断言，不需要渲染，headless 可跑。

var passed: int = 0
var failed: int = 0
var _cache: Dictionary = {}


func _ready() -> void:
	_check_graph_valid()
	_check_nodes()
	_check_edges_against_scenes()
	_check_routes()
	_finish()


## --- 用例 ---------------------------------------------------------------

func _check_graph_valid() -> void:
	_report("map_graph.json 通过自检", MapGraph.ok())
	_report("图里至少有两张地图（不然谈不上跨图）",
			MapGraph.node_ids().size() >= 2, "%d 张" % MapGraph.node_ids().size())


func _check_nodes() -> void:
	for id: String in MapGraph.node_ids():
		var p: String = MapGraph.scene_of(id)
		_report("节点 %s 有场景文件" % id,
				not p.is_empty() and ResourceLoader.exists(p), p)
		_report("节点 %s 有显示名" % id, not MapGraph.label_of(id).is_empty(),
				MapGraph.label_of(id))


## 逐条边：实例化 from 图 → 找 door 节点 → 比对 target_scene / spawn_position。
func _check_edges_against_scenes() -> void:
	var checked: int = 0
	for e: Dictionary in _edges():
		var src: String = str(e.get("from", ""))
		var dst: String = str(e.get("to", ""))
		var door_path: String = str(e.get("door", ""))

		_report("边 %s->%s 的端点都在 nodes 里" % [src, dst],
				MapGraph.node_ids().has(src) and MapGraph.node_ids().has(dst),
				"door=%s" % door_path)
		_report("边 %s->%s 有正数耗时（跑路要花时间）" % [src, dst],
				int(e.get("minutes", 0)) > 0, "minutes=%s" % str(e.get("minutes", 0)))

		var inst: Node = _instantiate(MapGraph.scene_of(src))
		if inst == null:
			_report("能实例化 %s" % MapGraph.scene_of(src), false, "实例化失败")
			continue
		var door: DoorArea = inst.get_node_or_null(door_path) as DoorArea
		if door == null:
			_report("%s 里有门 %s" % [src, door_path], false, "节点不存在或不是 DoorArea")
			continue
		checked += 1
		_report("门 %s/%s 指向 %s" % [src, door_path, dst],
				door.target_scene == MapGraph.scene_of(dst),
				"实际=%s 期望=%s" % [door.target_scene, MapGraph.scene_of(dst)])
		var want: Vector2 = _vec(e.get("spawn", []))
		_report("门 %s/%s 的落点一致" % [src, door_path],
				door.spawn_position == want,
				"实际=%s 期望=%s" % [str(door.spawn_position), str(want)])
	_report("至少校验了 5 条边", checked >= 5, "%d 条" % checked)


## 路线规划：跳数正确、不可达返回空、同图返回空。
func _check_routes() -> void:
	var w: String = MapGraph.scene_of("world")
	var ex: String = MapGraph.scene_of("tavern_exterior")
	var v: String = MapGraph.scene_of("village")
	var me: String = MapGraph.scene_of("mine_entrance")
	var mn: String = MapGraph.scene_of("mine")

	_report("起点=终点 → 空路线（直接指目的地）", MapGraph.route(w, w).is_empty())
	_report("world → tavern_exterior = 1 跳",
			MapGraph.route(w, ex).size() == 1, "%d 跳" % MapGraph.route(w, ex).size())
	_report("world → village = 2 跳（要绕门口）",
			MapGraph.route(w, v).size() == 2, "%d 跳" % MapGraph.route(w, v).size())
	_report("world → mine = 4 跳",
			MapGraph.route(w, mn).size() == 4, "%d 跳" % MapGraph.route(w, mn).size())
	_report("mine → world = 4 跳（village 改走 tavern_exterior 绕门口）",
			MapGraph.route(mn, w).size() == 4, "%d 跳" % MapGraph.route(mn, w).size())
	_report("不存在的图 → 空路线（不崩）",
			MapGraph.route(w, "res://scenes/nope.tscn").is_empty())

	# 第一跳必须真的是"从当前图出去"的那扇门
	var r: Array[Dictionary] = MapGraph.route(w, mn)
	if r.is_empty():
		_report("world→mine 有路线可校验", false, "空")
		return
	var hop: Dictionary = r[0] as Dictionary
	_report("第一跳 from = world", str(hop.get("from", "")) == "world",
			str(hop.get("from", "")))
	_report("第一跳 door = ExitSouth", str(hop.get("door", "")) == "Doors/ExitSouth",
			str(hop.get("door", "")))


## --- 工具 ---------------------------------------------------------------


func _edges() -> Array[Dictionary]:
	return MapGraph._edges


## 同一个场景只实例化一次，实例化过的留着，别白跑 NPC / 顾客。
func _instantiate(path: String) -> Node:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Node
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	add_child(inst)
	_cache[path] = inst
	return inst


func _vec(v: Variant) -> Vector2:
	if v is Array:
		var a: Array = v as Array
		if a.size() >= 2:
			return Vector2(float(a[0]), float(a[1]))
	elif v is Vector2:
		return v as Vector2
	return Vector2.ZERO


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _finish() -> void:
	print("[map_graph] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
