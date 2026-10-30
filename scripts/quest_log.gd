extends Node
## 任务清单（autoload：QuestLog）—— 只存数据和进度，不画任何 UI。
##
## 注意：**不设 class_name** —— 类名会和 autoload 单例名撞车（"Class QuestLog
## hides an autoload singleton"），全项目统一用单例名 QuestLog 访问。
##
## 为什么是 autoload：任务横跨酒馆 / 外观 / 集市三个场景，玩家买完料要回店里，
## 进度必须像 Inventory 一样常驻，不随场景切换丢掉。
##
## 结构：一个任务 = {id, title, desc, dest, done, steps: [{text, got, need, done}]}。
## 步骤支持计数型（生姜 2/4）与布尔型（和凯瑟琳说上话，need=1）。
##
## dest = 指引系统的目的地，两种写法，**绑节点优先**：
##   {"scene": "res://scenes/village.tscn", "node": "NPCs/Npc_katherine"}
##   {"scene": "res://scenes/village.tscn", "pos": [447, 36]}
## 绑节点的意义：NPC 会游荡、以后挪位置指示不会漂；节点不在了才退回 pos。
##
## UI（追踪小卡 / Q 任务面板 / 罗盘箭头）只读这里的数据 + 监听 changed 信号。

signal changed
## 当前追踪的任务 id 变了（玩家点选 / 任务完成自动取消）。
signal tracked_changed

var _quests: Array[Dictionary] = []
## 当前被玩家设为"追踪"的任务 id（全局唯一，空串=未追踪）。
## 后续任务指引（地图黄色感叹号）就读取这个 + 任务的 dest 字段。
var _tracked_id: String = ""


func reset() -> void:
	_quests.clear()
	_tracked_id = ""
	changed.emit()
	tracked_changed.emit()


func has(id: String) -> bool:
	return not _find(id).is_empty()


func is_complete(id: String) -> bool:
	var q: Dictionary = _find(id)
	return (not q.is_empty()) and bool(q["done"])


## 设置 / 取消"追踪"任务。
##  · 传别的 id → 顶掉旧的，只追这一个；
##  · 传当前已追踪的 id → 视为"再点一次"，取消追踪（切换）；
##  · 传空串 / 不存在的 id → 取消（清空）。
func set_tracked(id: String) -> void:
	var tid: String = id
	if not tid.is_empty() and not has(tid):
		tid = ""            # 不存在的任务不能追踪
	if tid == _tracked_id:
		# 已处于该状态：本来就没追踪 → 啥也不做；
		# 传的是当前正追踪的任务 → 视为"再点一次"取消。
		if not tid.is_empty():
			_tracked_id = ""
			tracked_changed.emit()
		return
	_tracked_id = tid
	tracked_changed.emit()


func tracked_id() -> String:
	return _tracked_id


func tracked_quest() -> Dictionary:
	if _tracked_id.is_empty():
		return {}
	return _find(_tracked_id)


func is_tracked(id: String) -> bool:
	return str(id) == _tracked_id


## 建立任务（已存在则忽略 —— 幂等，重复触发剧情不会刷出重复任务）。
## dest 见文件头：指引系统的目的地，可留空（没有目的地的任务不显示箭头）。
func add(id: String, title: String, desc: String = "", dest: Dictionary = {}) -> void:
	if has(id):
		return
	_quests.append({
		"id": id, "title": title, "desc": desc, "dest": dest.duplicate(true),
		"done": false, "steps": [] as Array[Dictionary],
	})
	changed.emit()


## 任务的目的地（没设过则返回空字典）。
func dest_of(id: String) -> Dictionary:
	return _find(id).get("dest", {}) as Dictionary


## 事后补 / 改目的地（比如剧情推进到下一阶段）。顺便刷一下 UI。
func set_dest(id: String, dest: Dictionary) -> void:
	var q: Dictionary = _find(id)
	if q.is_empty():
		return
	q["dest"] = dest.duplicate(true)
	changed.emit()


func add_step(id: String, text: String, need: int = 1) -> void:
	var q: Dictionary = _find(id)
	if q.is_empty():
		return
	(q["steps"] as Array).append({
		"text": text, "got": 0, "need": maxi(1, need), "done": false,
	})
	changed.emit()


## 计数型进度（got 会被夹到 0..need）。
func set_progress(id: String, step_index: int, got: int) -> void:
	var q: Dictionary = _find(id)
	if q.is_empty():
		return
	var steps: Array = q["steps"]
	if step_index < 0 or step_index >= steps.size():
		return
	var s: Dictionary = steps[step_index]
	var need: int = maxi(1, int(s["need"]))
	var v: int = clampi(got, 0, need)
	if int(s["got"]) == v and bool(s["done"]) == (v >= need):
		return
	s["got"] = v
	s["done"] = v >= need
	_retrack_if_stale()
	changed.emit()


## 布尔型步骤：直接打勾 / 取消。
func set_step_done(id: String, step_index: int, done: bool) -> void:
	var q: Dictionary = _find(id)
	if q.is_empty():
		return
	var steps: Array = q["steps"]
	if step_index < 0 or step_index >= steps.size():
		return
	var s: Dictionary = steps[step_index]
	var v: int = int(s["need"]) if done else 0
	if bool(s["done"]) == done:
		return
	s["got"] = v
	s["done"] = done
	_retrack_if_stale()
	changed.emit()


