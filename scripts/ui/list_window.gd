class_name ListWindow
extends RefCounted
## 一个"条目数不确定"的列表可视窗口。
##
## 为什么单独抽：酿造配方、卖酒清单、集市货架三处都会随着内容变多而溢出，
## 三处各写一遍滚动，迟早有一处忘了夹紧。这里只算数，不碰节点：
## 哪个下标的条目该落在窗口的第几行，由它一个人说了算。
##
## 三种用法：
##   · 酿造 / 卖酒（单列）：visible = 可见行数，align = 1
##   · 集市（两列成对）：visible = 可见格数、align = 2，保证一行的左右两格
##     永远来自同一段连续区间，不会翻页翻出"半行"。

## 条目总数
var count: int = 0
## 一屏能放几个（集市按"格"算，不是按行）
var visible: int = 1
## 当前选中下标
var index: int = 0
## 翻到头是回绕（酿造）还是顶住（卖酒/集市）
var wrap: bool = true
## 窗口起点对齐步长。集市 = 2（两列成对）；单列 = 1
var align: int = 1

var _first: int = 0


func configure(total: int, rows: int, do_wrap: bool = true, step_align: int = 1) -> void:
	# 条目数和可见行都没变时保留滚动位置：卖酒面板每卖一瓶都会重建一次，
	# 每次都跳回顶部的话，卖第 6 瓶时列表会突然"刷"一下。
	var same: bool = total == count and rows == visible
	count = maxi(0, total)
	visible = maxi(1, rows)
	wrap = do_wrap
	align = maxi(1, step_align)
	if not same:
		_first = 0
	index = clampi(index, 0, maxi(0, count - 1))
	_ensure_visible()


func set_index(i: int) -> void:
	index = clampi(i, 0, maxi(0, count - 1))
	_ensure_visible()


## 上移/下移若干格。wrap = true 时到边界回绕，否则顶住。
func move(step: int) -> void:
	if count <= 0:
		return
	var next: int = index + step
	index = wrapi(next, 0, count) if wrap else clampi(next, 0, count - 1)
	_ensure_visible()


func first() -> int:
	return _first


func last() -> int:
	return mini(count, _first + visible) - 1


## 这个下标落在窗口第几行；不在窗口里返回 -1。
func slot_of(i: int) -> int:
	var s: int = i - _first
	return s if s >= 0 and s < visible else -1


func is_visible(i: int) -> bool:
	return slot_of(i) >= 0


func has_above() -> bool:
	return _first > 0


func has_below() -> bool:
	return _first + visible < count


func needs_scroll() -> bool:
	return count > visible


## 给界面用的一行状态字：总数不超过一屏就返回空串（不打扰）。
func indicator() -> String:
	if not needs_scroll():
		return ""
	return "%d/%d" % [index + 1, count]


## 多列网格更适合显示"当前看到第几条到第几条"。
func range_text() -> String:
	if not needs_scroll():
		return ""
	return "%d-%d / %d" % [_first + 1, last() + 1, count]


func _ensure_visible() -> void:
	var max_first: int = maxi(0, count - visible)
	max_first = _align_down(max_first)
	# 选中项掉到窗口上面
	if index < _first:
		_first = _align_down(index)
	# 选中项掉到窗口下面
	elif index >= _first + visible:
		_first = _align_up(index - visible + 1)
	_first = clampi(_first, 0, max_first)


func _align_down(v: int) -> int:
	return floori(float(v) / float(align)) * align


func _align_up(v: int) -> int:
	return ceili(float(v) / float(align)) * align
