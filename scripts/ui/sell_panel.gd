class_name SellPanel
extends UiPanel
## 卖酒面板：吧台前对着某位顾客按 E 打开，把自己手上的酒卖给他。
##
## 和集市面板（ShopPanel）是镜像关系：那边"铜币换原料"，这边"酒换铜币"。
## 三点刻意做成可替换的：
##  · 收不收由 **顾客** 说了算（Customer.accepts），面板不写死"只收酒"；
##  · 出价由 **顾客** 算（Customer.price_for），面板只负责显示和调用；
##  · 所以以后加"某人只喝烈酒""某人出价高 40%"，只改 data/npcs.json 的
##    customer.wine_pref，这里一行都不用动。
##
## **一人一天只买一瓶**（2026-10-30）：卖出一瓶后这单就结束了 —— 面板把买后台词
## 留在屏上片刻，然后自动收摊，顾客自己去落座（Customer._on_panel_closed）。
## 真正的判定在 Customer.sell(limit) 里，这里只负责友好提示和收摊节奏。

const FRAME: Rect2 = Rect2(88, 60, 464, 272)
const ROW_TOP: int = 74
const ROW_H: int = 32
## 一屏能放几行。酒的种类多起来就滚动，不靠加高面板硬塞。
const VISIBLE_ROWS: int = 5

var customer: Customer = null
var customer_name: String = ""

var _items: Array[String] = []
var _window: ListWindow = ListWindow.new()
var _indicator: Label = null
var _rows: Array[Node] = []
var _message: Label = null
var _message_frames: int = 0
## 卖出后自动收摊的倒计时（帧）。0 = 不倒计时。
var _close_in: int = 0
var _empty: Label = null
var _money: Label = null


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	_header()
	_list_area()
	UiStyle.divider(_frame, 8, 240, int(FRAME.size.x) - 16)

	var hint: Label = UiStyle.label("[W/S] 选  [E] 卖 1 瓶  [Esc] 结束", UiStyle.LINEN_DARK)
	hint.position = Vector2(10, 246)
	_frame.add_child(hint)

	_message = UiStyle.label("", UiStyle.FIRE)
	_message.position = Vector2(210, 246)
	_message.size = Vector2(244, 14)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_message)

	_rebuild()


func _header() -> void:
	var title: Label = UiStyle.label(customer_name, UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(14, 10)
	_frame.add_child(title)

	var role: String = ""
	if customer != null:
		role = customer.title
	var sub: Label = UiStyle.label(role, UiStyle.LINEN_DARK)
	sub.position = Vector2(14 + _width(customer_name, UiStyle.TITLE_SIZE) + 10, 18)
	_frame.add_child(sub)

	_money = UiStyle.label("铜 0", UiStyle.GOLD)
	_money.position = Vector2(340, 16)
	_money.size = Vector2(110, 16)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_money)
	Inventory.copper_changed.connect(_on_copper_changed)
	_on_copper_changed(Inventory.copper)

	_indicator = UiStyle.label("", UiStyle.METAL_DARK)
	_indicator.position = Vector2(14, 34)
	_frame.add_child(_indicator)

	UiStyle.divider(_frame, 8, 44, int(FRAME.size.x) - 16)

	# 顾客的开场话：让"这一位想喝什么"能先被看见（偏好数据接上以后就有区别了）
	var greet: String = ""
	if customer != null:
		var lines: PackedStringArray = customer.greet_lines()
		if lines.size() > 0:
			greet = lines[0]
	if greet != "":
		var g: Label = UiStyle.label(greet, UiStyle.LINEN_DARK)
		g.position = Vector2(14, 52)
		g.size = Vector2(int(FRAME.size.x) - 28, 16)
		_frame.add_child(g)


func _list_area() -> void:
	_empty = UiStyle.label("你手上还没有酒（先去锅边酿一锅）", UiStyle.METAL_DARK)
	_empty.position = Vector2(16, 120)
	_empty.visible = false
	_frame.add_child(_empty)


func _width(text: String, size: int) -> int:
	var f: Font = UiStyle.theme().default_font
	return int(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)


# ---- 列表 ---------------------------------------------------------------

func _wines_owned() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.items:
		if customer != null and not customer.accepts(id):
			continue
		if Inventory.count(id) <= 0:
			continue
		out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = customer.price_for(a) if customer != null else ItemDB.price(a)
		var pb: int = customer.price_for(b) if customer != null else ItemDB.price(b)
		return pa > pb)
	return out


