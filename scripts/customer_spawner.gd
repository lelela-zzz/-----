class_name CustomerSpawner
extends Node2D
## 酒馆的顾客流：玩家在店里的时候，隔一阵随机来一位，走到吧台前排队。
##
## 谁算"顾客"：**已认识**（玩家真对过话，见 autoload Regulars）+ 设定上允许当酒客
## 的角色。数据层面不再要求必须带 customer 块 —— 带块的用专属预算/台词，没带的用
## Customer.DEFAULT_PROFILE（统一默认）。开局只有预置的 4 位首发常客算已认识；
## 之后玩家每搭话一位，他/她就可能作为酒客再次上门（从门口走进来，见 spawn）。
##
## 路线（为什么是折线，见 customer.gd 的注释）：
##   内门口 (320,300) → (320,200) → (283,200) → (283,150) → (槽位x,150) → (槽位x,140)
## 槽位沿吧台前沿一字排开，先来的站左边，后来的往右让。

## 测试用总闸：场景实例化之前把它置 true，整个顾客层就不工作。
static var force_disable: bool = false

## 开场 rush **每天**放一次（换场景重建本节点会清零实例变量，static 兜住）。
## 以前是"一局一次"，营业时段交给玩家后改成"每天一次"：
## 同一天关掉招牌再开，不该又涌进一拨人；第二天才该有开门热闹。
static var _rush_day: int = -1

## 跨场景快照：离开酒馆（下楼进地窖）时把店里的人和状态存这儿，回来照原样摆回去。
## 场景一切换 world.tscn 整个销毁，顾客节点跟着没 —— 不做这件事的话，
## 玩家下地窖看一眼锅再上来，店里就空了。
static var _snap_customers: Array[Dictionary] = []
static var _snap_day: int = -1
static var _snap_ticks: int = 0

## 哪些场景算"还在酒馆建筑里头"。去这些地方时店不散场；
## 去别处（集市/村子）则当玩家真的走远了，店里重新来客。
## 地窖 2026-10-28 起并在 world.tscn 里（同一张图的上半层），不再是独立场景。
const TAVERN_INTERIOR: Array[String] = [
	"res://scenes/tavern_exterior.tscn",  # 门口街上：还在自家屋檐下
	"res://scenes/world.tscn",            # 店里，含楼上的地窖
]

## 离店多久之后就不再恢复（现实秒）。下地窖看锅通常十几二十秒，
## 留 2 分钟余量；再久就当他们等不及走了，回来重新来客。
const RESTORE_MAX_AWAY: float = 120.0

const CUSTOMER_SCENE: String = "res://scenes/customer.tscn"
const DATA_PATH: String = "res://data/npcs.json"

## 时段客流倍率（按游戏小时）。这是"什么时候开张"的唯一差异来源：
##   07:30–11 早市 0.4（进货时段，几乎没人）｜11–14 午市 0.9
##   14–18 下午 1.1｜18–21 晚市 1.4（峰值）｜21–22 收尾 0.9｜22 点后关张
## 倍率直接乘在补位间隔的倒数上（间隔 / f），不改任何既有参数。
const TRAFFIC: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	0.0, 0.4, 0.4, 0.4, 0.4,
	0.9, 0.9, 0.9,
	1.1, 1.1, 1.1, 1.1,
	1.4, 1.4, 1.4,
	0.9, 0.0, 0.0,
]


## 门口内侧：顾客从这里出现（也是离开时的终点）。
const ENTRY: Vector2 = Vector2(320, 300)
## 折线拐点：绕过酿造锅、从柜台与锅之间的缝钻进吧台通道。
const CORNER_A: Vector2 = Vector2(320, 200)
const CORNER_B: Vector2 = Vector2(283, 200)
const CORNER_C: Vector2 = Vector2(283, 150)
## 通道横走的高度（y=140 是脚底，柜台前沿在 132）。
const AISLE_Y: float = 150.0
const QUEUE_Y: float = 140.0
## 吧台前五个位置（柜台可视范围 x≈92..262）。
const SLOTS: Array[float] = [110.0, 145.0, 180.0, 215.0, 245.0]

