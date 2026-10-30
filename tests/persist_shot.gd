extends Node
## 一次性取景："出门前"与"从门口街上回来"的对照，证明店里的人没被清空。
##   "<godot.exe>" --path . res://tests/persist_shot.tscn
##
## 走的是真通道：加载 world.tscn → 摆两位顾客（一位排队、一位坐下）
## → 拍一张 → 按 DoorArea 的方式离场（pending_target = 门口街上）并销毁场景（存快照）
## → 重新加载 world.tscn → 恢复后再记录一张。

const DIR: String = "res://tests/persist_shots/"
const ENTRY := "res://scenes/world.tscn"

var scene: Node2D
var spawner: CustomerSpawner


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = false
	CustomerSpawner.reset_session()
	Inventory.clear()
	DirAccess.make_dir_recursive_absolute(DIR)
	WindowScale.set_display_scale(1.5)
	await get_tree().process_frame

	await _make_world()
	Inventory.add("wine_warm_ginger", 3)
	var luc: Customer = spawner.spawn("explorer_lucy")
	if luc != null:
		luc.customer_speed = 400.0   # 拍照用：别让镜头等她从门口走完长廊
	var simon: Customer = spawner.spawn("miner_simon")
	if simon != null:
		simon.customer_speed = 400.0
		simon.sell("wine_warm_ginger")
		simon._begin_sit()
		for i in 240:
			await get_tree().physics_frame
			if simon._seated:
				break
	var player: Node2D = scene.get_node("Sorted/Player") as Node2D
	player.global_position = Vector2(150, 112)
	# 等她走到吧台站定再拍，两张图才好对照
	if luc != null:
		for i in 900:
			await get_tree().physics_frame
			if luc.state == Customer.State.QUEUED:
				break
	await _wait(20)
	await _shot("01_before_leaving.png")
	print("  下楼前：在场 %d 位" % spawner.active_count())
	_dump()

	# 真实路径：推门进地窖 = **切场景**，world 被销毁（_exit_tree 存快照）；
	# 踩地窖楼梯回酒馆 = world 重建，_ready 里把快照摆回去。
	# 这里照同一条通道走一遍，只拍"离开前"和"回来后"两张对照
	# （地窖里本来就没有顾客，去拍它没有信息量）。
	DoorArea.pending_target = "res://scenes/tavern_exterior.tscn"
	scene.queue_free()
	spawner = null
	await _wait(8)

	await _make_world()
	var player2: Node2D = scene.get_node_or_null("Sorted/Player") as Node2D
	if player2 != null:
		player2.global_position = Vector2(150, 112)
	await _wait(30)
	await _shot("02_after_return.png")
	print("  从地窖回来：在场 %d 位" % spawner.active_count())
	_dump()

	print("[persist_shot] done -> %s" % DIR)
	get_tree().quit()


## 把每位顾客的 id/状态/坐标打出来，方便和截图对照
## 顾客挂在 npc_parent_path 底下，不在 spawner 里面，所以读 _occupancy
func _dump() -> void:
	var occ: Dictionary = spawner._occupancy
	var slots: Array = occ.keys()
	slots.sort()
	for s in slots:
		var cu: Customer = occ[s] as Customer
		if cu == null or not is_instance_valid(cu):
			continue
		print("     %-16s slot=%d state=%d pos=(%.0f,%.0f) seat=%s" % [
			cu.npc_id, s, cu.state, cu.global_position.x, cu.global_position.y,
			str(cu.seat().get("id", "-"))
		])


func _make_world() -> void:
	scene = (load(ENTRY) as PackedScene).instantiate()
	add_child(scene)
	spawner = scene.get_node("Customers") as CustomerSpawner
	spawner.auto_spawn = false     # 只摆用例指定的两位，别自动补位
	await _wait(6)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + name)
	print("  -> ", name)
