extends Node
## 龙巢出图：传送门 / 洞厅全貌 / 龙首旁 / 东侧回廊。

const LAIR := "res://scenes/dragon_lair.tscn"
const DIR := "res://tests/lair_shots/"


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	await get_tree().process_frame
	var scene: Node = (load(LAIR) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(20)
	await _shot("01_portal.png")
	_place(Vector2(480, 300))
	await _wait(10)
	await _shot("02_hall.png")
	_place(Vector2(640, 400))
	await _wait(10)
	await _shot("03_beside_dragon.png")
	_place(Vector2(700, 620))
	await _wait(10)
	await _shot("04_east_corridor.png")
	# 逐幕摆人，检查「全员站在龙巢中心」的站位与 y 排序。
	Chapter3Story.wait_for_talk = true
	for step: Array in [[5, "05_cast_edward.png"], [6, "06_cast_awaken.png"], [8, "07_cast_after.png"]]:
		Chapter3Story.reset()
		Chapter3Story.begin(int(step[0]))
		_place(Vector2(470, 548))   # 玩家站在菱形下顶点（棱形第四点）
		await _wait(30)
		await _shot(str(step[1]))
	print("[lair_shot] done")
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
