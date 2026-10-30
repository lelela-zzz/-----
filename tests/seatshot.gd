extends Node
## 落座观感截图：四位顾客坐到长桌两侧长凳上，验证方向 + 有无占位矩形残留。
##   "<godot.exe>" res://tests/seatshot.tscn      （必须窗口模式）

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

	# 把玩家挪到一边，别挡住长凳
	player.position = Vector2(430, 250)

	var ids: Array[String] = ["explorer_lucy", "miner_simon",
			"dwarf_war_edward", "market_catherine"]
	var folks: Array[Customer] = []
	for id: String in ids:
		var c: Customer = spawner.spawn(id)
		if c != null:
			c.customer_speed = 260.0
			folks.append(c)

	await _wait(10)
	# 等队列排好后再让他们各自去占座
	for c: Customer in folks:
		c._begin_sit()

	for i in 1800:
		await get_tree().physics_frame
		var n: int = 0
		for f: Customer in folks:
			if f._seated:
				n += 1
		if n >= folks.size():
			break

	await _wait(20)
	await _shot("seat_01_all.png")

	# 打印每位的实际落座帧 + 屏幕坐标，便于核对与裁图
	var cam: Camera2D = get_viewport().get_camera_2d()
	var view: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	for f: Customer in folks:
		var a: AnimatedSprite2D = f.get_node_or_null("Anim") as AnimatedSprite2D
		var scr: Vector2 = Vector2.ZERO
		if cam != null:
			scr = f.global_position - cam.global_position + view * 0.5
		print("[seatshot] %s seat=%s dir=%s anim=%s frame=%d world=(%.0f,%.0f) screen=(%.0f,%.0f)" % [
			f.npc_id, str(f._seat.get("id", "?")), str(f._dir),
			(a.animation if a != null else "?"), (a.frame if a != null else -1),
			f.global_position.x, f.global_position.y, scr.x, scr.y])

	print("[seatshot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	(get_viewport().get_texture().get_image()).save_png(DIR + name)
