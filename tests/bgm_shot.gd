extends Node
## 设置面板（含音乐音量行）观感截图：
##   "<godot.exe>" --path . res://tests/bgm_shot.tscn --quit-after 9000
##
## 只做两件事：进酒馆、按 F10 打开面板，选中"音乐音量"行拍一张。不改任何存盘设置。

const DIR: String = "res://tests/bgm_shots/"

var _panel: UiPanel


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	Engine.max_fps = 60
	await get_tree().process_frame

	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(40)

	print("[bgmshot] current_track=%s playing=%s db=%.1f" % [
			Music.current_track(), Music.is_playing(), Music.volume_db_now()])

	_push_key(KEY_F10)
	for i: int in 60:
		await get_tree().process_frame
		if _modal() != null:
			break
	_panel = _modal()
	if _panel == null:
		print("[bgmshot] 面板没开出来")
		get_tree().quit(1)
		return

	_panel.set("_index", 3)
	_panel._refresh()
	await _wait(10)
	await _shot("01_settings_music.png")

	_panel.close()
	await _wait(4)
	await _shot("02_tavern_running.png")
	print("[bgmshot] done")
	get_tree().quit()


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
