extends Node
## 存档观感截图（窗口模式）：
##   "<godot.exe>" --path . res://tests/save_shot.tscn --quit-after 9000
##
## 拍四张：游戏内存档面板 / 左上角提示条 / 标题界面（有档时）/ 读取存档面板。
## 统一按 1280×768 原生出图（不缩回 640）—— 面板本身按 640 设计、2× 渲染，
## 出原图才看得出字锐不锐。

const DIR := "res://tests/save_shots/"
const WORLD := "res://scenes/world.tscn"
const TITLE := "res://scenes/title.tscn"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	Engine.max_fps = 60
	_clear_saves()
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = false
	Story.stage = StoryDirector.Stage.OPEN
	await get_tree().process_frame

	# ---- 造一份像样的进度 ----
	var scene: Node = (load(WORLD) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(10)
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	clock.day = 4
	clock.set_time(16, 40)
	Inventory.earn(214)
	Inventory.add("ginger", 3)
	Inventory.add("barley", 5)
	QuestLog.add("shot_q", "去集市进一批酿酒材料", "", {})
	await _wait(6)

	# 1) 存档面板（空档位）
	_push_key(KEY_F5)
	await _wait(6)
	await _shot("01_save_panel_empty.png")

	# 2) 真存一档，看覆盖提示与"已存入"的状态
	_push_key(KEY_E)
	await get_tree().create_timer(0.3).timeout
	await _shot("02_save_panel_saved.png")
	await get_tree().create_timer(0.8).timeout

	# 3) 左上角提示条（连任务书一起拍）
	await _shot("03_hud_hint.png")

	# 4) 覆盖确认：再按一次 F5 / E
	_push_key(KEY_F5)
	await _wait(6)
	_push_key(KEY_E)
	await _wait(4)
	await _shot("04_save_overwrite_arm.png")
	_push_key(KEY_ESCAPE)
	await _wait(4)

	# ---- 标题界面 ----
	get_tree().change_scene_to_file(TITLE)
	await _wait(120)
	await _shot("05_title_with_save.png")
	_push_key(KEY_S)          # 继续游戏 → 读取存档
	await _wait(4)
	_push_key(KEY_E)
	await _wait(8)
	await _shot("06_load_panel.png")

	print("[save_shot] done")
	get_tree().quit()


func _clear_saves() -> void:
	for i: int in range(1, SaveGame.SLOT_COUNT + 1):
		var path: String = ProjectSettings.globalize_path(SaveGame.slot_path(i))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var last: String = ProjectSettings.globalize_path(SaveGame.LAST_PATH)
	if FileAccess.file_exists(last):
		DirAccess.remove_absolute(last)


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
