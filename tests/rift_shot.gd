extends Node
## 矿井裂隙门出图：开闸前后各一张，看位置与亮度。

const MINE := "res://scenes/mine.tscn"
const DIR := "res://tests/rift_shots/"


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	await get_tree().process_frame
	var scene: Node = (load(MINE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)
	_place(Vector2(500, 760))
	await _wait(10)
	await _shot("01_closed.png")
	Chapter3Story._rift_open = true
	await _wait(30)
	await _shot("02_open.png")
	print("[rift_shot] done")
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
