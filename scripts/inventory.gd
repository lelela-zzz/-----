extends Node
## 玩家库存 + 铜币（autoload：Inventory）。
##
## 放在 autoload 而不是场景里，是因为要跨三个场景（酒馆 / 外观 / 村庄）保留 ——
## 和 DoorArea 的伪静态变量不同，这是真的常驻，传送不会丢。
##
## 只做加减和查询，不判断"能不能买"、"能不能酿" —— 那些属于业务层
## （ShopPanel / BrewingService）。这样库存永远不会因为业务改动而变复杂。

signal changed
signal copper_changed(value: int)

## 开局给的钱。够买十来锅料，先让人把循环跑通；后面接经济系统再调。
const START_COPPER: int = 60

var copper: int = START_COPPER

var _counts: Dictionary = {}


func count(id: String) -> int:
	return int(_counts.get(id, 0))


func has(id: String, amount: int = 1) -> bool:
	return count(id) >= amount


func add(id: String, amount: int = 1) -> void:
	if id == "" or amount <= 0:
		return
	_counts[id] = count(id) + amount
	changed.emit()


## 扣到不够就整笔不扣，返回 false。调用方不必先查再扣。
func remove(id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if count(id) < amount:
		return false
	_counts[id] = count(id) - amount
	if int(_counts[id]) == 0:
		_counts.erase(id)
	changed.emit()
	return true


func spend(amount: int) -> bool:
	if amount < 0 or copper < amount:
		return false
	copper -= amount
	copper_changed.emit(copper)
	return true


func earn(amount: int) -> void:
	if amount <= 0:
		return
	copper += amount
	copper_changed.emit(copper)


func all() -> Dictionary:
	return _counts.duplicate()


func clear() -> void:
	_counts.clear()
	changed.emit()


# ---- 存档 ------------------------------------------------------------------

## 存档快照：铜币 + 全部物品计数。
func snapshot() -> Dictionary:
	return {"copper": copper, "items": _counts.duplicate()}


## 读档：整份替换，不做增量（增量在"两边都动过"时必然对不平）。
## 两个信号都发，HUD / 营业额 / 任务进度才会跟着重算。
func restore(data: Dictionary) -> void:
	copper = int(data.get("copper", START_COPPER))
	_counts.clear()
	var items: Dictionary = data.get("items", {}) as Dictionary
	for key: Variant in items:
		var n: int = int(items[key])
		if n > 0:
			_counts[str(key)] = n
	changed.emit()
	copper_changed.emit(copper)
