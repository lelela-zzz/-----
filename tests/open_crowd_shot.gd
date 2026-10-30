extends Node
## 一次性取景：复现"序章酿酒完成、开张之后"的酒馆人流密度。
##   "<godot.exe>" --path . res://tests/open_crowd_shot.tscn   （窗口模式）
## 只用于观感确认，不进回归套件。

const ENTRY := "res://scenes/world.tscn"
const DIR := "res://tests/shots/"
const NPC_SCENE := "res://scenes/npc.tscn"

var scene: Node2D
var passed: int = 0


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	scene = (load(ENTRY) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame

	var defs: Dictionary = _load_defs()

	# 1) 老板娘（Story 在开张前就会摆）
	_place(defs, "tavern_cuige", Vector2(76, 100))

	# 2) 支线访客（Story._ensure_side_npcs 摆的那位 —— 现在一次只摆一位）
	var f: FileAccess = FileAccess.open("res://data/side_stories.json", FileAccess.READ)
	var side: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if side is Dictionary:
		for arc: Variant in ((side as Dictionary).get("arcs", []) as Array):
			var sp: Variant = (arc as Dictionary).get("spawn")
			if sp == null:
				continue
			var arr: Array = (sp as Dictionary).get("pos", [0, 0]) as Array
			_place(defs, str((arc as Dictionary).get("npc_id", "")),
					Vector2(float(arr[0]), float(arr[1])))
			break

	# 3) 顾客：铺满上限（3 位）
	var spawner: CustomerSpawner = scene.get_node("Customers") as CustomerSpawner
	var ids: Array[String] = ["explorer_lucy", "miner_simon", "dwarf_war_edward"]
	for id: String in ids:
		var cust: Customer = spawner.spawn(id)
		if cust == null:
			continue
		cust.customer_speed = 260.0
		for i in 600:
			await get_tree().physics_frame
			if is_instance_valid(cust) and cust.state == Customer.State.QUEUED:
				break

	# 玩家站到柜台后
	var player: Node2D = scene.get_node("Sorted/Player") as Node2D
	player.global_position = Vector2(150, 112)

	for i in 30:
		await get_tree().process_frame
	for c: Node in get_tree().get_nodes_in_group("npc"):
		var cu: Customer = c as Customer
		if cu != null:
			print("  cust ", cu.npc_id, " state=", cu.state, " pos=", cu.global_position)
		else:
			print("  npc  ", (c as Npc).npc_id, " pos=", (c as Node2D).global_position)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + "open_crowd.png")
	print("[open_crowd_shot] NPC=%d 顾客=%d -> %sopen_crowd.png"
			% [get_tree().get_nodes_in_group("npc").size(), spawner.active_count(), DIR])
	get_tree().quit()


func _load_defs() -> Dictionary:
	var out: Dictionary = {}
	var f: FileAccess = FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		for d: Variant in ((data as Dictionary).get("npcs", []) as Array):
			out[str((d as Dictionary).get("id", ""))] = d
	return out


func _place(defs: Dictionary, id: String, at: Vector2) -> void:
	var def: Dictionary = defs.get(id, {}) as Dictionary
	if def.is_empty():
		return
	var ps: PackedScene = load(NPC_SCENE) as PackedScene
	var npc: Npc = ps.instantiate() as Npc
	npc.name = "Npc_" + id
	npc.configure(def, {"scene": "world", "pos": [at.x, at.y],
			"facing": "down", "wander": 0.0})
	scene.get_node("Sorted").add_child(npc)
	passed += 1
