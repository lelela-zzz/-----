class_name NpcSpawner
extends Node2D
## 按 data/npcs.json 往场景里摆 NPC。
##
## 为什么不在 world.tscn 里手摆节点：19 个角色、四个场景，手摆一次还好，
## 改一个坐标要在场景树里翻半天。数据在 JSON 里，"这个 NPC 站哪儿"就是一行文本，
## 加人/挪人/换台词都不用碰场景。
##
## 一条 NPC 可以有多条 placement（同一角色出现在多个场景），
## 本节点只实例化 scene_key 与当前场景一致的那些。

const NPC_SCENE: String = "res://scenes/npc.tscn"
const DATA_PATH: String = "res://data/npcs.json"

## 摆到哪个父节点下（必须是 y_sort 容器，否则和家具的遮挡会错）。
@export var npc_parent_path: NodePath = ^"../Sorted"
## 只实例化 placement.scene == 本值的条目。
@export var scene_key: String = "world"
## 总开关。关掉 = 数据照常读（错误照样报），但一个人也不往场景里放。
## 现在酒馆里先不站人，保留 placement 坐标，回头把这里打开就回来了。
@export var enabled: bool = true

var errors: Array[String] = []

var _defs: Dictionary = {}
var _spawned: bool = false


func _ready() -> void:
	_load()
	if not enabled:
		return
	spawn()


## 按数据实例化。_ready 会自动调一次；验收脚本想测生成逻辑时才手动再调。
func spawn() -> void:
	if _spawned:
		return
	var parent: Node = get_node_or_null(npc_parent_path)
	if parent == null:
		push_error("NpcSpawner：找不到父节点 %s" % npc_parent_path)
		return
	var scene: PackedScene = load(NPC_SCENE) as PackedScene
	if scene == null:
		push_error("NpcSpawner：加载不了 %s" % NPC_SCENE)
		return
	for id: String in _defs:
		var def: Dictionary = _defs[id] as Dictionary
		for place: Variant in (def.get("placement", []) as Array):
			var p: Dictionary = place as Dictionary
			if str(p.get("scene", "")) != scene_key:
				continue
			var npc: Npc = scene.instantiate() as Npc
			npc.name = "Npc_" + id
			npc.configure(def, p)
			parent.add_child(npc)
	_spawned = true


func _load() -> void:
	_defs.clear()
	errors.clear()
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		errors.append("打不开 %s" % DATA_PATH)
		push_error("[NpcSpawner] %s" % errors[-1])
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s 不是合法 JSON 对象" % DATA_PATH)
		push_error("[NpcSpawner] %s" % errors[-1])
		return
	var list: Array = (parsed as Dictionary).get("npcs", [])
	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("npcs 里有一条不是对象")
			continue
		var d: Dictionary = entry as Dictionary
		var id: String = str(d.get("id", ""))
		if id == "":
			errors.append("有一条缺 id")
			continue
		if _defs.has(id):
			errors.append("id 重复：%s" % id)
			continue
		var sheet: String = str(d.get("sheet", ""))
		if not ResourceLoader.exists(sheet):
			errors.append("%s 的图集不存在：%s" % [id, sheet])
		_defs[id] = d
	if not errors.is_empty():
		for e: String in errors:
			push_error("[NpcSpawner] %s" % e)


## 供验收/调试：当前场景应该摆几个。
func expected_count() -> int:
	var n: int = 0
	for id: String in _defs:
		for place: Variant in ((_defs[id] as Dictionary).get("placement", []) as Array):
			if str((place as Dictionary).get("scene", "")) == scene_key:
				n += 1
	return n


## 数据集里一共有多少个角色（含未出场的）。
func total_defs() -> int:
	return _defs.size()


func defs() -> Dictionary:
	return _defs