@export var enabled: bool = true
## 同时在店里最多几位。槽位有 5 个，但**上限只给 3** ——
## 4 位并排站在吧台前会连成一堵人墙（间距才 35px、角色宽 30px），
## 开张后店里本来还有老板娘和支线访客，加起来就太挤了。
@export var max_customers: int = 3
## 开门后多久来第一位（现实秒）。（开场 rush 放完之后，常规补位从这里起算。）
@export var first_delay: float = 6.0
## 之后每位之间的间隔区间（现实秒）。放宽是为了让店里偶尔真的空下来。
@export var min_interval: float = 20.0
@export var max_interval: float = 34.0
## 开门瞬间涌进的一拨人（"开场 rush"），错峰入场不像瞬移。其余仍按原随机节奏零星补位。
@export var opening_rush_count: int = 2
## rush 内每位之间的间隔（现实秒），让门口排着进。
@export var opening_rush_gap: float = 1.0
## 摆到哪个父节点下（y_sort 容器）。
@export var npc_parent_path: NodePath = ^"../Sorted"
## 关掉"自动来客"（开场 rush + 常规补位）。顾客层的其余功能（快照恢复、
## 卖酒、座位）照常，只是不自己往店里加人 —— 验收脚本全靠它把在场人员
## 交给用例手动摆，否则跑着跑着就多出一位。
@export var auto_spawn: bool = true

var errors: Array[String] = []

## 显式顾客（带 customer 块）—— defs() 只返回这些，保持旧语义（验收已钉死 4 条）。
var _defs: Dictionary = {}
## 全部 NPC 定义（已认识角色当顾客时要拿它的图集/名字来 configure）。
var _all_defs: Dictionary = {}
## 可能成为酒客的全部 id（有图集 + 非老板娘/终章 Boss），是否来客再看 is_known。
var _candidates: Array[String] = []
var _occupancy: Dictionary = {}
## 当天买过酒的人：id -> 他们买酒那天的 GameClock.day。
## 规则：买过酒的人当天不会再来买酒。spawn_random 据此跳过，
## 跨天（day 变化）后凭"天对不上"自动恢复资格，无需显式清零。
## static：下地窖再上来不该把"今天买过"的记录洗掉（否则同一个人一天能买好几轮）。
static var _purchased_day: Dictionary = {}
## 今天"已经来过店里"的人：id -> 到店那天。用于营业框的"预计客流 N · 已来 M"。
## 与 _purchased_day 分开：买过酒的人当天不再来（_purchased_day）；这里只记"来过"，
## 不管买没买，好让玩家知道今日还能等来几个新面孔。
static var _arrived_day: Dictionary = {}
var _timer: float = 0.0
## _ready 里上膛（数据合法且没被总闸掐掉）。
var _armed: bool = false
## 闸门放行后才开始计时；手动 spawn()（验收用）不受它管。
var _running: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 开场 rush 剩余名额（开门瞬间一次性放完）。
var _rush_remaining: int = 0
## rush 内每位之间的倒计时。
var _rush_timer: float = 0.0


func _ready() -> void:
	_load()
	if force_disable or not enabled:
		return
	_rng.randomize()
	_timer = first_delay
	_armed = true
	# 延后一帧：Sorted 容器是兄弟节点，等场景搭完再往里塞人
	_restore_snapshot.call_deferred()


func _exit_tree() -> void:
	# 场景要没了：把店里的人存成纯数据（下地窖再上来要照原样摆回去）
	_save_snapshot()


# ---- 跨场景快照 -----------------------------------------------------------

## 离开酒馆的那一刻存盘。只在"去酒馆内部的另一个房间"时保留 ——
## 去集市/村子说明玩家真的走远了，店里散场，回来重新来客。
##
## 注意：**离场这段时间不计耐心**。玩家下楼看锅、在门口转一圈，回来时顾客
## 该还站在吧台前，而不是"时间照走、人全走了"。真要散场由 RESTORE_MAX_AWAY
## 兜（离开太久就不恢复了）。
func _save_snapshot() -> void:
	_snap_customers.clear()
	if force_disable or not _armed:
		return
	if not TAVERN_INTERIOR.has(DoorArea.pending_target):
		return
	for slot: int in _occupancy.keys():
		var c: Customer = _occupancy[slot] as Customer
		if not is_instance_valid(c) or c.state == Customer.State.LEAVING:
			continue
		_snap_customers.append(c.snapshot(int(slot)))
		# 座位是 autoload 上的状态，不还回去就永远被占着（旧顾客已经没了）
		if c.state == Customer.State.SITTING:
			SeatRegistry.release(c.seat())
	_snap_day = _current_day()
	_snap_ticks = Time.get_ticks_msec()


