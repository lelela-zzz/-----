extends Node
## 地图拓扑（autoload MapGraph）—— 跨图指引的底层：一张**有向图** + BFS。
##
## 为什么是「写死的表 + 校验测试」而不是运行时扫场景：
## 运行时要拿到 DoorArea 的 target_scene / spawn，得把每个 .tscn 实例化一遍，
## 顺带把 NPC / 顾客 / 时钟全跑起来，代价大、副作用多。所以表落在 data/
## （和 story / items / npcs 一样数据驱动），由 tests/verify_map_graph.gd
## 逐个实例化场景核对「门存在 / 目标一致 / 落点一致」—— 以后改了门忘了改表，
## 测试立刻红。这是这套设计最容易烂掉的地方，必须钉住。
##
## **边是有向的**：A 图里某扇门的 target_scene 是 B，不代表 B 里有门回 A。
## 比如 village 的 Doors/TavernDoor 直达 tavern_exterior（落点在酒馆外围正门前的
## 石板路 440,800）；而 tavern_exterior 回 village 走的是 RoadEast/RoadWest
## 两扇路门只剩 RoadWest（触发条覆盖横向路左侧整条，落点 440,800）。所以 BFS 必须按有向边走，不能当无向图。
##
## 表里只记「图 → 门 → 图」的连通关系和预期落点；门在源图里的**坐标**
## 不写死，运行时从节点的 CollisionShape2D 取（绑节点优先，见 quest_guide），
## 这样门挪了位置指引也不会漂。

signal graph_loaded

const GRAPH_PATH: String = "res://data/map_graph.json"

var _nodes: Dictionary = {}
var _edges: Array[Dictionary] = []
var _valid: bool = false


func _ready() -> void:
	_reload()
	graph_loaded.emit()


