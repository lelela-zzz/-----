extends Node
## 一次性取景：确认萃歌挪到左吧台后端后，玩家在柜台后的服务带空了出来。
##   "<godot.exe>" --path . res://tests/cuige_shot.tscn   （窗口模式）
## 只用于观感确认，不进回归套件。
##
## 输出两张：
##   cuige_left_bar.png   柜台后全景（玩家在服务带、萃歌在左吧台尽头）
##   cuige_left_bar_serve.png  近景 —— 顾客排队 + 玩家出 [E] 卖酒 提示

const ENTRY := "res://scenes/world.tscn"
const DIR := "res://tests/shots/"


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	var scene: Node2D = (load(ENTRY) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame

	# 把按数据摆人的 NPC 层打开（萃歌 placement 已改成左吧台）
	var spawner: NpcSpawner = scene.get_node("NPCs") as NpcSpawner
	spawner.enabled = true
	spawner.spawn()

	# 放一位顾客到 1 号槽，看"玩家 + 顾客 + 老板娘"三者的提示归谁
	var customers: CustomerSpawner = scene.get_node("Customers") as CustomerSpawner
	var cust: Customer = customers.spawn("explorer_lucy")
	if cust != null:
		cust.customer_speed = 400.0
		for i in 900:
			await get_tree().physics_frame
			if cust.state == Customer.State.QUEUED:
				break

	# 玩家站到柜台后、1 号槽顾客的斜前方（正确服务位）。
	# 特意往右挪 25px：顾客在 y=140、玩家在 y=112，两人贴太近会互相盖住，
	# 取景要能同时看清"老板娘 / 玩家 / 顾客"三个人。
	var player: Node2D = scene.get_node("Sorted/Player") as Node2D
	player.global_position = Vector2(135, 112)
	for i in 24:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + "cuige_left_bar.png")
	print("[cuige_shot] done -> %scuige_left_bar.png" % DIR)
	get_tree().quit()
