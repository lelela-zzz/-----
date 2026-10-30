extends Node
## 物品与配方的唯一数据源（autoload：ItemDB）。
##
## 设计要点：
##  · 所有数值都躺在 data/*.json 里，代码只负责读、校验、提供查询 —— 加一种新酒
##    只要往两份 JSON 各添一条 + 放一张图标，不动任何 .gd。
##  · 启动时做一次**强校验**：配方引用的 id 必须存在、图标必须能加载。校验失败
##    不会崩游戏，但会把问题堆进 errors[] 并 push_error，headless 测试据此判红。
##  · 图标缓存住，UI 每帧重绘时不会反复 load。

const ITEMS_PATH: String = "res://data/items.json"
const RECIPES_PATH: String = "res://data/recipes.json"

## 获取方式的词表。新增一种（比如"捕鱼"）就往这里加一个常量，
## 校验和"按产地分组"会自动认它；面板不用改。
const OBTAIN_MARKET: String = "market"
const OBTAIN_MINE: String = "mine"
const OBTAIN_GATHER: String = "gather"
const OBTAIN_BREW: String = "brew"
const OBTAIN_TODO: String = "todo"
## 剧情赠礼：买不到、采不到，只能靠支线人物交到你手上（例：爱德华的雷司令）。
const OBTAIN_GIFT: String = "gift"
const OBTAIN_KINDS: Array[String] = [
	OBTAIN_MARKET, OBTAIN_MINE, OBTAIN_GATHER, OBTAIN_BREW, OBTAIN_TODO, OBTAIN_GIFT,
]

## id -> 物品字典（见 items.json）
var items: Dictionary = {}
## id -> 配方字典（见 recipes.json）
var recipes: Dictionary = {}
## 配方展示顺序，与 JSON 里的书写顺序一致
var recipe_order: Array[String] = []
## 校验发现的问题，空数组 = 数据干净
var errors: Array[String] = []
## 不致命但值得提醒的问题（比如图标尺寸不是 32 的整数倍，缩放会糊）
var warnings: Array[String] = []

var _icons: Dictionary = {}


func _ready() -> void:
	reload()


