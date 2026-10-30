class_name ShopPanel
extends UiPanel
## 集市采购面板：村里摊位前按 E 打开，两列五行的原料货架。
##
## 只做一件事：把铜币换成原料。价格与货源全部来自 data/items.json 的
## shop / price / source 三个字段 —— 以后想加货、调价、断货，改 JSON 就行。
##
## ── 货变多以后怎么办 ────────────────────────────────────────────
## 货架固定 10 格（2 列 × 5 行），但货单可以无限长：ListWindow 负责"这 10 格里
## 该摆哪 10 样"，翻到下一段时整格重新绑数据，节点数始终是 10。
## 排列改成**行优先**（i/2 是行、i%2 是列），这样 A/D 是左右挪一格、W/S 是
## 上下一行，跟眼睛看到的方阵一致；窗口按 2 对齐，永远不会翻出"半行"。
## ──────────────────────────────────────────────────────────────

const FRAME: Rect2 = Rect2(70, 66, 500, 252)
const COLS: int = 2
const VISIBLE_ROWS: int = 5
const VISIBLE: int = COLS * VISIBLE_ROWS
const CELL_W: int = 240
const CELL_H: int = 32
const CELL_TOP: int = 52
const CELL_STEP: int = 34
const COL_X: Array[int] = [8, 252]

var _items: Array[String] = []
var _window: ListWindow = ListWindow.new()
var _cells: Array[Dictionary] = []
var _money: Label = null
var _range: Label = null
var _message: Label = null
var _message_frames: int = 0


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)
	_items = ItemDB.market_item_ids()

	_header()
	for slot in VISIBLE:
		_cell_slot(slot)

	UiStyle.divider(_frame, 8, 226, int(FRAME.size.x) - 16)
	var hint: Label = UiStyle.label("[W/S] 选  [A/D] 换列  [E] 买1  [R] 买5  [Esc] 关闭", UiStyle.LINEN_DARK)
	hint.position = Vector2(10, 230)
	_frame.add_child(hint)
	_message = UiStyle.label("", UiStyle.FIRE)
	_message.position = Vector2(300, 230)
	_message.size = Vector2(190, 14)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_message)

	_window.configure(_items.size(), VISIBLE, false, COLS)
	_refresh()


func _header() -> void:
	var title: Label = UiStyle.label("集市", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(14, 10)
	_frame.add_child(title)

	# 牌子上的地名从数据里取：哪天集市搬到别处，这里跟着变
	var sign_text: String = ItemDB.market_sign()
	var sub: Label = UiStyle.label(("散装原料 · " + sign_text) if sign_text != "" else "散装原料 · 论份卖",
			UiStyle.LINEN_DARK)
	sub.position = Vector2(70, 22)
	_frame.add_child(sub)

	_range = UiStyle.label("", UiStyle.METAL_DARK)
	_range.position = Vector2(268, 22)
	_frame.add_child(_range)

	_money = UiStyle.label("铜 0", UiStyle.GOLD)
	_money.position = Vector2(372, 16)
	_money.size = Vector2(112, 16)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_money)
	Inventory.copper_changed.connect(_on_copper_changed)
	_on_copper_changed(Inventory.copper)

	UiStyle.divider(_frame, 8, 44, int(FRAME.size.x) - 16)


## 建第 slot 个格子（0..9）。位置按行优先算死，之后只换内容不换位置。
func _cell_slot(slot: int) -> void:
	var col: int = slot % COLS
	var row: int = floori(float(slot) / float(COLS))
	var x: int = COL_X[clampi(col, 0, COL_X.size() - 1)]
	var y: int = CELL_TOP + row * CELL_STEP

	var bg: ColorRect = UiStyle.rect(UiStyle.BROWN)
	bg.position = Vector2(x, y)
	bg.size = Vector2(CELL_W, CELL_H)
	bg.visible = false
	_frame.add_child(bg)

	var accent: ColorRect = UiStyle.rect(UiStyle.FIRE)
	accent.position = Vector2(x, y)
	accent.size = Vector2(2, CELL_H)
	accent.visible = false
	_frame.add_child(accent)

	var art: TextureRect = UiStyle.icon(load("res://assets/items/icons/barley.png") as Texture2D, Vector2i(32, 32))
	art.position = Vector2(x + 4, y)
	art.visible = false
	_frame.add_child(art)

	var name_label: Label = UiStyle.label("", UiStyle.LINEN)
	name_label.position = Vector2(x + 42, y + 2)
	name_label.visible = false
	_frame.add_child(name_label)

	var price: Label = UiStyle.label("", UiStyle.GOLD)
	price.position = Vector2(x + 42, y + 17)
	price.visible = false
	_frame.add_child(price)

	var owned: Label = UiStyle.label("", UiStyle.LINEN_DARK)
	owned.position = Vector2(x + 150, y + 17)
	owned.size = Vector2(80, 14)
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	owned.visible = false
	_frame.add_child(owned)

	_cells.append({"bg": bg, "accent": accent, "art": art, "name": name_label,
			"price": price, "owned": owned, "id": ""})


