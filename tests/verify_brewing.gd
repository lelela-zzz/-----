extends Node
## 无窗口验收：酿造状态机 + 锅已接入酒馆。
## 跑法：godot --headless --path . res://tests/verify_brewing.tscn

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	StoryDirector.force_disable = true
	print("[brew] ── 状态机 ──")
	BrewingService.reset()
	Inventory.clear()

	_check("三口锅初始全空", _empty_count() == 3, "实际 %d" % _empty_count())
	_check("没材料时开不了锅", BrewingService.start("r_burnt_ale") == -1)

	# 备足焦麦烈啤的材料：焦麦×2 + 雪山泉×1
	Inventory.add("burnt_malt", 6)
	Inventory.add("snow_spring", 3)
	_check("材料齐了能开锅", BrewingService.can_start("r_burnt_ale"))
	var slot: int = BrewingService.start("r_burnt_ale")
	_check("开锅落在 0 号槽", slot == 0, "实际 %d" % slot)
	_check("投料即扣（焦麦 6→4）", Inventory.count("burnt_malt") == 4, str(Inventory.count("burnt_malt")))
	_check("投料即扣（雪山泉 3→2）", Inventory.count("snow_spring") == 2, str(Inventory.count("snow_spring")))
	_check("槽位进入发酵", int(BrewingService.slots[0]["state"]) == BrewingService.State.FERMENTING)

	BrewingService.advance(15.0)
	_check("走一半还不能收", int(BrewingService.slots[0]["state"]) == BrewingService.State.FERMENTING)
	_check("进度约 0.5", absf(BrewingService.progress(0) - 0.5) < 0.01, str(BrewingService.progress(0)))

	BrewingService.advance(15.0)
	_check("满 30 分钟转可取", int(BrewingService.slots[0]["state"]) == BrewingService.State.READY)
	_check("可取数 = 1", BrewingService.ready_count() == 1)
	_check("进度到 1", absf(BrewingService.progress(0) - 1.0) < 0.001, str(BrewingService.progress(0)))

	var out_id: String = BrewingService.collect(0)
	_check("收酒拿到焦麦烈啤", out_id == "wine_burnt_ale", out_id)
	_check("酒进了库存", Inventory.count("wine_burnt_ale") == 1, str(Inventory.count("wine_burnt_ale")))
	_check("收完槽位清空", int(BrewingService.slots[0]["state"]) == BrewingService.State.EMPTY)

	print("[brew] ── 五条配方逐一跑通 ──")
	for rid: String in ItemDB.recipe_ids():
		BrewingService.reset()
		Inventory.clear()
		_seed_inputs(rid)
		var idx: int = BrewingService.start(rid)
		_check("配方 %s 能开锅" % rid, idx >= 0, "槽 %d" % idx)
		BrewingService.advance(30.0)
		var brewed: String = BrewingService.collect(idx)
		_check("配方 %s 出酒正确" % rid, brewed == str(ItemDB.recipe(rid)["output"]), brewed)

	print("[brew] ── 满载 ──")
	BrewingService.reset()
	Inventory.clear()
	for id: String in ["burnt_malt", "snow_spring", "ginger", "wild_berry", "white_rice",
			"moon_river_spring", "malt_tea", "honey", "barley", "fish_mint"]:
		Inventory.add(id, 6)
	for rid: String in ["r_burnt_ale", "r_warm_ginger", "r_rice_brew"]:
		BrewingService.start(rid)
	_check("三槽满后开不了第四锅", BrewingService.start("r_river_ale") == -1)

	BrewingService.advance(30.0)
	_check("三锅同时可取", BrewingService.ready_count() == 3, str(BrewingService.ready_count()))
	for i in 3:
		_check("第 %d 锅能收" % (i + 1), BrewingService.collect(i) != "")

	print("[brew] ── 时间换算 ──")
	_check("一条配方 = 15 现实秒", absf(BrewingService.recipe_seconds("r_burnt_ale") - 15.0) < 0.01,
			str(BrewingService.recipe_seconds("r_burnt_ale")))

	print("[brew] ── 接入酒馆（地窖已并进 world.tscn 上半层）──")
	# 锅在 world.tscn 的 Sorted 下、地窖吊灯正下方。地窖那张图贴在酒馆底图上方
	# （offset -22,-398），所以地窖局部坐标 (300,205) = 世界坐标 (278,-193)。
	var world: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	add_child(world)
	for i in 6:
		await get_tree().process_frame

	var pot: Node = world.get_node_or_null("Sorted/BrewingPot")
	_check("地窖里有锅", pot != null)
	if pot != null:
		_check("锅在地窖灯正下方 (278,-193)", pot.position == Vector2(278, -193), str(pot.position))
		_check("锅有碰撞体", pot.get_node_or_null("Body/Collision") != null)
		_check("锅有交互区", pot.get_node_or_null("Zone") != null)
		_check("锅的交互区挂了酿造面板",
				pot.get_node_or_null("Zone") != null and pot.get_node("Zone").panel_scene != null)

	var textures_ok: bool = true
	for st: String in ["pot_empty", "pot_full"]:
		for suffix: String in ["_dawn", "", "_dusk", "_night"]:
			if load("res://assets/items/pot/%s%s.png" % [st, suffix]) == null:
				textures_ok = false
	_check("锅的 8 张时段贴图齐全", textures_ok)

	var clock_in_group: Node = get_tree().get_first_node_in_group("game_clock")
	_check("时钟已进 game_clock 组", clock_in_group != null)
	_check("时钟在酒馆场景里", clock_in_group != null and world.is_ancestor_of(clock_in_group))

	var player: Node = world.get_node_or_null("Sorted/Player")
	_check("玩家已进 player 组", player != null and player.is_in_group("player"))
	if player != null:
		player.set_frozen(true)
		_check("冻结后停止 physics 处理", not player.is_physics_processing())
		player.set_frozen(false)
		_check("解冻后恢复 physics 处理", player.is_physics_processing())

	_check("interact 动作已映射 E",
			InputMap.has_action("interact") and InputMap.action_get_events("interact").size() > 0)

	print("[brew] 结论：PASS %d / FAIL %d" % [_pass, _fail])
	print("[brew] 总判定: %s" % ("PASS" if _fail == 0 else "FAIL"))
	get_tree().quit()


func _seed_inputs(recipe_id: String) -> void:
	for e: Variant in (ItemDB.recipe(recipe_id)["inputs"] as Array):
		var d: Dictionary = e as Dictionary
		Inventory.add(str(d["id"]), int(d["count"]))


func _empty_count() -> int:
	var n: int = 0
	for slot: Dictionary in BrewingService.slots:
		if int(slot["state"]) == BrewingService.State.EMPTY:
			n += 1
	return n


func _check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		_pass += 1
		print("   [check] %s: PASS" % label)
	else:
		_fail += 1
		print("   [check] %s: FAIL  %s" % [label, extra])
