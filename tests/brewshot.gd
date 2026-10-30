extends Node
## 窗口模式验收：酿酒机制的可视部分（锅 / 面板 / 缺料态 / 扩容压力 / 集市）。
## 跑法：  "<godot.exe>" --path . res://tests/brewshot.tscn   （不要加 --headless）
## headless 下 frame_post_draw 永不触发，截图会卡死 —— 必须真机窗口。
##
## 后段会**临时往 ItemDB 里塞 4 条假配方**（含 4 味料、5 味料各一条），
## 用来验证"配方变多、料变多"时版面还撑得住。塞完不落盘，进程退出即恢复。

const DIR := "res://tests/brew_shots/"
const WORLD := "res://scenes/world.tscn"
const VILLAGE := "res://scenes/village.tscn"
## 锅在酒馆正下方的地窖里、地窖灯正下方 (320,634)；
## 站在 (320,640)：脚在触发区(y578-658)内、且刚好落在锅体碰撞(结束于 y633)下方不重叠。
const POT_STAND := Vector2(320, 640)

var scene: Node = null
var player: Player = null


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	Engine.max_fps = 60
	# _ready 里 root 还在"搭子节点"，直接 add_child 会被拒，先让一帧
	await get_tree().process_frame

	scene = (load(WORLD) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(8)
	player = scene.get_node("Sorted/Player") as Player

	_seed_purse()

	# 1) 锅与 [E] 提示
	await _place_player(POT_STAND)
	await _wait(10)
	await _shot("01_pot.png")
	await _shot("02_prompt.png")

	# 2) 打开面板（空锅，5 条真配方）
	await _press_interact()
	await _wait(10)
	await _shot("03_panel.png")
	await _shot_zoom("03_panel_2x.png")

	# 3) 投两锅 → 发酵中 → 可取
	BrewingService.start("r_burnt_ale")
	BrewingService.start("r_river_ale")
	BrewingService.advance(15.0)
	await _wait(6)
	await _shot("04_fermenting.png")

	BrewingService.advance(15.0)
	await _wait(6)
	await _shot("05_ready.png")
	await _shot_zoom("05_ready_2x.png")

	# 4) 收一锅
	var got: String = BrewingService.collect(0)
	print("[brewshot] 收取:", got, " 库存:", Inventory.count(got))
	await _wait(6)
	await _shot("06_collected.png")

	# 5) 缺料态
	Inventory.clear()
	await _wait(6)
	await _shot("07_broke.png")

	# 6c) 只买得到集市货时：雪山泉/月痕河泉 不在集市 → 焦麦烈啤/清口米酿 变缺料
	Inventory.clear()
	for id: String in ItemDB.market_item_ids():
		Inventory.add(id, 4)
	await _wait(6)
	await _shot("07b_market_only.png")
	_seed_purse()
	await _wait(4)

	# 6) 关面板
	await _press_escape()
	await _wait(10)
	await _shot("08_pot_after_close.png")

	# 7) 扩容压力：塞 4 条假配方（三味/四味/五味各一条），重开面板看窗口与料位
	_inject_stress_recipes()
	await _press_interact()
	await _wait(10)
	await _shot("09_many_recipes.png")
	await _shot_zoom("09_many_recipes_2x.png")

	# 往下滚到压力配方那几行：6 次到四味料，7 次到五味料
	for i in 6:
		await _press_key(KEY_S)
	await _wait(6)
	await _shot("10_scrolled_4ing.png")
	await _shot_zoom("10_scrolled_4ing_2x.png")

	await _press_key(KEY_S)
	await _wait(6)
	await _shot("11_scrolled_5ing.png")
	await _shot_zoom("11_scrolled_5ing_2x.png")
	await _press_escape()
	await _wait(6)
	_clear_stress_recipes()

	# 8) 集市（行优先 2×5 + 翻页窗口）
	scene.queue_free()
	await _wait(4)
	scene = (load(VILLAGE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(8)
	player = scene.get_node("Sorted/Player") as Player
	await _place_player(Vector2(235, 790))
	await _wait(12)
	await _shot("12_market_prompt.png")

	# 集市摊位旁边现在站着 NPC，按 E 会先被对话抢走（近者优先），
	# 这张图要验的是面板排版，所以直接把面板挂上去，不绕触发区。
	var shop: Node = (load("res://scenes/ui/shop_panel.tscn") as PackedScene).instantiate()
	scene.get_node("HUD").add_child(shop)
	await _wait(10)
	await _shot("13_shop.png")
	await _shot_zoom_rect("13_shop_2x.png", Rect2(70, 66, 500, 252))

	print("[brewshot] 全部截图完成")
	get_tree().quit()


func _seed_purse() -> void:
	BrewingService.reset()
	Inventory.clear()
	Inventory.copper = 200
	for id: String in ItemDB.ingredient_ids():
		Inventory.add(id, 4)


## 临时塞进 4 条配方：一条三味、一条四味、一条五味、一条两味。
## 只改内存里的字典，不写盘。
func _inject_stress_recipes() -> void:
	var fake: Array = [
		{"id": "r_stress_3", "inputs": ["honey", "ginger", "wild_berry"],
			"output": "wine_friend_malt_tea", "name": "试作·三味"},
		{"id": "r_stress_4", "inputs": ["white_rice", "moon_river_spring", "honey", "barley"],
			"output": "wine_rice_brew", "name": "试作·四味"},
		{"id": "r_stress_5", "inputs": ["burnt_malt", "snow_spring", "ginger", "honey", "malt_tea"],
			"output": "wine_burnt_ale", "name": "试作·五味"},
		{"id": "r_stress_2", "inputs": ["barley", "fish_mint"],
			"output": "wine_river_ale", "name": "试作·两味"},
	]
	for f: Dictionary in fake:
		var inputs: Array = []
		for id: String in (f["inputs"] as Array):
			inputs.append({"id": id, "count": 1})
		# 顺手造一条同名酒品，截图里才分得清哪行是几条料（否则会跟真酒重名）
		var fake_item: String = "wine_" + str(f["id"])
		ItemDB.items[fake_item] = {"id": fake_item, "name": str(f["name"]), "kind": "wine",
				"tier": 1, "price": 1, "icon": ItemDB.item(str(f["output"]))["icon"]}
		ItemDB.recipes[str(f["id"])] = {"id": str(f["id"]), "output": fake_item,
				"yield": 1, "tier": 1, "minutes": 30, "inputs": inputs}
		ItemDB.recipe_order.append(str(f["id"]))
	print("[brewshot] 灌入压力配方后共 ", ItemDB.recipe_order.size(), " 条")


func _clear_stress_recipes() -> void:
	for rid: String in ["r_stress_3", "r_stress_4", "r_stress_5", "r_stress_2"]:
		ItemDB.recipes.erase(rid)
		ItemDB.recipe_order.erase(rid)
		ItemDB.items.erase("wine_" + rid)


func _place_player(pos: Vector2) -> void:
	if player == null:
		return
	player.global_position = pos
	var cam: Node = player.get_node_or_null("Camera")
	if cam != null and cam.has_method("snap_now"):
		cam.snap_now()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _press_interact() -> void:
	await _press_key(KEY_E)


func _press_escape() -> void:
	await _press_key(KEY_ESCAPE)


func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up: InputEventKey = InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(2)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(DIR + file_name)
	if err != OK:
		print("[brewshot] 存图失败 ", file_name, " err=", err)


## 酿酒面板当前的外框（改版面时只改这一处）
const PANEL_RECT: Rect2 = Rect2(30, 46, 580, 292)


func _shot_zoom(file_name: String) -> void:
	await _shot_zoom_rect(file_name, PANEL_RECT)


func _shot_zoom_rect(file_name: String, rect: Rect2) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var region: Image = img.get_region(Rect2i(rect))
	region.resize(int(rect.size.x) * 2, int(rect.size.y) * 2, Image.INTERPOLATE_NEAREST)
	var err: int = region.save_png(DIR + file_name)
	if err != OK:
		print("[brewshot] 存图失败 ", file_name, " err=", err)