func _process(_delta: float) -> void:
	if _message_frames > 0:
		_message_frames -= 1
		if _message_frames == 0:
			_message.text = ""
	_refresh()


func _refresh() -> void:
	if _range != null:
		_range.text = _window.range_text()

	for slot in VISIBLE:
		var ui: Dictionary = _cells[slot]
		var i: int = _window.first() + slot
		if i >= _items.size():
			_hide_cell(ui)
			continue

		var id: String = _items[i]
		if str(ui["id"]) != id:
			ui["id"] = id
			(ui["art"] as TextureRect).texture = ItemDB.icon(id)
			(ui["name"] as Label).text = ItemDB.item_name(id)
			(ui["price"] as Label).text = "%d 铜" % ItemDB.price(id)
		for key: String in ["art", "name", "price", "owned"]:
			(ui[key] as Control).visible = true

		var selected: bool = i == _window.index
		(ui["bg"] as ColorRect).visible = selected
		(ui["accent"] as ColorRect).visible = selected

		var affordable: bool = Inventory.copper >= ItemDB.price(id)
		if affordable:
			(ui["price"] as Label).add_theme_color_override("font_color", UiStyle.GOLD)
			(ui["name"] as Label).add_theme_color_override("font_color",
					UiStyle.FIRE_CORE if selected else UiStyle.LINEN)
		else:
			(ui["price"] as Label).add_theme_color_override("font_color", UiStyle.METAL_DARK)
			(ui["name"] as Label).add_theme_color_override("font_color", UiStyle.METAL_DARK)
		var have: int = Inventory.count(id)
		(ui["owned"] as Label).text = ("有 %d" % have) if have > 0 else ""


func _hide_cell(ui: Dictionary) -> void:
	(ui["bg"] as ColorRect).visible = false
	(ui["accent"] as ColorRect).visible = false
	for key: String in ["art", "name", "price", "owned"]:
		(ui[key] as Control).visible = false
	ui["id"] = ""


func _on_copper_changed(value: int) -> void:
	if _money != null:
		_money.text = "铜 %d" % value


func _on_key(keycode: int) -> bool:
	if _items.is_empty():
		return false
	match keycode:
		KEY_W, KEY_UP:
			_window.move(-COLS)
			return true
		KEY_S, KEY_DOWN:
			_window.move(COLS)
			return true
		KEY_A, KEY_LEFT:
			_window.move(-1)
			return true
		KEY_D:
			_window.move(1)
			return true
		KEY_E:
			_buy(1)
			return true
		KEY_R:
			_buy(5)
			return true
	return false


## 一次买 [param amount] 份，钱不够几份就买几份，一分都不够才报错。
## 序章首单是"姜4/莓6/麦6/草4"，R 连按两下就把一份材料凑满，不用点到 20 下。
func _buy(amount: int) -> void:
	var id: String = _items[_window.index]
	var cost: int = ItemDB.price(id)
	var n: int = mini(amount, Inventory.copper / cost)
	if n <= 0:
		_say("铜不够了", UiStyle.FIRE)
		return
	if not Inventory.spend(cost * n):
		_say("铜不够了", UiStyle.FIRE)
		return
	Inventory.add(id, n)
	_say("买了 %d 份%s" % [n, ItemDB.item_name(id)], UiStyle.LINEN)


func _say(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message_frames = 100
