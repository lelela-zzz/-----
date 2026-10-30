extends Node
## 序章观感截图（窗口模式）：序言卡 / 萃歌开场 / 任务追踪 / 凯瑟琳菜单 / 集市 / 地图。
##   "<godot.exe>" --path . res://tests/prologue_shot.tscn --quit-after 9000
## 注意：这个驱动**故意不关** Story —— 拍的就是序章自己的 UI。

const DIR := "res://tests/prologue_shots/"

var scene: Node2D
var village: Node2D
var player: Player


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	Engine.max_fps = 60
	await get_tree().process_frame

	# 同 vshot：挂 root + 抢 current_scene，让 Story 的场景感知生效
	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	player = scene.get_node("Sorted/Player") as Player

	# 1) 序言卡第一页
	await _until_modal(PrologueCard, 60)
	await _shot("01_intro_card.png")

	# 2) 关卡 → 萃歌开场白（她站在吧台后面）
	var card: PrologueCard = _modal_of(PrologueCard) as PrologueCard
	if card != null:
		card.close()
	await _until_modal(UiPanel, 30)
	await _wait(6)
	await _shot("02_cuige_open_talk.png")

	# 3) 台词走完 → 左上任务追踪 + 吧台后的萃歌
	await _finish_dialogue()
	player.global_position = Vector2(170, 138)
	await _wait(10)
	await _shot("03_quest_tracker.png")

	# 4) 到集市找凯瑟琳 → 她的集市对话 → 选项菜单（村庄这一刻才挂上来，别让它的画盖住酒馆）
	village = (load("res://scenes/village.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(village)
	get_tree().current_scene = village
	await _wait(10)
	player = village.get_node("Sorted/Player") as Player
	var catherine: Npc = _npc_by_id("market_catherine")
	player.global_position = Vector2(260, 778)
	await _wait(10)
	if catherine != null:
		catherine.talk()
	await _until_modal(UiPanel, 30)
	await _wait(6)
	await _shot("04_catherine_talk.png")  # 凯瑟琳的集市台词（非通用模板）
	await _finish_dialogue(ChoicePanel)
	await _shot("05_catherine_menu.png")

	# 5) 选「采购物资」→ 集市面板（带 [R] 买5 提示）
	var menu: ChoicePanel = _modal_of(ChoicePanel) as ChoicePanel
	if menu != null:
		menu.option_chosen.emit(0)
		menu.close()
	await _until_modal(ShopPanel, 30)
	await _shot("06_shop_panel.png")

	# 6) 关掉集市，按 M 看地图
	var shop: UiPanel = _modal_of(ShopPanel) as UiPanel
	if shop != null:
		shop.close()
	await _wait(6)
	_push_key(KEY_M)
	await _until_modal(MapPanel, 30)
	await _shot("07_map_panel.png")

	print("[proshot] done")
	get_tree().quit()


# ---- 工具 ---------------------------------------------------------------

func _until_modal(type: Variant, frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame
		if _modal_of(type) != null:
			return


func _modal_of(type: Variant) -> UiPanel:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and is_instance_of(n, type):
			return n as UiPanel
	return null


## 连按 E 直到对话框收摊；stop_at 传面板类型时看到它就停手。
func _finish_dialogue(stop_at: Variant = null) -> void:
	for i: int in 40:
		if stop_at != null and _modal_of(stop_at) != null:
			break
		if _modal_of(UiPanel) == null:
			break
		_push_key(KEY_E)
		await get_tree().process_frame
		await get_tree().process_frame
	await _wait(4)


func _npc_by_id(id: String) -> Npc:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = n as Npc
		if npc != null and npc.npc_id == id:
			return npc
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
	var img: Image = get_viewport().get_texture().get_image()
	# 显示器缩放可能是分数（如 175%）→ 视口按窗口分辨率渲染，图会比 640×384 大；
	# 统一按整数倍缩回设计像素，出图尺寸才不会随显示设置变。
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