## 回到酒馆的那一帧还原。快照是一次性的：用掉就清。
func _restore_snapshot() -> void:
	if force_disable or not _armed or _snap_customers.is_empty():
		return
	var saved: Array[Dictionary] = _snap_customers.duplicate()
	_snap_customers.clear()
	# 跨了天、或者离开太久 → 当他们等不及走了，不恢复
	if _snap_day != _current_day():
		return
	var away: float = float(Time.get_ticks_msec() - _snap_ticks) / 1000.0
	if away > RESTORE_MAX_AWAY:
		return
	for snap: Dictionary in saved:
		var id: String = str(snap.get("id", ""))
		var slot: int = int(snap.get("slot", -1))
		if id == "" or slot < 0 or slot >= SLOTS.size():
			continue
		if not _all_defs.has(id) or _occupancy.has(slot):
			continue
		var seat: Dictionary = SeatRegistry.claim_by_id(str(snap.get("seat_id", "")))
		var c: Customer = _spawn_in_slot(id, slot)
		if c == null:
			SeatRegistry.release(seat)
			continue
		if not c.restore(snap, seat):
			_occupancy.erase(slot)
			SeatRegistry.release(seat)
			c.queue_free()


## 测试/重开用：把跨场景状态全部清零。
static func reset_session() -> void:
	_snap_customers.clear()
	_snap_day = -1
	_snap_ticks = 0
	_purchased_day.clear()
	_arrived_day.clear()
	_rush_day = -1


## 存档快照：当天的两本账（谁今天买过 / 谁今天来过）。
## 这两个字典本来就是 static（跨场景活），但进程一结束就没了 ——
## 不存的话，读档进来"今天已经买过酒"的判定会重置，同一个人一天能被卖两次。
static func snapshot() -> Dictionary:
	return {
		"purchased_day": _purchased_day.duplicate(),
		"arrived_day": _arrived_day.duplicate(),
		"rush_day": _rush_day,
	}


static func restore(data: Dictionary) -> void:
	_purchased_day.clear()
	var purchased: Dictionary = data.get("purchased_day", {}) as Dictionary
	for key: Variant in purchased:
		_purchased_day[str(key)] = int(purchased[key])
	_arrived_day.clear()
	var arrived: Dictionary = data.get("arrived_day", {}) as Dictionary
	for key: Variant in arrived:
		_arrived_day[str(key)] = int(arrived[key])
	_rush_day = int(data.get("rush_day", -1))