func _rebuild() -> void:
	for n: Node in _rows:
		if is_instance_valid(n):
			_frame.remove_child(n)
			n.queue_free()
	_rows.clear()

	_items = _wines_owned()
	_window.configure(_items.size(), VISIBLE_ROWS, false)
	_empty.visible = _items.is_empty()
	if _indicator != null:
		_indicator.text = _window.indicator()

	for r in VISIBLE_ROWS:
		var i: int = _window.first() + r
		if i >= _items.size():
			continue
		var id: String = _items[i]
		var y: int = ROW_TOP + r * ROW_H

		var bg: ColorRect = UiStyle.rect(UiStyle.BROWN)
		bg.position = Vector2(10, y)
		bg.size = Vector2(int(FRAME.size.x) - 20, ROW_H - 2)
		bg.visible = i == _window.index
		_frame.add_child(bg)
		_rows.append(bg)

		var accent: ColorRect = UiStyle.rect(UiStyle.FIRE)
		accent.position = Vector2(10, y)
		accent.size = Vector2(2, ROW_H - 2)
		accent.visible = i == _window.index
		_frame.add_child(accent)
		_rows.append(accent)

		var art: TextureRect = UiStyle.icon(ItemDB.icon(id), Vector2i(32, 32))
		art.position = Vector2(12, y)
		_frame.add_child(art)
		_rows.append(art)

		var nm: Label = UiStyle.label(ItemDB.item_name(id), UiStyle.LINEN)
		nm.position = Vector2(48, y + 9)
		_frame.add_child(nm)
		_rows.append(nm)

		var have: Label = UiStyle.label("有 %d" % Inventory.count(id), UiStyle.LINEN_DARK)
		have.position = Vector2(150, y + 9)
		_frame.add_child(have)
		_rows.append(have)

		var price: int = customer.price_for(id) if customer != null else ItemDB.price(id)
		var tag: String = ""
		if customer != null and customer.pref_multiplier(id) > 1.05:
			tag = "  ★"
		var pf: Label = UiStyle.label("%d 铜%s" % [price, tag], UiStyle.GOLD)
		pf.position = Vector2(int(FRAME.size.x) - 110, y + 9)
		pf.size = Vector2(96, 14)
		pf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_frame.add_child(pf)
		_rows.append(pf)

		if i == _window.index:
			nm.add_theme_color_override("font_color", UiStyle.FIRE_CORE)


func _process(_delta: float) -> void:
	if _message_frames > 0:
		_message_frames -= 1
		if _message_frames == 0:
			_message.text = ""
	# 这单成了：让"买后台词"被读到，然后自己收摊（顾客去落座，不用再按 Esc）
	if _close_in > 0:
		_close_in -= 1
		if _close_in == 0:
			close()


func _on_copper_changed(value: int) -> void:
	if _money != null:
		_money.text = "铜 %d" % value


# ---- 按键 ---------------------------------------------------------------

func _on_key(keycode: int) -> bool:
	match keycode:
		KEY_W, KEY_UP:
			_move(-1)
			return true
		KEY_S, KEY_DOWN:
			_move(1)
			return true
		KEY_E:
			_sell()
			return true
	return false


func _move(step: int) -> void:
	if _items.is_empty():
		return
	_window.move(step)
	_rebuild()


func _sell() -> void:
	if customer == null:
		return
	# 一人一天只买一瓶：已经买过的这位不再接第二单（正常流程走不到 ——
	# 卖出后面板会自动收摊；这里是保险，比如剧情递酒先收过他一瓶）
	if customer.sold_count() > 0:
		_say("他今天一瓶就满足了", UiStyle.METAL_DARK)
		return
	if _items.is_empty():
		_say("他没什么想买的", UiStyle.METAL_DARK)
		return
	var id: String = _items[_window.index]
	if not customer.can_afford(customer.price_for(id)):
		_say("他手头没那么多铜了", UiStyle.METAL_DARK)
		return
	var gained: int = customer.sell(id)
	if gained <= 0:
		_say("这瓶他不要", UiStyle.METAL_DARK)
		return
	var line: String = customer.bought_line()
	_say(("卖出 %s，+%d 铜" % [ItemDB.item_name(id), gained])
			+ ("  「%s」" % line if line != "" else ""), UiStyle.LINEN)
	_rebuild()
	_close_in = 55   # ≈0.9s：读完买后台词再收摊


func _say(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message_frames = 120
