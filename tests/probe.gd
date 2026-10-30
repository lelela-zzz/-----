extends Node
## 定点取景：把角色摆到指定坐标截图，用来复现"某处观感不对"。
##   "<godot.exe>" res://tests/probe.tscn
## 改 SPOTS 就能拍别的地方。坐标是**脚底**（角色节点原点）。

const ENTRY_SCENE := "res://scenes/world.tscn"
const DIR := "res://tests/probe_shots/"

## [文件名, 脚底坐标]
const SPOTS: Array = [
	["bench_t1_west_133_152", Vector2(133.0, 152.0)],
	["bench_t3_north_133_240", Vector2(133.0, 240.0)],
	["bench_t4_east_271_240", Vector2(271.0, 240.0)],
]

var scene: Node2D
var player: Player


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	scene = (load(ENTRY_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	player = scene.get_node("Sorted/Player") as Player
	Engine.max_fps = 60
	var clock: GameClock = scene.get_node("Clock") as GameClock
	clock.running = false
	clock.set_time(12, 0)
	await _wait(10)

	for entry: Array in SPOTS:
		player.velocity = Vector2.ZERO
		player.global_position = entry[1]
		await _wait(8)
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(DIR + str(entry[0]) + ".png")
		# 同时存一张以角色为中心的 4 倍放大图，方便看细节
		var c: Vector2i = Vector2i(entry[1]) + Vector2i(0, -24)
		var half := Vector2i(64, 48)
		var box := Rect2i(c - half, half * 2)
		box = box.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		var zoom: Image = img.get_region(box)
		zoom.resize(box.size.x * 4, box.size.y * 4, Image.INTERPOLATE_NEAREST)
		zoom.save_png(DIR + str(entry[0]) + "_zoom.png")
		print("shot ", entry[0], " @ ", entry[1])

	print("probe done: ", DirAccess.get_files_at(DIR))
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
