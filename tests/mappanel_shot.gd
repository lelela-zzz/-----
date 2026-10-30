extends Node
## M 地图面板【排版】观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/mappanel_shot.tscn --quit-after 9000
##
## 面板高度按"本次实际列出的去处条数"自适应（3 项 192 / 5 项 272），
## 这里固定两张对照图，确认两种条数下都不留大块空白、文字也不出框：
##   01_three.png —— 初始 3 项（酒馆 / 集市 / 酒馆门口）；
##   02_four.png  —— 解锁「矿道入口」后 4 项。
const DIR := "res://tests/map_shots/"

var scene: Node


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	await get_tree().process_frame

	QuestLog.reset()
	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	for i: int in 8:
		await get_tree().process_frame

	var hud: Node = UiStyle.ui_layer(self)
	var p1: MapPanel = MapPanel.new()
	hud.add_child(p1)
	for i: int in 6:
		await get_tree().process_frame
	await _shot("01_three.png")
	p1.queue_free()
	for i: int in 4:
		await get_tree().process_frame

	SideStory.unlock("mine_entrance")
	var p2: MapPanel = MapPanel.new()
	hud.add_child(p2)
	for i: int in 6:
		await get_tree().process_frame
	await _shot("02_four.png")
	p2.queue_free()

	print("[mappanel_shot] done")
	get_tree().quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
