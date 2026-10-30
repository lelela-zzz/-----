extends Node
## 2× 真实渲染下的对话框取景：NPC 单说话人框 + 支线多说话人框 + 卖酒面板。
##   "<godot.exe>" --path . res://tests/dlg_shot.tscn --quit-after 9000
##
## 故意**不**调 TestView.logic_resolution()：这里要看的就是 1280×768 的真实渲染。

const DIR: String = "res://tests/dlg_shots/"

var scene: Node2D


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	WindowScale.set_display_scale(1.5)
	await get_tree().process_frame

	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(30)

	# 摆一位老板娘，玩家站到她旁边
	var defs: Dictionary = _load_defs()
	var npc: Npc = _place(defs, "tavern_cuige", Vector2(76, 100))
	var player: Node2D = scene.get_node("Sorted/Player") as Node2D
	player.global_position = Vector2(80, 106)
	await _wait(20)

	# 1) NPC 单说话人对话框
	if npc != null:
		npc._open_dialogue()
	await _wait(40)
	await _shot("01_npc_dialogue.png")
	_close_all()
	await _wait(10)

	# 2) 支线多说话人框（长句 + 旁白 + 两个说话人）
	var ps: PackedScene = load("res://scenes/ui/story_dialogue.tscn") as PackedScene
	var box: UiPanel = ps.instantiate() as UiPanel
	box.set("entries", [
		{"speaker": "", "role": "", "text": "炉火噼啪响了一声，雪水顺着屋檐往下淌。"},
		{"speaker": "哈特菲利亚", "role": "FAIRY TAIL 魔导士",
			"text": "黑松山脉的雪一年比一年厚。半年前有一支商队想翻过垭口，走到一半就再没下来过——我在雪里找到他们的时候，只剩下一面旗子。"},
		{"speaker": "拜登", "role": "酒馆老板",
			"text": "……那你还打算上去？"},
		{"speaker": "哈特菲利亚", "role": "FAIRY TAIL 魔导士",
			"text": "总得有人上去。你要是哪天备够了酒，就来找我。"},
	])
	_ui_root().add_child(box)
	await _wait(60)
	await _shot("02_story_dialogue.png")
	_close_all()
	await _wait(10)

	# 3) 卖酒面板（同样是 640 逻辑坐标的老 UI）
	Inventory.add("wine_warm_ginger", 3)
	var cust_ps: PackedScene = load("res://scenes/ui/sell_panel.tscn") as PackedScene
	var sell: UiPanel = cust_ps.instantiate() as UiPanel
	sell.set("customer", null)
	_ui_root().add_child(sell)
	await _wait(30)
	await _shot("03_sell_panel.png")
	_close_all()
	await _wait(10)

	# 4) 兜底验证：故意把对话框塞进 CanvasLayer（口径 1280×768，不是 640×384），
	#    UiPanel._fit_canvas 应该把它自己换算成 2× 铺满，而不是缩在左上角。
	var dlg_ps: PackedScene = load("res://scenes/ui/dialogue_box.tscn") as PackedScene
	var stray: UiPanel = dlg_ps.instantiate() as UiPanel
	stray.set("speaker", "萃歌")
	stray.set("role", "酒馆老板娘")
	stray.set("lines", PackedStringArray([
		"这一条是故意挂到 CanvasLayer 上的，用来验证画布会自动换算。"]))
	scene.get_node("HUD").add_child(stray)
	await _wait(30)
	await _shot("04_stray_on_canvaslayer.png")
	print("  stray canvas_scale=%.2f size=%s" % [stray.canvas_scale, stray.size])
	_close_all()
	await _wait(10)

	print("[dlg_shot] done -> %s" % DIR)
	get_tree().quit()


func _ui_root() -> Node:
	var ui: Node = scene.get_node_or_null("HUD/UIRoot")
	return ui if ui != null else scene.get_node("HUD")


func _close_all() -> void:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		(n as UiPanel).close()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + name)
	print("  -> ", name)


func _load_defs() -> Dictionary:
	var out: Dictionary = {}
	var f: FileAccess = FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		for d: Variant in ((data as Dictionary).get("npcs", []) as Array):
			out[str((d as Dictionary).get("id", ""))] = d
	return out


func _place(defs: Dictionary, id: String, at: Vector2) -> Npc:
	var def: Dictionary = defs.get(id, {}) as Dictionary
	if def.is_empty():
		return null
	var ps: PackedScene = load("res://scenes/npc.tscn") as PackedScene
	var npc: Npc = ps.instantiate() as Npc
	npc.name = "Npc_" + id
	npc.configure(def, {"scene": "world", "pos": [at.x, at.y],
			"facing": "down", "wander": 0.0})
	scene.get_node("Sorted").add_child(npc)
	return npc
