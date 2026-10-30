class_name GiveWinePanel
extends UiPanel
## 「交接哪一件？」—— 剧情里"东西从手里过一遍"那一拍的选物窗口。
##
## 三种用法（由 StoryDialogue 按句子的 trade 配置）：
##   · 递酒（默认）：只列 kind=wine、且你身上真有的，选完由调用方扣库存
##   · 卖酒（pay_mode）：同一份酒单，多显示一列售价，标题/提示改成"卖"
##   · 交别的（pick_kind=""）：身上任何东西都能列出来
##
## 选中后发 chosen(item_id)，由调用方（StoryDialogue）负责扣库存、收钱、续播；
## Esc / 直接关闭 = 算了（不交）。
##
## 和 SellPanel 是近亲，但不认识"顾客"这个对象、也不自己扣库存/加钱 ——
## 它只回答"交哪一件"，账由剧情那边结。

signal chosen(item_id: String)

const FRAME: Rect2 = Rect2(140, 68, 360, 248)
const ROW_TOP: int = 52
const ROW_H: int = 30
const VISIBLE_ROWS: int = 5

## 交给谁（标题副行）。由 StoryDialogue 在 add_child 之前写入。
var guest_name: String = "客人"
## 只列这类物品；"" = 身上有什么列什么。
var pick_kind: String = "wine"
## 是不是一笔买卖：真则多显示售价、文案改成"卖"（钱由调用方收）。
var pay_mode: bool = false

var _items: Array[String] = []
var _window: ListWindow = ListWindow.new()
var _indicator: Label = null
var _rows: Array[Node] = []
var _empty: Label = null


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	var title_text: String = "卖给他哪一瓶？" if pay_mode else "交给他哪一件？"
	if pick_kind == "wine" and not pay_mode:
		title_text = "递上哪一瓶？"
	var title: Label = UiStyle.label(title_text, UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(14, 12)
	_frame.add_child(title)

	var sub: Label = UiStyle.label("给 %s" % guest_name, UiStyle.LINEN_DARK)
	sub.position = Vector2(14 + _width(title_text, UiStyle.TITLE_SIZE) + 10, 20)
	_frame.add_child(sub)

	_indicator = UiStyle.label("", UiStyle.METAL_DARK)
	_indicator.position = Vector2(int(FRAME.size.x) - 72, 20)
	_indicator.size = Vector2(58, 14)
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_indicator)

	UiStyle.divider(_frame, 10, 46, int(FRAME.size.x) - 20)

	_empty = UiStyle.label("", UiStyle.METAL_DARK)
	_empty.position = Vector2(16, 110)
	_empty.visible = false
	_frame.add_child(_empty)

	var action: String = "卖出" if pay_mode else "递上"
	var hint: Label = UiStyle.label("[W/S] 选  [E] %s  [Esc] 算了" % action, UiStyle.LINEN_DARK)
	hint.position = Vector2(12, int(FRAME.size.y) - 26)
	_frame.add_child(hint)

	_rebuild()


func _width(text: String, size: int) -> int:
	var f: Font = UiStyle.theme().default_font
	return int(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)


## 身上有、并且符合 pick_kind 的东西（按名字排）。
func _candidates() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.items:
		var k: String = str((ItemDB.items[id] as Dictionary).get("kind", ""))
		if pick_kind != "" and k != pick_kind:
			continue
		if Inventory.count(id) <= 0:
			continue
		out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return ItemDB.item_name(a) < ItemDB.item_name(b))
	return out


## 旧名保留：早期只有"选酒"一种用法，外部偶尔会问到这一句。
func _wine_ids_owned() -> Array[String]:
	return _candidates()


func _rebuild() -> void:
	for n: Node in _rows:
		if is_instance_valid(n):
			_frame.remove_child(n)
			n.queue_free()
	_rows.clear()

	_items = _candidates()
	_window.configure(_items.size(), VISIBLE_ROWS, false)
	_empty.visible = _items.is_empty()
	_empty.text = "你手头没有能交出去的东西"
	if pick_kind == "wine":
		_empty.text = "你手头还没有酒（先去锅边酿一锅）"
	if _indicator != null:
		_indicator.text = _window.indicator()

	for r: int in VISIBLE_ROWS:
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

		var art: TextureRect = UiStyle.icon(ItemDB.icon(id), Vector2i(28, 28))
		art.position = Vector2(14, y + 1)
		_frame.add_child(art)
		_rows.append(art)

		var nm: Label = UiStyle.label(ItemDB.item_name(id), UiStyle.LINEN)
		nm.position = Vector2(50, y + 7)
		_frame.add_child(nm)
		_rows.append(nm)

		# 买卖：右边先报这一瓶能卖多少钱
		if pay_mode:
			var price: Label = UiStyle.label("%d 铜" % ItemDB.price(id), UiStyle.GOLD)
			price.position = Vector2(int(FRAME.size.x) - 158, y + 7)
			price.size = Vector2(56, 14)
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_frame.add_child(price)
			_rows.append(price)

		var have: Label = UiStyle.label("有 %d" % Inventory.count(id), UiStyle.LINEN_DARK)
		have.position = Vector2(int(FRAME.size.x) - 96, y + 7)
		have.size = Vector2(84, 14)
		have.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_frame.add_child(have)
		_rows.append(have)

		if i == _window.index:
			nm.add_theme_color_override("font_color", UiStyle.FIRE_CORE)


func _on_key(keycode: int) -> bool:
	match keycode:
		KEY_W, KEY_UP:
			_move(-1)
			return true
		KEY_S, KEY_DOWN:
			_move(1)
			return true
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			_confirm()
			return true
	return false


func _move(step: int) -> void:
	if _items.is_empty():
		return
	_window.move(step)
	_rebuild()


func _confirm() -> void:
	if _items.is_empty():
		return
	var id: String = _items[_window.index]
	chosen.emit(id)
	close()
