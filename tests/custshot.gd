extends Node
## 顾客观感截图：四位顾客排满吧台前（上限 4）/ 卖酒面板。
##   "<godot.exe>" res://tests/custshot.tscn      （窗口模式）

const ENTRY := "res://scenes/world.tscn"
const DIR := "res://tests/shots/"

var scene: Node2D
var spawner: CustomerSpawner
var player: Player


func _ready() -> void:
	TestView.logic_resolution()
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	scene = (load(ENTRY) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	player = scene.get_node("Sorted/Player") as Player
	spawner = scene.get_node("Customers") as CustomerSpawner
	Engine.max_fps = 60

	var ids: Array[String] = ["explorer_lucy", "miner_simon",
			"dwarf_war_edward", "market_catherine"]
	for id: String in ids:
		var c: Customer = spawner.spawn(id)
		if c != null:
			c.customer_speed = 220.0

	# 等四位都排到位
	for i in 1200:
		await get_tree().physics_frame
		var ready_n: int = 0
		for n: Node in get_tree().get_nodes_in_group("npc"):
			var c: Customer = n as Customer
			if c != null and c.state == Customer.State.QUEUED:
				ready_n += 1
		if ready_n >= 4:
			break
	await _wait(6)
	await _shot("cust_01_queue.png")

	Inventory.clear()
	Inventory.add("wine_warm_ginger", 3)
	Inventory.add("wine_burnt_ale", 2)
	Inventory.add("wine_river_ale", 1)

	var near: Customer = null
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var c: Customer = n as Customer
		if c != null:
			near = c
			break
	if near != null:
		player.global_position = near.global_position + Vector2(0, 32)
		await _wait(8)
		await _shot("cust_02_prompt.png")
		var ev: InputEventAction = InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		get_viewport().push_input(ev)
		await _wait(14)
		await _shot("cust_03_sell.png")

	print("[custshot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	(get_viewport().get_texture().get_image()).save_png(DIR + name)
