extends Node
## 酒馆座位注册表（autoload）：顾客买完酒来占位坐下。
##
## 座位数据来自 data/seats.json：[{id, x, y, facing:[x,y], path:[[x,y],...]}]
##   · x/y     = 落座时角色脚底坐标（也用作 y_sort 排序键）
##   · facing  = 落座朝向（朝向吧台/桌子，默认朝上）
##   · path    = 从吧台到座位的途经点（已避开吧台），落座时角色会把自己的当前位置接在最前面
##
## 顾客落座 claim() 一张空座，离场时 release()。没有空座时顾客直接走（不卡）。

const DATA_PATH: String = "res://data/seats.json"

var _seats: Array[Dictionary] = []
var _occupied: Dictionary = {}   # id -> true


func _ready() -> void:
	_load()


func _load() -> void:
	_seats.clear()
	_occupied.clear()
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("[SeatRegistry] 打不开 %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("[SeatRegistry] %s 不是数组" % DATA_PATH)
		return
	for e: Variant in (parsed as Array):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_seats.append(e as Dictionary)


## 抢一张空座；没有了返回空字典。
func claim() -> Dictionary:
	for s: Dictionary in _seats:
		var id: String = str(s.get("id", ""))
		if not _occupied.get(id, false):
			_occupied[id] = true
			return s
	return {}


## 离场时释放座位。
func release(seat: Dictionary) -> void:
	if seat.is_empty():
		return
	_occupied[str(seat.get("id", ""))] = false


## 按 id 抢指定座位（跨场景恢复用：让坐回原来那张凳子，别凭空换桌）。
## 座位不存在或被占了就返回空字典。
func claim_by_id(id: String) -> Dictionary:
	if id == "":
		return {}
	for s: Dictionary in _seats:
		if str(s.get("id", "")) != id:
			continue
		if _occupied.get(id, false):
			return {}
		_occupied[id] = true
		return s
	return {}


## 调试/验收用：当前被占的座位数。
func occupied_count() -> int:
	var n: int = 0
	for id: String in _occupied:
		if _occupied[id]:
			n += 1
	return n
