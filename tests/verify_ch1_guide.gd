extends Node
## 第一章「雾凇无虞」任务【指引】验收。
##
## verify_map_graph 只保证「拓扑表 ↔ 场景里的门」一致，
## **不保证任务数据里写的目的地指得对** —— 新地图接入后指引乱掉，乱的就是这一层。
## 所以这里专门盯三件事：
##   1) 数据：13 幕每幕都有 dest，scene 是地图图里已知的图，pos 是合法坐标；
##   2) 节点：dest 绑的节点路径，按 ChapterStory 的命名规则摆好人后真的能解析
##      （章节人物 = Sorted/Npc_beat_<id>；常驻人物 = Sorted/Npc_<id>；锅是静态节点）；
##   3) 路线：逐幕推进时，「上一幕所在地 → 本幕目的地」的跨图路线真的存在（可达）。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_ch1_guide.tscn

## 章节临时人物的节点前缀（与 ChapterStory._place_npc 的命名保持一致）。
const BEAT_PREFIX: String = "Sorted/Npc_beat_"

var passed: int = 0
var failed: int = 0
var _scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	QuestLog.reset()
	# _ready 这条链还在跑时 root 正忙着布置子节点，先让一帧
	await get_tree().process_frame

	_check_dest_data()
	await _check_dest_nodes()
	_check_routes()

	QuestLog.reset()
	print("[ch1_guide] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 数据完整性 -------------------------------------------------------

func _check_dest_data() -> void:
	var beats: Array = ChapterStory._beats
	_report("第一章 13 幕", beats.size() == 13, "beats=%d" % beats.size())

	var no_dest: String = ""
	var bad_scene: String = ""
	var bad_pos: String = ""
	for b: Variant in beats:
		var beat: Dictionary = b as Dictionary
		var id: String = str(beat.get("id", ""))
		var dest: Dictionary = beat.get("dest", {}) as Dictionary
		if dest.is_empty():
			no_dest += id + " "
			continue
		var sc: String = str(dest.get("scene", ""))
		if MapGraph.id_of_scene(sc) == "":
			bad_scene += "%s(%s) " % [id, sc]
		var pos: Variant = dest.get("pos", null)
		if not (pos is Array) or (pos as Array).size() < 2:
			bad_pos += id + " "

	_report("每幕都有目的地 dest", no_dest == "", "缺 dest：%s" % no_dest)
	_report("dest.scene 都是地图图里的已知图", bad_scene == "", bad_scene)
	_report("dest.pos 都是合法坐标", bad_pos == "", bad_pos)


# ---- 2. 目的地节点真的能解析 ---------------------------------------------

## 对每一幕：挂上 dest 所在的图 → 按 ChapterStory 的命名规则摆本幕人物 →
## 看 dest.node 能不能 get_node 到。
##
## 摆人用的是和 ChapterStory._place_npc 完全相同的命名（"Npc_beat_" + nid，
## 挂在 Sorted 下）；这里只验路径格式对不对，所以摆同名的空 Node2D 就够，
## 不必真的 configure 一个 NPC。常驻人物（凯瑟琳/萃歌）由 NpcSpawner 摆，不重复摆。
func _check_dest_nodes() -> void:
	var beats: Array = ChapterStory._beats
	var bad: String = ""
	var checked: int = 0
	for b: Variant in beats:
		var beat: Dictionary = b as Dictionary
		var id: String = str(beat.get("id", ""))
		var dest: Dictionary = beat.get("dest", {}) as Dictionary
		if dest.is_empty():
			continue
		var np: String = str(dest.get("node", ""))
		if np == "":
			continue
		var sc: String = str(dest.get("scene", ""))
		# 章节人物由"摆他的那一幕"负责出场：travel 幕只写了目的地，人要到下一幕
		# 才登台 —— 所以按人物 id 找到那一幕，用那一幕的 spawn 摆人再验。
		var spawn_beat: Dictionary = beat
		if np.begins_with(BEAT_PREFIX):
			var owner: Dictionary = _beat_that_spawns(np.substr(BEAT_PREFIX.length()))
			if not owner.is_empty():
				spawn_beat = owner
		await _mount(sc)
		_spawn_sim(spawn_beat)
		await _tick()
		checked += 1
		if _scene.get_node_or_null(np) == null:
			bad += "%s→%s " % [id, np]

	_report("dest.node 在场景里真的能解析", bad == "",
			"验了 %d 幕；解析不到：%s" % [checked, bad])


## 哪一幕会把这个章节人物摆进场景（主 npc 或 extras 里出现了他）。
## travel 幕自己不摆人，但它指的目的地人物会在下一幕登场，所以按 id 反查那一幕。
func _beat_that_spawns(npc_id: String) -> Dictionary:
	for b: Variant in ChapterStory._beats:
		var beat: Dictionary = b as Dictionary
		if str(beat.get("npc", "")) == npc_id:
			return beat
		for e: Variant in beat.get("extras", []):
			if str((e as Dictionary).get("npc", "")) == npc_id:
				return beat
	return {}


## 按 ChapterStory 的规则把本幕人物摆进 Sorted：主 npc + extras。
func _spawn_sim(beat: Dictionary) -> void:
	if _scene == null:
		return
	var sorted: Node = _scene.get_node_or_null("Sorted")
	if sorted == null:
		return
	var items: Array = []
	var nid: String = str(beat.get("npc", ""))
	if nid != "":
		items.append({"npc": nid})
	for e: Variant in beat.get("extras", []):
		items.append(e as Dictionary)
	for it: Variant in items:
		var d: Dictionary = it as Dictionary
		var n: String = str(d.get("npc", ""))
		if n == "":
			continue
		var node_name: String = "Npc_beat_" + n
		if sorted.get_node_or_null(node_name) == null:
			var node: Node2D = Node2D.new()
			node.name = node_name
			sorted.add_child(node)


# ---- 3. 逐幕推进的可达性 -------------------------------------------------

## 模拟玩家一路做下去：站在上一幕的图里，去本幕的目的地图，BFS 得给出路线。
## travel 幕本身不是一张图（place="travel"），所在地沿用上一幕。
func _check_routes() -> void:
	var beats: Array = ChapterStory._beats
	var prev_place: String = ""
	var bad: String = ""
	var hops: Array[String] = []
	for b: Variant in beats:
		var beat: Dictionary = b as Dictionary
		var id: String = str(beat.get("id", ""))
		var place: String = str(beat.get("place", ""))
		var dest: Dictionary = beat.get("dest", {}) as Dictionary
		if not dest.is_empty() and prev_place != "" and place != "travel":
			var from: String = MapGraph.scene_of(prev_place)
			var to: String = str(dest.get("scene", ""))
			if from != "" and to != "" and from != to:
				var r: Array = MapGraph.route(from, to)
				if r.is_empty():
					bad += "%s(%s→%s) " % [id, prev_place, MapGraph.id_of_scene(to)]
				else:
					hops.append("%s:%d跳" % [id, r.size()])
		if place != "travel":
			prev_place = place

	_report("逐幕推进：上一幕所在地 → 本幕目的地 都可达", bad == "",
			"走不到：%s ｜ %s" % [bad, " / ".join(hops)])


# ---- 工具 ---------------------------------------------------------------

func _mount(path: String) -> Node:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	var ps: PackedScene = load(path) as PackedScene
	_scene = ps.instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	await _tick()
	return _scene


func _tick() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