func _load() -> void:
	_defs.clear()
	_all_defs.clear()
	_candidates.clear()
	errors.clear()
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		errors.append("打不开 %s" % DATA_PATH)
		push_error("[CustomerSpawner] %s" % errors[-1])
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s 不是合法 JSON" % DATA_PATH)
		push_error("[CustomerSpawner] %s" % errors[-1])
		return
	for entry: Variant in ((parsed as Dictionary).get("npcs", []) as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry as Dictionary
		var id: String = str(d.get("id", ""))
		if id == "":
			errors.append("有一位缺 id")
			continue
		_all_defs[id] = d
		var has_sheet: bool = ResourceLoader.exists(str(d.get("sheet", "")))
		# 显式顾客（带 customer 块）：沿用旧校验（图集必须存在），进 _defs。
		if d.has("customer"):
			if not has_sheet:
				errors.append("%s 的图集不存在" % id)
				continue
			_defs[id] = d
		# 候选池：有图集、且设定上可以当酒客（排除老板娘/终章 Boss）。
		if has_sheet and Regulars != null and Regulars.allows_customer(id):
			_candidates.append(id)
	if _defs.is_empty():
		errors.append("npcs.json 里没有任何带 customer 块的角色")
	if not errors.is_empty():
		for e: String in errors:
			push_error("[CustomerSpawner] %s" % e)


func _process(delta: float) -> void:
	if not _armed or not auto_spawn:
		return
	# 闸门每帧复查：招牌挂着才营业。玩家按 T 打烊、22:00 系统强制关张、
	# 离开酒馆自动打烊 —— 三条路最后都落到 Story.tavern_open() 变 false。
	# （以前 _running 一旦置 true 就再也不复检，招牌机制接上就会漏客。）
	if not Story.tavern_open():
		_running = false
		return
	if not _running:
		_running = true
		if _rush_day == _current_day():
			# 今天已经放过开场客（关掉招牌又开）：直接进常规节奏，不重播
			_rush_remaining = 0
			_timer = first_delay
		else:
			# 开门瞬间涌进一拨人（错峰入场，不像瞬移）。
			_rush_day = _current_day()
			_rush_remaining = mini(opening_rush_count, max_customers)
			_rush_timer = 0.0   # 立刻放第一人
		return
	if _rush_remaining > 0:
		_refill_rush(delta)
		return
	if active_count() >= max_customers:
		return
	var f: float = traffic_factor()
	if f <= 0.0:
		return      # 深夜不接客（也不消耗补位计时的余额）
	_timer -= delta
	if _timer <= 0.0:
		_timer = _rng.randf_range(min_interval, max_interval) / f
		spawn_random()


## 当前时段的客流倍率（0 = 不接客）。
func traffic_factor() -> float:
	var c: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if c == null:
		return 1.0
	return TRAFFIC[clampi(c.hour, 0, 23)]


## 打烊：让在场客人自己走出去（不凭空消失）。
## 正在卖酒的那位不打断 —— 他会在面板关掉时自己走（Customer._dismissed）。
func dismiss_all() -> void:
	_rush_remaining = 0
	for slot: int in _occupancy.keys():
		var c: Customer = _occupancy[slot] as Customer
		if is_instance_valid(c):
			c.dismiss()



## 开场 rush：按 opening_rush_gap 错峰把剩下的人放进来；放完交还常规节奏。
func _refill_rush(delta: float) -> void:
	if active_count() >= max_customers:
		_rush_remaining = 0
		_timer = first_delay
		return
	_rush_timer -= delta
	if _rush_timer <= 0.0:
		var c: Customer = spawn_random()
		if c != null:
			_rush_remaining -= 1
			_rush_timer = opening_rush_gap
		else:
			# 没人可放（都买过 / 没空槽）→ 提前收尾
			_rush_remaining = 0
		_timer = first_delay   # 无论是否提前结束，常规补位都从首间隔起算


# ---- 生成 ---------------------------------------------------------------

## 今天该以**顾客身份**进店的"剧情访客"：身上还挂着没播的支线、今天能播、且不在店里。
## 未认识也放行 —— 他们本来就是来让玩家认识的，聊完这段支线就进正常 roster 了。
## （「今天能播」由 SideStory.has_pending 里的 min_day / 章节 gate 把关。）
func _story_visitors() -> Array[String]:
	var out: Array[String] = []
	if SideStory == null or not SideStory.active():
		return out
	# 章节剧情进行中不安排：这会儿店里的位置要留给人家的戏，别塞个闲人进来
	if ChapterStory != null and ChapterStory.is_active():
		return out
	# 遍历**全部**角色定义（_all_defs），不是 _candidates —— 俄莉斯已列入
	# NOT_CUSTOMER（不再当普通酒客），但她的支线还得照播（顺序闸：奇斯演完才轮到她）。
	# 没挂支线的人（卡兹、老板娘等）会被 has_pending 天然过滤掉。
	for id: String in _all_defs:
		if not SideStory.has_pending(id):
			continue
		if _present(id) or _in_scene(id):
			continue
		out.append(id)
	return out


## 随机挑一位还没在店里、且今天没买过酒的顾客，站到第一个空槽位。
## （手动 spawn(id) 不受此规则限制——验收脚本要靠它摆人。）
func spawn_random() -> Customer:
	# 上限在这里兜一道：_process / _refill_rush 也会先判，但那是两条路径，
	# 漏一条就是"店里多出一位"。放这里所有调用点都受约束。
	if active_count() >= max_customers:
		return null

	# **剧情访客优先**：谁身上还挂着没播的支线，今天先请他进店坐坐。
	# 走的是和普通客人**完全一样**的入场流程（从门口走进来、坐下、点酒），
	# 玩家按 [E] 交谈时 Customer._open_dialogue 会让 SideStory.try_play 接管播剧情。
	# （2026-10-30 用户要求：以前这些人是被 Story 静态塞在酒馆固定位置的，像个桩子。）
	var visitors: Array[String] = _story_visitors()
	if not visitors.is_empty():
		return spawn(visitors[_rng.randi() % visitors.size()])

	var today: int = _current_day()
	var free: Array[String] = []
	for id: String in _candidates:
		# 只放"已认识"的角色（玩家真对过话）——本改动的核心判定。
		if Regulars == null or not Regulars.is_known(id):
			continue
		if _present(id):
			continue
		# 场里已经有这位（支线访客还没退场 / 常驻 NPC）→ 不重复摆一个同名顾客
		if _in_scene(id):
			continue
		if _purchased_day.get(id, -1) == today:
			continue
		free.append(id)
	if free.is_empty():
		return null
	var pick: String = free[_rng.randi() % free.size()]
	return spawn(pick)


## 当前游戏内"天"。取不到时钟时退化为 1（不会让规则误伤）。
func _current_day() -> int:
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock != null:
		return clock.day
	return 1


## 指定某位顾客（验收/调试用）。返回 null 表示槽位满或 id 不认识。
func spawn(id: String) -> Customer:
	var slot: int = _first_free_slot()
	if slot < 0 or not _all_defs.has(id):
		return null
	return _spawn_in_slot(id, slot)


## 摆到**指定**槽位（恢复快照时要原样站回原来那个位置）。
func _spawn_in_slot(id: String, slot: int) -> Customer:
	if not _all_defs.has(id):
		return null
	var parent: Node = get_node_or_null(npc_parent_path)
	if parent == null:
		push_error("CustomerSpawner：找不到父节点 %s" % npc_parent_path)
		return null
	var scene: PackedScene = load(CUSTOMER_SCENE) as PackedScene
	if scene == null:
		push_error("CustomerSpawner：加载不了 %s" % CUSTOMER_SCENE)
		return null

	var cust: Customer = scene.instantiate() as Customer
	cust.name = "Customer_" + id
	cust.configure_customer(_all_defs[id] as Dictionary, path_for(slot), slot)
	parent.add_child(cust)
	cust.departed.connect(_on_departed)
	_occupancy[slot] = cust
	# 记"今天来过"（跨场景 static；同一天同一位重复生成只是覆盖，不会重复计数）
	_arrived_day[id] = _current_day()
	return cust


## 某槽位的完整折线（含终点）。
func path_for(slot: int) -> PackedVector2Array:
	var x: float = SLOTS[clampi(slot, 0, SLOTS.size() - 1)]
	return PackedVector2Array([
		ENTRY, CORNER_A, CORNER_B, CORNER_C,
		Vector2(x, AISLE_Y), Vector2(x, QUEUE_Y),
	])


func _first_free_slot() -> int:
	for i in SLOTS.size():
		if not _occupancy.has(i) or not is_instance_valid(_occupancy[i]):
			return i
	return -1


func _present(id: String) -> bool:
	for slot: int in _occupancy:
		var c: Customer = _occupancy[slot] as Customer
		if is_instance_valid(c) and c.npc_id == id:
			return true
	return false


func _on_departed(cust: Customer) -> void:
	for slot: int in _occupancy.keys():
		if _occupancy[slot] == cust:
			_occupancy.erase(slot)
			break
	# 当天买过酒 → 记一笔，让他今天不再被随机放进来。
	if is_instance_valid(cust) and cust.sold_count() > 0:
		_purchased_day[cust.npc_id] = _current_day()


# ---- 查询（验收用）------------------------------------------------------

func active_count() -> int:
	var n: int = 0
	for slot: int in _occupancy:
		if is_instance_valid(_occupancy[slot]):
			n += 1
	return n


## 当前"能来买酒"的候选：已认识 + 设定上允许当酒客。
## 开局 = 预置的 4 位首发常客；玩家每搭话一位，这里就多一位。
func roster() -> Array[String]:
	var out: Array[String] = []
	for id: String in _candidates:
		if Regulars != null and Regulars.is_known(id):
			out.append(id)
	return out


## 今日"能来买酒"的最大人数 = 已认识的候选数（每人每天最多来买一次）。
## 营业框用它显示"预计客流"，让玩家判断今天还有没有营业的必要。
func daily_customer_cap() -> int:
	return roster().size()


## 今天已经来过店里的不同人数（不管有没有买）。
func arrived_today() -> int:
	var today: int = _current_day()
	var n: int = 0
	for id: String in _arrived_day:
		if int(_arrived_day[id]) == today:
			n += 1
	return n


## 场景里是否已经有这个角色（支线访客 / 常驻 NPC / 已上门的顾客都算）。
## 防止"人还在店里站着"时又随机摆一个同名顾客出来（比如访客奇斯还没聊完）。
func _in_scene(id: String) -> bool:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() \
				and str(n.get("npc_id")) == id:
			return true
	return false


func defs() -> Dictionary:
	return _defs


func free_slots() -> int:
	var n: int = 0
	for i in SLOTS.size():
		if not _occupancy.has(i) or not is_instance_valid(_occupancy[i]):
			n += 1
	return n
