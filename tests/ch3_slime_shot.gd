extends Node
## 第三章矿井幕【观感截图】—— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/ch3_slime_shot.tscn --quit-after 12000
##
## 出三张：史莱姆堵在裂隙门前 → 玩家走近（对话开场）→ 泼酒后只剩粘液尸体。

const DIR: String = "res://tests/ch3_slime_shots/"
const MINE: String = "res://scenes/mine.tscn"
const PLAYER_POS: Vector2 = Vector2(196, 906)


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	await get_tree().process_frame

	QuestLog.reset()
	var scene: Node = (load(MINE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)

	# 和第 4 幕一致：西蒙站在矿道里，史莱姆堵住通往裂隙门的路。
	Chapter3Story._place_npc("miner_simon", Vector2(235, 872), "left", {})
	Chapter3Story._spawn_slimes()
	_place_player(PLAYER_POS, Vector2i.RIGHT)
	await _wait(12)
	await _shot("01_blocked.png")
	_dump_layout()

	# 走近一点，看得清史莱姆的体型与站位。
	_place_player(Vector2(214, 912), Vector2i.RIGHT)
	await _wait(12)
	await _shot("02_near.png")

	# 泼酒 → 逐只崩解成粘液尸体
	Chapter3Story._force_kill_slimes()
	await _wait(45)
	await _shot("03_dead.png")

	print("[ch3_slime_shot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _place_player(pos: Vector2, facing: Vector2i) -> void:
	var player: Player = get_tree().current_scene.get_node("Sorted/Player") as Player
	player.teleport_to(pos)
	player.face(facing)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	print("[ch3_slime_shot] %s raw=%dx%d step=%d" % [
			file_name, img.get_width(), img.get_height(), step])
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)


## 把关键节点的世界坐标换算成屏幕坐标，核对构图（史莱姆是否真在通往裂隙门的路上）。
func _dump_layout() -> void:
	var scene: Node = get_tree().current_scene
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var report: Array[String] = []
	for n: Node in scene.find_children("*", "Node2D", true, false):
		var nm: String = str(n.name)
		if nm.begins_with("Slime_") or nm.begins_with("Npc_beat_") or nm.begins_with("Rift"):
			var n2d: Node2D = n as Node2D
			report.append("%s world=%s screen=%s" % [nm, n2d.global_position,
					n2d.get_global_transform_with_canvas().origin])
	if player != null:
		report.append("Player world=%s screen=%s cam_zoom=%s" % [player.global_position,
				player.get_global_transform_with_canvas().origin,
				str((player.get_node("Camera") as Camera2D).zoom)])
	for line: String in report:
		print("[layout] ", line)
