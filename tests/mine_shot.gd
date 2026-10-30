extends Node
## 矿井出图：入口 / 中央十字 / 左上洞厅 / 右上洞厅 / 左下洞厅。

const MINE := "res://scenes/mine.tscn"
const DIR := "res://tests/mine_shots/"


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	await get_tree().process_frame
	var scene: Node = (load(MINE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)
	await _shot("01_entry.png")
	_place(Vector2(505, 470))
	await _wait(10)
	await _shot("02_crossroad.png")
	_place(Vector2(250, 255))
	await _wait(10)
	await _shot("03_left_cavern.png")
	_place(Vector2(720, 290))
	await _wait(10)
	await _shot("04_right_cavern.png")
	_place(Vector2(255, 870))
	await _wait(10)
	await _shot("05_bottom_room.png")
	print("[mine_shot] done")
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