func _reload() -> void:
	_nodes = {}
	_edges = []
	_valid = false
	if not FileAccess.file_exists(GRAPH_PATH):
		push_error("MapGraph：找不到 %s" % GRAPH_PATH)
		return
	var f: FileAccess = FileAccess.open(GRAPH_PATH, FileAccess.READ)
	if f == null:
		push_error("MapGraph：打不开 %s" % GRAPH_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapGraph：%s 不是 JSON 对象" % GRAPH_PATH)
		return
	var data: Dictionary = parsed as Dictionary
	_nodes = (data.get("nodes", {}) as Dictionary).duplicate(true)
	var raw: Array = data.get("edges", []) as Array
	for e: Variant in raw:
		if typeof(e) == TYPE_DICTIONARY:
			_edges.append((e as Dictionary).duplicate(true))
	_valid = _validate()


## 自检：场景文件是否存在、边的端点是否都在 nodes 里、door 是否填了。
func _validate() -> bool:
	if _nodes.is_empty():
		push_error("MapGraph：nodes 为空")
		return false
	for k: Variant in _nodes.keys():
		var n: Dictionary = _nodes[k] as Dictionary
		var p: String = str(n.get("scene", ""))
		if p == "" or not ResourceLoader.exists(p):
			push_error("MapGraph：节点 %s 的场景不存在：%s" % [str(k), p])
			return false
	for e: Dictionary in _edges:
		var a: String = str(e.get("from", ""))
		var b: String = str(e.get("to", ""))
		if not _nodes.has(a) or not _nodes.has(b):
			push_error("MapGraph：边 %s -> %s 的端点不在 nodes 里" % [a, b])
			return false
		if str(e.get("door", "")) == "":
			push_error("MapGraph：边 %s -> %s 缺 door" % [a, b])
			return false
		# 耗时必须是正数：漏填会让"跑路不花时间"，是个静默 bug，宁可报错
		if int(e.get("minutes", 0)) <= 0:
			push_error("MapGraph：边 %s -> %s 的 minutes 必须 > 0" % [a, b])
			return false
	return true


func ok() -> bool:
	return _valid


## 图节点 id 列表（保持 nodes 里的书写顺序）。
func node_ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in _nodes.keys():
		out.append(str(k))
	return out


func scene_of(id: String) -> String:
	return str((_nodes.get(id, {}) as Dictionary).get("scene", ""))


func label_of(id: String) -> String:
	return str((_nodes.get(id, {}) as Dictionary).get("label", id))


func desc_of(id: String) -> String:
	return str((_nodes.get(id, {}) as Dictionary).get("desc", ""))


## 该去处需要哪个解锁开关（空串=一开始就可用）。
func unlock_of(id: String) -> String:
	return str((_nodes.get(id, {}) as Dictionary).get("unlock", ""))


## 场景文件路径 → 图节点 id（不在图里返回空串）。
## 地窖从 2026-10-28 起并在 world.tscn 里（同一张图的上半层），已经是酒馆的一部分，
## 连独立场景都没有，自然也不会进这张跨图路线表。
func id_of_scene(scene_path: String) -> String:
	for k: Variant in _nodes.keys():
		if str((_nodes[k] as Dictionary).get("scene", "")) == scene_path:
			return str(k)
	return ""


## 从这张图能出去的所有门（按表里顺序）。每项是 {from,door,to,spawn}。
func doors_of(scene_path: String) -> Array[Dictionary]:
	var src: String = id_of_scene(scene_path)
	var out: Array[Dictionary] = []
	if src.is_empty():
		return out
	for e: Dictionary in _edges:
		if str(e.get("from", "")) == src:
			out.append(e)
	return out


## 当前图是否已解锁（没有 unlock 字段=默认解锁）。
func is_unlocked(id: String) -> bool:
	var flag: String = unlock_of(id)
	if flag.is_empty():
		return true
	return SideStory.is_unlocked(flag)


## 跨图路线：BFS 最少跳数。
##  · 起点就是终点 → 空数组（上层会改成"直接指目的地"）；
##  · 不可达 → 空数组 + push_warning（不崩，箭头不显示）；
##  · 返回每跳 {from, door, to, spawn}：from/to 是图节点 id，
##    door 是源图里的门节点路径，spawn 是落到 to 图的脚底坐标。
func route(from_scene: String, to_scene: String) -> Array[Dictionary]:
	var src: String = id_of_scene(from_scene)
	var dst: String = id_of_scene(to_scene)
	if src.is_empty() or dst.is_empty() or src == dst:
		return []

	var prev: Dictionary = {src: null}
	var queue: Array[String] = [src]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == dst:
			break
		for e: Dictionary in _edges:
			if str(e.get("from", "")) != cur:
				continue
			var nxt: String = str(e.get("to", ""))
			if prev.has(nxt):
				continue
			prev[nxt] = {"via": e, "from": cur}
			queue.append(nxt)

	if not prev.has(dst):
		push_warning("MapGraph：从 %s 到 %s 没有可走的路线" % [src, dst])
		return []

	var hops: Array[Dictionary] = []
	var node: String = dst
	while prev[node] != null:
		var link: Dictionary = prev[node] as Dictionary
		hops.push_front(link["via"] as Dictionary)
		node = str(link["from"])
	return hops


## 走这条路线要花多少**游戏分钟** = 各跳 minutes 之和。
## 同图 = 0（不用跑）；两端不在图里 / 不可达 = -1（调用方自己决定怎么兜底）。
## 用在 M 地图的「快速前往」：面板据此决定跑路时长与时钟要转多久。
func travel_minutes(from_scene: String, to_scene: String) -> int:
	var src: String = id_of_scene(from_scene)
	var dst: String = id_of_scene(to_scene)
	if src.is_empty() or dst.is_empty():
		return -1
	if src == dst:
		return 0
	var hops: Array[Dictionary] = route(from_scene, to_scene)
	if hops.is_empty():
		return -1
	var total: int = 0
	for e: Dictionary in hops:
		total += int(e.get("minutes", 0))
	return total


## 门在源图里的世界坐标 = 触发框中心（优先取 CollisionShape2D）。
## 取不到就用 DoorArea 自己的位置兜底。
static func door_center(door: Node2D) -> Vector2:
	if door == null:
		return Vector2.ZERO
	for c: Node in door.get_children():
		if c is CollisionShape2D:
			return (c as Node2D).global_position
	return door.global_position
