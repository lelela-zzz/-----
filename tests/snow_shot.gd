extends Node
## 雪山出图：入口 / 谷地中央 / 上谷 / 木桥 / 西坡。

const SNOW := "res://scenes/snow_mountain.tscn"
const DIR := "res://tests/snow_shots/"


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	await get_tree().process_frame
	var scene: Node = (load(SNOW) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)
	await _shot("01_entry.png")
	_place(Vector2(280, 780))
	await _wait(10)
	await _shot("02_camp.png")
	_place(Vector2(600, 520))
	await _wait(10)
	await _shot("03_spring.png")
	_place(Vector2(770, 710))
	await _wait(10)
	await _shot("04_bridge.png")
	_place(Vector2(880, 770))
	await _wait(10)
	await _shot("05_far_bank.png")
	_place(Vector2(680, 300))
	await _wait(10)
	await _shot("06_upper.png")
	# 回程门（接回矿道入口）实拍，便于确认出口位置
	_place(Vector2(650, 940))
	await _wait(10)
	await _shot("07_return_door.png")
	print("[snow_shot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _place(pos: Vector2) -> void:
	var player: Player = get_tree().current_scene.get_node("Sorted/Player") as Player
	player.velocity = Vector2.ZERO
	player.global_position = pos
	var cam: PixelCamera = player.get_node("Camera") as PixelCamera
	cam.snap_now()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var err: int = (get_viewport().get_texture().get_image()).save_png(DIR + file_name)
	if err != OK:
		print("save failed ", file_name, " err=", err)
