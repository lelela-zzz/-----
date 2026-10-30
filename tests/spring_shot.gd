extends Node
## 泉水出图：泉眼 / 右侧灰石小路 / 新的出山门（右下角路尽头）三张。

const SPRING := "res://scenes/spring.tscn"
const DIR := "res://tests/spring_shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	await get_tree().process_frame
	var scene: Node = (load(SPRING) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)
	await _shot("01_spring.png")
	_place(Vector2(395, 300))
	await _wait(10)
	await _shot("02_pool.png")
	# 右侧灰石小路中段
	_place(Vector2(690, 460))
	await _wait(10)
	await _shot("03_right_path.png")
	# 新的出山门：右侧小路下端（右下角）
	_place(Vector2(692, 660))
	await _wait(10)
	await _shot("04_snow_door.png")
	print("[spring_shot] done")
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
