class_name LedgerPanel
extends UiPanel
## 账簿（R）：一张经营台账，按酒种一行一列地摊开。
##
##   累计营业额  —— 从开店到现在卖酒进账的总和（铜），即 Revenue.total
##   酒种表格    —— 每种酒一行：左边"销售"= 累计卖出的瓶数（Revenue.total_wines_by_id），
##                右边"剩余"= 酒窖里现存的瓶数
##
## 为什么这么摆：顶栏累计营业额 必须等于 各酒种「销售×单价」之和 —— 所以"销售"
## 取累计口径，和顶栏对齐（否则顶栏是累计、表格是当日，两者加不起来）。表格完全按
## data/items.json 里 kind=="wine" 动态生成 —— 以后加一种酒，这里零改动就多一行。
##
## 只读视图，不改任何状态；数值每帧刷新（营业时卖出在涨、补货在变，看得到）。

const FRAME: Rect2 = Rect2(36, 28, 568, 328)
const NAME_X: int = 40        # 酒种名列起始 x
const SALE_X: int = 210       # 销售列数值右对齐 x
const STOCK_X: int = 330      # 剩余列数值右对齐 x
const VAL_W: int = 110        # 数值列宽（右对齐用）
const INCOME_Y: int = 60
const HEAD_Y: int = 92
const ROW_Y0: int = 114
const ROW_H: int = 20
const MAX_ROWS: int = 9       # 单列最多显示的行，超出折叠成"还有 N 种"

var _revenue_lbl: Label = null
var _name_labels: Array[Label] = []
var _sale_labels: Array[Label] = []
var _stock_labels: Array[Label] = []
var _more_label: Label = null
var _built_count: int = -1     # 酒种数变了才重建行网格，平时只刷文字


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	var title: Label = UiStyle.label("账簿", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(14, 12)
	_frame.add_child(title)

	var sub: Label = UiStyle.label("银辉酒馆 · 第 %d 天" % _day(), UiStyle.LINEN_DARK)
	sub.position = Vector2(14 + _width("账簿", UiStyle.TITLE_SIZE) + 10, 20)
	_frame.add_child(sub)

	UiStyle.divider(_frame, 10, 46, int(FRAME.size.x) - 20)

	var hint: Label = UiStyle.label("[Esc] 关闭", UiStyle.LINEN_DARK)
	hint.position = Vector2(12, int(FRAME.size.y) - 24)
	_frame.add_child(hint)

	# 累计营业额（单行置顶）
	var inc_lbl: Label = UiStyle.label("累计营业额", UiStyle.LINEN)
	inc_lbl.position = Vector2(NAME_X, INCOME_Y)
	_frame.add_child(inc_lbl)
	_revenue_lbl = UiStyle.label("0 铜", UiStyle.GOLD)
	_revenue_lbl.position = Vector2(SALE_X, INCOME_Y)
	_revenue_lbl.size = Vector2(VAL_W, 14)
	_revenue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_revenue_lbl)

	# 表头
	var h_name: Label = UiStyle.label("酒种", UiStyle.METAL_DARK)
	h_name.position = Vector2(NAME_X, HEAD_Y)
	_frame.add_child(h_name)
	var h_sale: Label = UiStyle.label("销售", UiStyle.METAL_DARK)
	h_sale.position = Vector2(SALE_X, HEAD_Y)
	h_sale.size = Vector2(VAL_W, 14)
	h_sale.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(h_sale)
	var h_stock: Label = UiStyle.label("剩余", UiStyle.METAL_DARK)
	h_stock.position = Vector2(STOCK_X, HEAD_Y)
	h_stock.size = Vector2(VAL_W, 14)
	h_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(h_stock)

	_refresh()


## 所有酒种 id（按 data/items.json 书写顺序），kind=="wine" 才算。
func _wine_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.items:
		if str(ItemDB.item(id).get("kind", "")) == "wine":
			out.append(id)
	return out


## 酒种数变了（理论上只在改 JSON 时发生）才重建行网格，否则每帧只刷文字。
func _ensure_rows(ids: Array[String]) -> void:
	if ids.size() == _built_count:
		return
	for l: Label in _name_labels + _sale_labels + _stock_labels:
		if is_instance_valid(l):
			_frame.remove_child(l)
			l.queue_free()
	_name_labels.clear()
	_sale_labels.clear()
	_stock_labels.clear()
	var shown: int = mini(ids.size(), MAX_ROWS)
	for i: int in shown:
		var y: int = ROW_Y0 + i * ROW_H
		var n: Label = UiStyle.label("", UiStyle.LINEN)
		n.position = Vector2(NAME_X, y)
		_frame.add_child(n)
		_name_labels.append(n)
		var s: Label = UiStyle.label("", UiStyle.LINEN)
		s.position = Vector2(SALE_X, y)
		s.size = Vector2(VAL_W, 14)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_frame.add_child(s)
		_sale_labels.append(s)
		var k: Label = UiStyle.label("", UiStyle.LINEN)
		k.position = Vector2(STOCK_X, y)
		k.size = Vector2(VAL_W, 14)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_frame.add_child(k)
		_stock_labels.append(k)
	_built_count = ids.size()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _revenue_lbl == null:
		return
	var ids: Array[String] = _wine_ids()
	_ensure_rows(ids)
	_revenue_lbl.text = "%d 铜" % int(round(Revenue.total))

	var shown: int = mini(ids.size(), MAX_ROWS)
	for i: int in shown:
		var id: String = ids[i]
		_name_labels[i].text = ItemDB.item_name(id)
		_sale_labels[i].text = "×%d" % int(Revenue.total_wines_by_id.get(id, 0))
		_stock_labels[i].text = "×%d" % Inventory.count(id)

	if ids.size() > MAX_ROWS:
		var more: String = "（还有 %d 种）" % (ids.size() - MAX_ROWS)
		if _more_label == null:
			_more_label = UiStyle.label(more, UiStyle.METAL_DARK)
			_more_label.position = Vector2(NAME_X, ROW_Y0 + MAX_ROWS * ROW_H)
			_frame.add_child(_more_label)
		else:
			_more_label.text = more
	elif _more_label != null and is_instance_valid(_more_label):
		_frame.remove_child(_more_label)
		_more_label.queue_free()
		_more_label = null


func _day() -> int:
	var c: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	return c.day if c != null else 1


func _width(text: String, size: int) -> int:
	var f: Font = UiStyle.theme().default_font
	return int(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
