extends Node
## 酒馆 ↔ 地窖【观感】出图（窗口模式）。地窖已并进 world.tscn 上半层，没有传送。
##   01_door_closed.png —— 站远处：左上角那扇门**原样关着**（门板裁片不透明，和原图一模一样）
##   00d_tavern_shade.png —— 站到北墙跟前：店堂亮、上层地窖被一层阴影压着
##   02_door_open.png   —— 走到门前：门虚掉了，露出后面地窖那段楼梯
##   03_in_doorway.png  —— 人正站在门洞里（半身在店堂、半身已经踩上楼梯）
##   04_cellar_side.png —— 走进地窖回身看：地窖、木桶、吊灯，脚下那截楼梯通回酒馆
##   05_pot.png         —— 地窖里的锅
##   "<godot.exe>" --path . res://tests/passage_shot.tscn --quit-after 9000

const WORLD := "res://scenes/world.tscn"
const DIR := "res://tests/passage_shots/"


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	await get_tree().process_frame

	var old: Node = get_tree().current_scene
	if old != null and old != self:
		old.queue_free()
		await get_tree().process_frame
	var scene: Node = (load(WORLD) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(12)

	_place(Vector2(320, 270))       # 店堂中央：离门 ~270px，门关着
	await _wait(24)
	await _shot("01_door_closed.png")

	_place(Vector2(320, 100))       # 站到北墙跟前：能看到上层的阴影压着
	await _wait(40)
	await _shot("00d_tavern_shade.png")

	_place(Vector2(126, 96))        # 门前：门已虚到底，楼梯露出来
	await _wait(40)
	await _shot("02_door_open.png")

	_place(Vector2(126, 40))        # 站在门洞里
	await _wait(24)
	await _shot("03_in_doorway.png")

	_place(Vector2(230, -160))      # 地窖里
	await _wait(24)
	await _shot("04_cellar_side.png")

	_place(Vector2(126, -110))      # 站到楼梯中段往回看：屏幕下方那块店堂被反向阴影压着
	await _wait(40)
	await _shot("06_tavern_dim.png")

	_place(Vector2(278, -140))      # 锅前（锅底 278,-193）
	await _wait(24)
	await _shot("05_pot.png")

	print("[passage_shot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _place(pos: Vector2) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: Player = scene.get_node_or_null("Sorted/Player") as Player
	if player == null:
		return
	player.velocity = Vector2.ZERO
	player.global_position = pos
	var cam: PixelCamera = player.get_node_or_null("Camera") as PixelCamera
	if cam != null:
		cam.snap_now()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var err: int = (get_viewport().get_texture().get_image()).save_png(DIR + file_name)
	if err != OK:
		print("save failed ", file_name, " err=", err)
