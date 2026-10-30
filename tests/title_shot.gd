extends Node
## 开始界面观感截图（窗口模式）：
##   "<godot.exe>" --path . res://tests/title_shot.tscn --quit-after 9000
##
## 这一屏按 1280×768 原生渲染排版，出图**不缩回 640**（缩了就看不出字锐不锐）。

const DIR := "res://tests/title_shots/"

var scene: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	Engine.max_fps = 60
	await get_tree().process_frame

	scene = (load("res://scenes/title.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene

	# 淡入 0.85s + 粒子预热，多等一会儿
	await _wait(110)
	await _shot("01_title.png")

	# 键盘下移一项 → 选中态
	_push_key(KEY_S)
	await _wait(8)
	await _shot("02_menu_move.png")

	# 打开设置面板
	_push_key(KEY_E)
	await _wait(24)
	await _shot("03_settings.png")

	# 关掉面板，回到菜单并选最后一项（退出游戏，只是看选中态，不真退）
	var panel: UiPanel = null
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if n is UiPanel:
			panel = n as UiPanel
	if panel != null:
		panel.close()
	await _wait(6)
	_push_key(KEY_S)
	await _wait(8)
	await _shot("04_menu_quit.png")

	# 存档位：选中灰掉的「继续游戏」，再按 E 看那句「暂无存档」闪一下
	_push_key(KEY_W)
	_push_key(KEY_W)
	_push_key(KEY_W)
	_push_key(KEY_W)
	await _wait(8)
	await _shot("05_save_slot_disabled.png")
	_push_key(KEY_E)
	await _wait(4)
	await _shot("06_save_slot_note_flash.png")

	# 真的点进游戏：回到「开始游戏」→ E，看淡出后接上的是不是酒馆
	_push_key(KEY_S)
	_push_key(KEY_S)
	await _wait(8)
	await _shot("07_menu_start.png")
	_push_key(KEY_E)
	await _wait(50)
	await _shot("08_fade_out.png")
	await _wait(160)      # 序章卡 / 萃歌开场，等它铺开
	await _shot("09_into_game.png")

	print("[title_shot] done")
	get_tree().quit()


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
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(DIR + file_name)
