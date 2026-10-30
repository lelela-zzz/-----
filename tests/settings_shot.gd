extends Node
## 显示设置面板观感截图（窗口模式）：
##   "<godot.exe>" --path . res://tests/settings_shot.tscn --quit-after 9000
##
## 走真实入口（推一个 F10 键），拍窗口化 / 全屏 两套状态。
## 全屏那两张**只改状态不真的进全屏**（panel._refresh 手动重画），免得
## 截图脚本把开发机卡在全屏里。

const DIR: String = "res://tests/settings_shots/"

var scene: Node2D
var panel: UiPanel


func _ready() -> void:
	TestView.logic_resolution()
	# 关掉序章和顾客：镜头里只要酒馆背景 + 设置面板
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	Engine.max_fps = 60
	await get_tree().process_frame

	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(30)

	# 1) 真实入口：F10 打开设置
	_push_key(KEY_F10)
	for i: int in 60:
		await get_tree().process_frame
		if _modal() != null:
			break
	panel = _modal()
	if panel == null:
		print("[setshot] 面板没开出来")
		get_tree().quit(1)
		return
	await _wait(8)
	await _shot("01_windowed.png")

	# 2) 全屏状态（只看界面，不动真窗口）
	WindowScale.fullscreen = true
	WindowScale.fill_screen = false
	panel.set("_index", 2)
	panel._refresh()
	await _wait(4)
	await _shot("02_fullscreen_integer.png")

	# 3) 全屏 + 铺满
	WindowScale.fill_screen = true
	panel._refresh()
	await _wait(4)
	await _shot("03_fullscreen_fill.png")

	# 还原内存与盘上的设置
	WindowScale.reset_to_defaults()
	WindowScale.save_settings()
	panel.close()
	print("[setshot] done")
	get_tree().quit()


# ---- 工具 ---------------------------------------------------------------

func _modal() -> UiPanel:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and n is UiPanel:
			return n as UiPanel
	return null


func _push_key(keycode: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_viewport().push_input(down)
	var up: InputEventKey = InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_viewport().push_input(up)


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	(get_viewport().get_texture().get_image()).save_png(DIR + file_name)
