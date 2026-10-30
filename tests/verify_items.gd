extends Node
## 无窗口验收：数据层（ItemDB / Inventory / 集市货架）。
## 跑法：godot --headless --path . res://tests/verify_items.tscn

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	print("[items] ── 数据层 ──")
	_check("ItemDB 校验零错误", ItemDB.errors.is_empty(), str(ItemDB.errors))

	_check("物品总数 = 26", ItemDB.items.size() == 26, "实际 %d" % ItemDB.items.size())

	var ingredients: int = 0
	var wines: int = 0
	var icons_ok: bool = true
	var missing_icon: String = ""
	for id: String in ItemDB.items:
		var kind: String = str(ItemDB.item(id).get("kind", ""))
		if kind == "ingredient":
			ingredients += 1
		elif kind == "wine":
			wines += 1
		if ItemDB.icon(id) == null:
			icons_ok = false
			missing_icon = id
	_check("素材 20 / 酒 6（含剧情赠礼的雷司令）", ingredients == 20 and wines == 6, "素材 %d，酒 %d" % [ingredients, wines])
	_check("26 张图标全部可加载", icons_ok, missing_icon)

	_check("配方 5 条", ItemDB.recipe_ids().size() == 5, "实际 %d" % ItemDB.recipe_ids().size())

	var two_inputs_ok: bool = true
	var minutes_ok: bool = true
	var output_ok: bool = true
	for rid: String in ItemDB.recipe_ids():
		var r: Dictionary = ItemDB.recipe(rid)
		var n: int = (r["inputs"] as Array).size()
		if n < 2 or n > 3:
			two_inputs_ok = false
		if int(r["minutes"]) != 30:
			minutes_ok = false
		if str(ItemDB.item(str(r["output"])).get("kind", "")) != "wine":
			output_ok = false
	_check("每条配方 2~3 味料（暖身姜酒按剧情三味）", two_inputs_ok)
	_check("每条配方 30 游戏分钟（=15 现实秒）", minutes_ok)
	_check("配方产出都是酒", output_ok)

	var market: Array[String] = ItemDB.market_item_ids()
	var prices_ok: bool = true
	for id: String in market:
		if ItemDB.price(id) <= 0:
			prices_ok = false
	_check("集市上架 9 种原料（清单里标「月痕河镇·集市」的）", market.size() == 9,
			"实际 %d：%s" % [market.size(), str(market)])
	_check("上架原料都有正价", prices_ok)

	print("[items] ── 产地 ──")
	_check("集市牌子上是「月痕河镇·集市」", ItemDB.market_sign() == "月痕河镇·集市", ItemDB.market_sign())
	_check("雪山泉已从集市下架（改矿道入口）", not market.has("snow_spring"))
	_check("月痕河泉已从集市下架（改河岸）", not market.has("moon_river_spring"))
	_check("白葡萄已上集市（清单标集市）", market.has("white_grape"))

	var mine: Array[String] = ItemDB.ids_at("黑松山脉", "矿道入口")
	mine.sort()
	_check("矿道入口出 3 种：雪山泉/冷泉水/铁皮菇",
			mine == ["cold_spring", "iron_cap_mushroom", "snow_spring"], str(mine))
	var shore: Array[String] = ItemDB.ids_at("月痕河", "河岸")
	shore.sort()
	_check("河岸出 2 种：月痕河泉/夜雾花", shore == ["moon_river_spring", "night_mist_flower"], str(shore))

	var all_have_obtain: bool = true
	var bad: String = ""
	for id: String in ItemDB.items:
		if ItemDB.obtain_of(id) == "":
			all_have_obtain = false
			bad = id
	_check("每个物品都写了 obtain", all_have_obtain, bad)

	_check("产地文字：雪山泉 = 黑松山脉·矿道入口",
			ItemDB.source_text("snow_spring") == "黑松山脉·矿道入口", ItemDB.source_text("snow_spring"))
	_check("产地文字：酒 = 自己酿", ItemDB.source_text("wine_burnt_ale") == "自己酿",
			ItemDB.source_text("wine_burnt_ale"))
	_check("产地文字：未定 = 待定", ItemDB.source_text("glow_algae") == "待定")
	_check("待定产地共 6 种（清单里没写）", ItemDB.todo_item_ids().size() == 6,
			str(ItemDB.todo_item_ids()))

	var spots: Array[Dictionary] = ItemDB.spots()
	_check("采集点共 2 处（矿道入口 / 河岸）", spots.size() == 2,
			str(spots.map(func(x): return "%s·%s" % [x["map"], x["spot"]])))

	print("[items] ── 库存 ──")
	Inventory.clear()
	Inventory.copper = Inventory.START_COPPER
	Inventory.add("barley", 3)
	_check("加 3 份大麦", Inventory.count("barley") == 3, str(Inventory.count("barley")))
	_check("扣 2 份成功", Inventory.remove("barley", 2) and Inventory.count("barley") == 1)
	_check("扣超额失败且不扣", not Inventory.remove("barley", 5) and Inventory.count("barley") == 1)
	Inventory.remove("barley", 1)
	_check("扣到 0 后不留空壳", Inventory.count("barley") == 0 and not Inventory.all().has("barley"))

	var before: int = Inventory.copper
	_check("花钱成功", Inventory.spend(10) and Inventory.copper == before - 10)
	_check("钱不够不扣", not Inventory.spend(99999) and Inventory.copper == before - 10)

	print("[items] 结论：PASS %d / FAIL %d" % [_pass, _fail])
	print("[items] 总判定: %s" % ("PASS" if _fail == 0 else "FAIL"))
	get_tree().quit()


func _check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		_pass += 1
		print("   [check] %s: PASS" % label)
	else:
		_fail += 1
		print("   [check] %s: FAIL  %s" % [label, extra])
