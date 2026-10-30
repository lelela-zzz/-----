extends Node
## 酿造服务（autoload：BrewingService）—— 三个槽位的状态机 + 计时。
##
## 为什么是 autoload：锅摆在酒馆，但玩家会跑出去买料、去村里逛、以后还要
## 换到别的房间。发酵中的锅不该因为换场景就回到没投料的状态，所以状态放在
## 全局，跟 Inventory 一样跨场景常驻。
##
## 计时接 GameClock 的**分钟**，不是 Timer：
##   · Timer 在暂停/跳时/读档时行为不一致，而游戏时间是有权威源的；
##   · 换算只有一条：分钟 = 现实秒 × 60 / seconds_per_hour
##     （默认 30 现实秒 = 1 游戏小时 → 15 现实秒 = 30 游戏分钟）。
##   · 时钟通过 "game_clock" 组自动发现，场景切换后会自动重新认领新的那个，
##     所以三个场景里哪个在跑，锅就跟着哪个走。
##
## 初级酒不设失败分支：能开锅就一定出酒，投料即扣、出酒即入库存。

signal slots_changed

const SLOT_COUNT: int = 3

enum State { EMPTY, FERMENTING, READY }

## 每个槽：{state, recipe, output, output_count, remaining, total}
var slots: Array[Dictionary] = []

var _clock: GameClock = null


func _ready() -> void:
	reset()


func reset() -> void:
	slots.clear()
	for i in SLOT_COUNT:
		slots.append(_empty())
	slots_changed.emit()


func _empty() -> Dictionary:
	return {
		"state": State.EMPTY, "recipe": "", "output": "",
		"output_count": 0, "remaining": 0.0, "total": 0.0,
	}


func _process(delta: float) -> void:
	var clock: GameClock = _active_clock()
	if clock == null or not clock.running or clock.seconds_per_hour <= 0.0:
		return
	advance(delta * 60.0 / clock.seconds_per_hour)


## 推进 [param minutes] 游戏分钟。手动推时间（睡觉、快进）和测试直接调这个。
func advance(minutes: float) -> void:
	if minutes <= 0.0:
		return
	var finished: bool = false
	for i in slots.size():
		var slot: Dictionary = slots[i]
		if int(slot["state"]) != State.FERMENTING:
			continue
		slot["remaining"] = maxf(0.0, float(slot["remaining"]) - minutes)
		if float(slot["remaining"]) <= 0.0:
			slot["state"] = State.READY
			finished = true
	if finished:
		slots_changed.emit()


## 第一个空槽，没有则 -1。
func first_empty() -> int:
	for i in slots.size():
		if int(slots[i]["state"]) == State.EMPTY:
			return i
	return -1


## 材料是否够这一锅。
func has_inputs(recipe_id: String) -> bool:
	var r: Dictionary = ItemDB.recipe(recipe_id)
	if r.is_empty():
		return false
	for e: Variant in (r["inputs"] as Array):
		var d: Dictionary = e as Dictionary
		if not Inventory.has(str(d["id"]), int(d["count"])):
			return false
	return true


func can_start(recipe_id: String) -> bool:
	return first_empty() >= 0 and has_inputs(recipe_id)


## 开一锅。成功返回槽位下标，失败返回 -1（没空槽 / 材料不够 / 配方不存在）。
func start(recipe_id: String) -> int:
	var r: Dictionary = ItemDB.recipe(recipe_id)
	if r.is_empty():
		return -1
	var idx: int = first_empty()
	if idx < 0:
		return -1
	if not has_inputs(recipe_id):
		return -1
	for e: Variant in (r["inputs"] as Array):
		var d: Dictionary = e as Dictionary
		Inventory.remove(str(d["id"]), int(d["count"]))

	var slot: Dictionary = slots[idx]
	slot["state"] = State.FERMENTING
	slot["recipe"] = recipe_id
	slot["output"] = str(r["output"])
	slot["output_count"] = int(r.get("yield", 1))
	slot["total"] = float(r["minutes"])
	slot["remaining"] = float(r["minutes"])
	slots_changed.emit()
	return idx


## 收酒入库存，返回产出的物品 id（失败返回空串）。
func collect(index: int) -> String:
	if index < 0 or index >= slots.size():
		return ""
	var slot: Dictionary = slots[index]
	if int(slot["state"]) != State.READY:
		return ""
	var out_id: String = str(slot["output"])
	if out_id != "":
		Inventory.add(out_id, maxi(1, int(slot["output_count"])))
	slots[index] = _empty()
	slots_changed.emit()
	return out_id


## 0..1，空槽恒为 0。
func progress(index: int) -> float:
	if index < 0 or index >= slots.size():
		return 0.0
	var slot: Dictionary = slots[index]
	if int(slot["state"]) == State.EMPTY:
		return 0.0
	var total: float = float(slot["total"])
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - float(slot["remaining"]) / total, 0.0, 1.0)


func ready_count() -> int:
	var n: int = 0
	for slot: Dictionary in slots:
		if int(slot["state"]) == State.READY:
			n += 1
	return n


## 现实秒 / 游戏分钟（默认 30 现实秒 = 1 游戏小时 → 0.5）。
## UI 只显示现实秒 —— 玩家真正在等的是秒，钟面走多少是他们顺带看到的结果。
func real_seconds_per_game_minute() -> float:
	var clock: GameClock = _active_clock()
	if clock == null or clock.seconds_per_hour <= 0.0:
		return 0.5
	return clock.seconds_per_hour / 60.0


## 某个槽还剩多少现实秒。
func remaining_seconds(index: int) -> float:
	if index < 0 or index >= slots.size():
		return 0.0
	return float(slots[index]["remaining"]) * real_seconds_per_game_minute()


## 一条配方总共要等多少现实秒（给列表显示）。
func recipe_seconds(recipe_id: String) -> float:
	var r: Dictionary = ItemDB.recipe(recipe_id)
	return float(r.get("minutes", 0)) * real_seconds_per_game_minute()


func _active_clock() -> GameClock:
	if _clock != null and is_instance_valid(_clock) and _clock.is_inside_tree():
		return _clock
	_clock = get_tree().get_first_node_in_group("game_clock") as GameClock
	return _clock