func complete(id: String) -> void:
	var q: Dictionary = _find(id)
	if q.is_empty() or bool(q["done"]):
		return
	for s: Variant in (q["steps"] as Array):
		var step: Dictionary = s as Dictionary
		step["got"] = int(step["need"])
		step["done"] = true
	q["done"] = true
	_retrack_if_stale()
	changed.emit()


## 追踪自动接力（2026-10-30 用户要求"所有指引与主线顺利串联"）：
## 正被追踪的任务已经没有活儿了（步骤全勾 / 显式完成）→ 自动换到下一个
## 还差活儿的任务，让追踪卡和罗盘箭头跨任务不断线 —— 玩家不用每做完一段
## 都手动重新点一次追踪。幂等：追踪目标还有活儿时一个字都不动。
## 注意不能用 complete 判定 —— 序章/章节任务很多是 set_step_done 逐勾走完的。
func _retrack_if_stale() -> void:
	if _tracked_id.is_empty():
		return
	var cur: Dictionary = _find(_tracked_id)
	if not cur.is_empty() and _has_pending(cur):
		return
	var next_id: String = ""
	for other: Dictionary in _quests:
		if str(other["id"]) == _tracked_id:
			continue
		if _has_pending(other):
			next_id = str(other["id"])
			break
	if next_id != _tracked_id:
		_tracked_id = next_id
		tracked_changed.emit()


func quest(id: String) -> Dictionary:
	return _find(id)


## 全部任务（进行中的在前，已完成的在后）。UI 直接渲染这个。
func all() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	var finished: Array[Dictionary] = []
	for q: Dictionary in _quests:
		if bool(q["done"]):
			finished.append(q)
		else:
			active.append(q)
	active.append_array(finished)
	return active


## 还差活儿的任务 = 任务栏里该显示的那几段（UI 直接渲染这个）。
##
## 规则（用户 2026-10-24 拍板）：**一段 = 一个任务**。整段的步骤全部做完，
## 这一段就不再返回 → UI 自动把它从任务栏里抹掉，后面还差活儿的段依次往上顶。
## 段内已完成的步骤照旧显示 ✓（保留进度感），不在这里滤。
##
## 没有步骤的任务（刚 add、还没来得及 add_step）算"还差活儿"，
## 否则刚建出来就被滤掉、玩家根本看不见。
func pending() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q: Dictionary in _quests:
		if _has_pending(q):
			out.append(q)
	return out


## 单段是否还有未完成的步骤。
static func _has_pending(q: Dictionary) -> bool:
	if bool(q["done"]):
		return false
	var steps: Array = q.get("steps", [])
	for s: Variant in steps:
		if not bool((s as Dictionary)["done"]):
			return true
	return steps.is_empty()


## 这一段做完了没（步骤全勾 / 显式 complete 过）。
## 判据用"步骤有没有未完成"而不是 done 标记 —— 很多任务是逐步
## set_step_done 走完的，压根不会调 complete()。
static func is_finished(q: Dictionary) -> bool:
	return not _has_pending(q)


## 任务栏里**逐步揭示**的展示窗口（用户 2026-10-30 拍板）。
##
## 一次最多露两条：**刚做完的那条**（留着给玩家看一眼战果）+ **正在做的这条**。
## 正在做的这条一完成，就把上上条挤掉，刚做完的留在屏上当"已完成"，
## 第三条补进来 —— 如此往复，直到全部做完（那时屏上只剩最后一条）。
##
## 还没轮到的任务全部藏着：不糊一脸，也不剧透后面要跑的路。
##
## ⚠ 和 pending() 的区别：**pending() 返回所有未完成的段**（追踪卡要的是真实的
## 未完成数量），本函数只是**给任务栏看的窗口**，两者别混用。
func visible() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var idx: int = -1
	for i: int in _quests.size():
		if _has_pending(_quests[i]):
			idx = i
			break
	if idx >= 0:
		if idx > 0:
			out.append(_quests[idx - 1])   # 上一条：刚做完的战果
		out.append(_quests[idx])           # 这一条：正在做
	elif not _quests.is_empty():
		out.append(_quests[_quests.size() - 1])   # 全做完了：留最后一条
	return out


## 当前应该显示在追踪卡上的任务 = 第一个未完成的。
func active() -> Dictionary:
	for q: Dictionary in _quests:
		if not bool(q["done"]):
			return q
	return {}


func quest_count() -> int:
	return _quests.size()


func _find(id: String) -> Dictionary:
	for q: Dictionary in _quests:
		if str(q["id"]) == id:
			return q
	return {}


# ---- 存档 ------------------------------------------------------------------

## 存档快照：任务数组（深拷贝，免得读档后改到存档里那份）+ 当前追踪 id。
func snapshot() -> Dictionary:
	return {"quests": _quests.duplicate(true), "tracked": _tracked_id}


## 读档：整份替换。两个信号都发 —— 追踪卡、任务面板、地图上的指引都靠它们刷新。
func restore(data: Dictionary) -> void:
	_quests.clear()
	var list: Array = data.get("quests", []) as Array
	for entry: Variant in list:
		if entry is Dictionary:
			_quests.append((entry as Dictionary).duplicate(true))
	var tracked: String = str(data.get("tracked", ""))
	_tracked_id = tracked if has(tracked) else ""
	changed.emit()
	tracked_changed.emit()
