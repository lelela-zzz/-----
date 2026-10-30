extends Node
## 矿道入口出图：入口 / 路中段 / 右下石拱门 三张。

const MINE_ENTRANCE := "res://scenes/mine_entrance.tscn"
const DIR := "res://tests/mine_entrance_shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	await get_tree().process_frame
	var scene: Node = (load(MINE_ENTRANCE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)
	await _shot("01_entry.png")
	_place(Vector2(736, 452))
	await _wait(10)
	await _shot("02_path_mid.png")
	_place(Vector2(430, 662))
	await _wait(10)
	await _shot("05_c4_tree.png")
	_place(Vector2(470, 880))
	await _wait(10)
	await _shot("04_lower_path.png")
	_place(Vector2(860, 780))
	await _wait(10)
	await _shot("03_arch.png")
	# 新的雪山门：最下面那条路的尽头（地图底边小径）
	_place(Vector2(452, 962))
	await _wait(10)
	await _shot("06_snow_door.png")
	print("[mine_entrance_shot] done")
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