## 重新读盘（改完 JSON 不用重启编辑器）。
func reload() -> void:
	items.clear()
	recipes.clear()
	recipe_order.clear()
	_icons.clear()
	errors.clear()
	warnings.clear()

	var item_data: Dictionary = _read_json(ITEMS_PATH)
	for entry: Variant in (item_data.get("items", []) as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("items.json 有一条不是对象")
			continue
		var it: Dictionary = entry as Dictionary
		var id: String = str(it.get("id", ""))
		if id == "":
			errors.append("items.json 有一条缺 id")
			continue
		if items.has(id):
			errors.append("物品 id 重复：%s" % id)
			continue
		items[id] = it
		var tex: Texture2D = load(str(it.get("icon", ""))) as Texture2D
		if tex == null:
			errors.append("图标加载失败：%s -> %s" % [id, it.get("icon", "")])
		else:
			var size: Vector2 = tex.get_size()
			if size.x != size.y:
				warnings.append("图标不是正方形：%s -> %dx%d" % [id, int(size.x), int(size.y)])
			elif int(size.x) % 32 != 0:
				warnings.append("图标边长不是 32 的整数倍，缩到面板上会糊：%s -> %d" % [id, int(size.x)])
		_validate_source(id, it)

	var recipe_data: Dictionary = _read_json(RECIPES_PATH)
	for entry: Variant in (recipe_data.get("recipes", []) as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("recipes.json 有一条不是对象")
			continue
		var r: Dictionary = entry as Dictionary
		var rid: String = str(r.get("id", ""))
		if rid == "":
			errors.append("recipes.json 有一条缺 id")
			continue
		if recipes.has(rid):
			errors.append("配方 id 重复：%s" % rid)
			continue
		recipes[rid] = r
		recipe_order.append(rid)
		_validate_recipe(rid, r)

	if not errors.is_empty():
		for e: String in errors:
			push_error("[ItemDB] %s" % e)
	if not warnings.is_empty():
		for w: String in warnings:
			push_warning("[ItemDB] %s" % w)


## 产地三件套的校验：词表要对、地点要写、集市货必须有价。
func _validate_source(id: String, it: Dictionary) -> void:
	var ob: String = str(it.get("obtain", ""))
	if ob == "":
		warnings.append("没写 obtain（获取方式），这个物品不会出现在任何货架/采集点：%s" % id)
		return
	if not OBTAIN_KINDS.has(ob):
		errors.append("obtain 不认识：%s -> %s（可用：%s）" % [id, ob, ", ".join(OBTAIN_KINDS)])
		return
	if ob == OBTAIN_MARKET and int(it.get("price", 0)) <= 0:
		errors.append("集市售卖品缺价格：%s" % id)
	if ob == OBTAIN_MINE or ob == OBTAIN_GATHER:
		if str(it.get("map", "")) == "":
			warnings.append("产地是 %s 但没写 map：%s" % [ob, id])


func _validate_recipe(rid: String, r: Dictionary) -> void:
	var out_id: String = str(r.get("output", ""))
	if not items.has(out_id):
		errors.append("配方 %s 的产出 %s 不在物品表里" % [rid, out_id])
	elif str((items[out_id] as Dictionary).get("kind", "")) != "wine":
		errors.append("配方 %s 的产出 %s 不是酒" % [rid, out_id])
	var inputs: Array = r.get("inputs", [])
	if inputs.is_empty():
		errors.append("配方 %s 没有材料" % rid)
	for e: Variant in inputs:
		var d: Dictionary = e as Dictionary
		if not items.has(str(d.get("id", ""))):
			errors.append("配方 %s 引用了不存在的材料 %s" % [rid, d.get("id", "")])
		if int(d.get("count", 0)) <= 0:
			errors.append("配方 %s 的材料 %s 数量非正" % [rid, d.get("id", "")])
	if int(r.get("minutes", 0)) <= 0:
		errors.append("配方 %s 的发酵时长非正" % rid)


func _read_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("打不开 %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s 不是合法 JSON 对象" % path)
		return {}
	return parsed as Dictionary


## ---- 查询 ----------------------------------------------------------------

func has(id: String) -> bool:
	return items.has(id)


func item(id: String) -> Dictionary:
	return items.get(id, {}) as Dictionary


func item_name(id: String) -> String:
	return str(item(id).get("name", id))


func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = load(str(item(id).get("icon", ""))) as Texture2D
	return _icons[id] as Texture2D


func price(id: String) -> int:
	return int(item(id).get("price", 0))


func recipe(id: String) -> Dictionary:
	return recipes.get(id, {}) as Dictionary


func recipe_ids() -> Array[String]:
	return recipe_order.duplicate()


## 酒的档位（items.json 可不写，默认 1）。以后分中/高级酒线，界面按这个分段。
func tier_of(id: String) -> int:
	return int(item(id).get("tier", 1))


## 一条配方要几味料。版面按这个值自适应，不写死。
func input_count(recipe_id: String) -> int:
	return (recipe(recipe_id).get("inputs", []) as Array).size()


## 所有配方里最多几味料 —— 给"最多要预留几个料位"之类的自检用。
func max_inputs() -> int:
	var n: int = 0
	for rid: String in recipe_order:
		n = maxi(n, input_count(rid))
	return n


## ── 产地（obtain / map / spot）────────────────────────────────────
## 一件东西"从哪来"是数据，不是代码里的 if：
##   market = 集市买   mine = 矿点采   gather = 野外采   brew = 自己酿   todo = 产地待定
## 各地图上的采集点只要报 (map, spot)，就能问出这里该出什么 ——
## 以后加黑松山脉、月痕河岸，不用往集市里塞货，也不用改任何面板。

## 集市采购：清单里写着「月痕河镇·集市」的原料，便宜的排前面。
func market_item_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in items:
		if str(items[id].get("kind", "")) == "ingredient" and obtain_of(id) == OBTAIN_MARKET:
			out.append(id)
	_sort_by_price(out)
	return out


## 旧名兼容（集市面板早期版本用的）。新代码请用 market_item_ids()。
func shop_item_ids() -> Array[String]:
	return market_item_ids()


## 集市牌子上的地名。取自数据，不写死。
func market_sign() -> String:
	for id: String in market_item_ids():
		var text: String = source_text(id)
		if text != "待定":
			return text
	return ""


## 所有原料（不分产地）。做"全材料一览"或测试备料时用。
func ingredient_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in items:
		if str(items[id].get("kind", "")) == "ingredient":
			out.append(id)
	_sort_by_price(out)
	return out


func obtain_of(id: String) -> String:
	return str(item(id).get("obtain", ""))


func map_of(id: String) -> String:
	return str(item(id).get("map", ""))


func spot_of(id: String) -> String:
	return str(item(id).get("spot", ""))


## 给界面看的一行产地文字。
func source_text(id: String) -> String:
	match obtain_of(id):
		OBTAIN_MARKET, OBTAIN_MINE, OBTAIN_GATHER:
			var m: String = map_of(id)
			var s: String = spot_of(id)
			if m == "":
				return "待定"
			return m if s == "" else "%s·%s" % [m, s]
		OBTAIN_BREW:
			return "自己酿"
		OBTAIN_GIFT:
			return "剧情赠礼"
		_:
			return "待定"


## 某个地点能出哪些原料。未来地图摆采集点时就问这一句。
func ids_at(map_name: String, spot: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in items:
		if str(items[id].get("kind", "")) != "ingredient":
			continue
		if map_of(id) != map_name:
			continue
		if spot != "" and spot_of(id) != spot:
			continue
		out.append(id)
	_sort_by_price(out)
	return out


## 所有采集点（按 map + spot 归组），给"这张图有几个采集点/各出什么"用。
func spots() -> Array[Dictionary]:
	var index: Dictionary = {}
	var order: Array[String] = []
	for id: String in items:
		var ob: String = obtain_of(id)
		if str(items[id].get("kind", "")) != "ingredient":
			continue
		if ob == OBTAIN_MARKET or ob == OBTAIN_BREW or ob == OBTAIN_TODO:
			continue
		var m: String = map_of(id)
		var s: String = spot_of(id)
		var key: String = "%s|%s" % [m, s]
		if not index.has(key):
			index[key] = {"map": m, "spot": s, "obtain": ob, "ids": [] as Array[String]}
			order.append(key)
		(index[key]["ids"] as Array[String]).append(id)
	var out: Array[Dictionary] = []
	for key: String in order:
		out.append(index[key])
	return out


## 产地还没定的（清单里没写），给设计/美术当待办清单。
func todo_item_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in items:
		if str(items[id].get("kind", "")) == "ingredient" and obtain_of(id) == OBTAIN_TODO:
			out.append(id)
	return out


func _sort_by_price(list: Array[String]) -> void:
	list.sort_custom(func(a: String, b: String) -> bool:
		if price(a) == price(b):
			return item_name(a) < item_name(b)
		return price(a) < price(b))
