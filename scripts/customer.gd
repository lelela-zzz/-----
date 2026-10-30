class_name Customer
extends Npc
## 上门的顾客：从酒馆内门口走进来 → 沿固定路线绕到吧台前 → 排在队列里等 → 卖完酒原路离开。
##
## 为什么继承 Npc：视觉（4x4 图集、脚底对齐、受光、昼夜环境色）、
## 「玩家靠近才出提示」「最近的人才抢到 E」「对话框/面板挂在 HUD」这些
## 和路人 NPC 完全一样，重写一遍纯属浪费。这里只换两件事：
##   1. 移动 —— 走路人 NPC 的随机游荡，改走一条固定折线；
##   2. 交互 —— 不弹对话，弹「卖酒」面板。
##
## 路线为什么这么绕：吧台前沿那条通道（y≈140）只有一个入口 ——
## 柜台右端 (x=262) 与魔法酿造锅 (x=287) 之间约 24px 的缝，
## 锅的碰撞一直盖到 y=187，所以必须先走到 y≈200 朝西，再从缝里往上钻。
## 硬直线穿过去会从长桌上踩过去，很难看。

signal departed(customer: Customer)

enum State { WALKING, QUEUED, TALKING, SITTING, LEAVING }

const SELL_PANEL: String = "res://scenes/ui/sell_panel.tscn"

## 没有 customer 数据块的角色（"已认识"后新加入的酒客）用这套默认值：
## 够买 1-2 瓶，台词通用。以后要给某个角色精修，在 tools/build_npc_data.py 的
## CUSTOMERS 里加一条即可（数据 > 默认）。
const DEFAULT_PROFILE: Dictionary = {
	"budget": 90,
	"greet": ["……老板，来一杯。", "随便什么，能暖身子的就行。"],
	"bought": ["唔，不错。", "谢了，老板。"],
	"leave": ["我先走了。"],
	"wine_pref": {},
}

## 顾客走路速度：比玩家慢一点，别抢镜。
@export var customer_speed: float = 34.0
## 排队耐心（现实秒）。玩家一直不理他，他就走了 —— 否则三个槽位会被永远占住。
@export var patience: float = 50.0
## 坐下喝一杯的停留时长（现实秒）。0 表示坐下即走（仅验收用）。
@export var drink_duration: float = 30.0

## 酒类偏好：item_id -> 出价倍数（1.0 原价）。**预留接口**，现在数据里是空的。
var wine_pref: Dictionary = {}
## 这一趟最多花多少铜（预留；现在给的额度都够买几瓶）。
var budget: int = 0

var state: int = State.WALKING

var _path: PackedVector2Array = PackedVector2Array()
var _leg: int = 0
var _queue_pos: Vector2 = Vector2.ZERO
var _slot_index: int = -1
var _sold_count: int = 0
var _budget_left: int = 0
var _waited: float = 0.0
var _seated: bool = false
var _seat: Dictionary = {}
## 打烊时被叫走：面板关掉后直接离场，不再回队列。
var _dismissed: bool = false
var _greet: PackedStringArray = PackedStringArray()
var _bought_lines: PackedStringArray = PackedStringArray()
var _leave_lines: PackedStringArray = PackedStringArray()


## 由 CustomerSpawner 在 add_child 之前调用。
func configure_customer(def: Dictionary, path: PackedVector2Array, slot_index: int) -> void:
	npc_id = str(def.get("id", ""))
	display_name = str(def.get("name", ""))
	title = str(def.get("title", ""))
	var cell: Array = def.get("cell", [60, 120])
	cell_size = Vector2i(int(cell[0]), int(cell[1]))
	var foot: Array = def.get("foot", [30, 120])
	foot_in_cell = Vector2(float(foot[0]), float(foot[1]))
	sprite_scale = float(def.get("scale", 0.5))
	var loaded: Texture2D = load(str(def.get("sheet", ""))) as Texture2D
	if loaded != null:
		sheet = loaded

	var c: Dictionary = def.get("customer", {})
	if c.is_empty():
		c = DEFAULT_PROFILE   # 没有专属顾客数据的角色（后加入的酒客）用默认档案
	wine_pref = (c.get("wine_pref", {}) as Dictionary).duplicate()
	budget = int(c.get("budget", 0))
	_budget_left = budget
	_greet = PackedStringArray(c.get("greet", []))
	_bought_lines = PackedStringArray(c.get("bought", []))
	_leave_lines = PackedStringArray(c.get("leave", []))

	_path = path
	_leg = 0
	_slot_index = slot_index
	_queue_pos = path[path.size() - 1]
	position = path[0]
	facing = "up"


func _ready() -> void:
	super()
	state = State.WALKING
	_anim.update_anim(Vector2i.UP, true)


# ---- 提示 ---------------------------------------------------------------
# 只在"站定排队"时才给 [E]：还在路上的人不该被半路拦住交易。

func _build_prompt() -> void:
	_prompt = UiStyle.outlined_label("[E] 卖酒")
	_prompt.size = Vector2(180, 16)
	_prompt.position = Vector2(-90, -foot_in_cell.y * sprite_scale - 22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.z_index = 200
	_prompt.visible = false
	add_child(_prompt)


## 是否正站在吧台前等卖酒。
## 「最近的人抢 E」仲裁要用（Npc 基类里通过 has_method 鸭子判定，
## 避免 Npc → Customer 的反向引用造成 class_name 循环依赖）。
func wants_service() -> bool:
	return state == State.QUEUED


func _update_prompt() -> void:
	if _prompt == null:
		return
	if SideStory != null:
		# 有未播支线时提示"交谈"，否则照旧"卖酒"
		_prompt.text = "[E] 交谈" if SideStory.has_pending(npc_id) else "[E] 卖酒"
	_prompt.visible = (not _talking) and state == State.QUEUED \
			and _player != null and _in_range() and _is_nearest()


# ---- 行走 ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match state:
		State.TALKING:
			_face_player()
			return
		State.QUEUED:
			# 正在播支线时冻结耐心，别让顾客说到一半就走人
			if not _talking:
				_waited += delta
				if _waited >= patience:
					_begin_leave()
			_idle_at_counter()
		State.WALKING, State.LEAVING:
			_walk(delta)
		State.SITTING:
			if _seated:
				_waited += delta
				if _waited >= drink_duration:
					_begin_leave()
			else:
				_walk(delta)
	_update_prompt()


func _walk(delta: float) -> void:
	while _leg < _path.size():
		var to: Vector2 = _path[_leg] - position
		if to.length() > 1.0:
			var step: Vector2 = to.normalized() * customer_speed * delta
			if step.length() >= to.length():
				position = _path[_leg]
			else:
				position += step
				_dir = _dir_toward(to)
				_anim.update_anim(_dir, true)
				return
		_leg += 1

	# 走完了
	if state == State.WALKING:
		position = _queue_pos
		_arrive()
	elif state == State.LEAVING:
		_finish_leave()
	elif state == State.SITTING:
		_arrive_seat()


func _arrive() -> void:
	state = State.QUEUED
	_dir = Vector2i.UP
	_anim.update_anim(_dir, false)
	_update_prompt()


func _idle_at_counter() -> void:
	if _player != null and _in_range():
		_face_player()
		return
	if _dir != Vector2i.UP:
		_dir = Vector2i.UP
		_anim.update_anim(_dir, false)


func _begin_leave() -> void:
	if state == State.LEAVING:
		return
	# 离场折线必须先算再清座位：座位的入座路径是"退回"的唯一依据
	_path = build_leave_path(position, _seat, _seated, _path, _leg)
	_leg = 0
	state = State.LEAVING
	if not _seat.is_empty():
		SeatRegistry.release(_seat)
	_seat = {}
	_seated = false
	if _prompt != null:
		_prompt.visible = false
	_talking = false


## 离场折线（纯函数，验收脚本直接拿它算几何）。
##
## 为什么不能"从座位斜插到 (320,200)"：座椅点本身就落在长桌的碰撞框里
## （长凳是长桌精灵的一部分），直线出去必然横穿桌面。所以离座只能**沿着入座
## 那条折线反着走回吧台通道**，再从通道口绕到门口。
##
## 三种出发地：
##   · 坐在凳子上（seated）→ 反序 seat["path"]
##   · 正走去座位、半路被叫走   → 沿已经走过的点退回
##   · 站在吧台前              → 反序入场折线（它自己就以门口结尾）
static func build_leave_path(from: Vector2, seat: Dictionary, seated: bool,
		path: PackedVector2Array, leg: int) -> PackedVector2Array:
	var pts: Array[Vector2] = [from]
	if not seat.is_empty():
		if seated:
			for i: int in range((seat.get("path", []) as Array).size() - 1, -1, -1):
				var a: Array = (seat.get("path", []) as Array)[i] as Array
				pts.append(Vector2(float(a[0]), float(a[1])))
		else:
			# 半路被叫走：把已经走过的点倒着走一遍
			for i: int in range(mini(leg, path.size()) - 1, -1, -1):
				pts.append(path[i])
		pts.append_array(_exit_tail())
	else:
		for i: int in range(path.size() - 1, -1, -1):
			pts.append(path[i])

	# 去掉相邻重复点（座位点、队列点都会和起点重合）
	var out: PackedVector2Array = PackedVector2Array()
	for v: Vector2 in pts:
		if out.is_empty() or out[out.size() - 1].distance_to(v) > 1.0:
			out.append(v)
	return out


## 从吧台通道口回门口的那一小段，和入场折线对称（几何常量统一放在 Spawner 里）。
static func _exit_tail() -> PackedVector2Array:
	return PackedVector2Array([
		CustomerSpawner.CORNER_C, CustomerSpawner.CORNER_B,
		CustomerSpawner.CORNER_A, CustomerSpawner.ENTRY,
	])


## 卖完酒 → 去抢一张空座坐下（没座就直接走，不卡）。
func _begin_sit() -> void:
	var seat: Dictionary = SeatRegistry.claim()
	if seat.is_empty():
		_begin_leave()
		return
	state = State.SITTING
	_seated = false
	_seat = seat
	_waited = 0.0
	var path: PackedVector2Array = PackedVector2Array()
	path.append(position)
	for p: Variant in (seat.get("path", []) as Array):
		var arr: Array = p as Array
		path.append(Vector2(float(arr[0]), float(arr[1])))
	_path = path
	_leg = 0
	if _prompt != null:
		_prompt.visible = false
	_talking = false


## 长桌上两排长凳的左右分界（s1/s3 x=137 左侧，s2/s4 x=272 右侧）。
const SEAT_MID_X: float = 201.0


## 落座：坐姿朝向由「椅子在长桌的左/右侧」决定 —— 左椅朝右坐、右椅朝左坐（都面向桌心）。
## 只允许左右，所以坐姿永远取图集第 5 行的侧向两格（col1=左/col2=右），
## 绝不会落到正/背两格（那是 make_sit_row 的占位稿）。
func _arrive_seat() -> void:
	_seated = true
	position = Vector2(float(_seat["x"]), float(_seat["y"]))
	var fdir: Vector2i = _sit_dir_for(_seat)
	_dir = fdir
	_sit_pose(fdir)


## 依椅子侧别给出坐姿朝向：左椅→朝右(1,0)、右椅→朝左(-1,0)。
## 优先读 seat["side"]（"left"/"right"），其次旧的 facing.x，最后按 x 与长桌中心判定。
func _sit_dir_for(seat: Dictionary) -> Vector2i:
	var side: String = str(seat.get("side", ""))
	if side == "left":
		return Vector2i.RIGHT
	if side == "right":
		return Vector2i.LEFT
	var fdata: Array = seat.get("facing", []) as Array
	if fdata.size() >= 2:
		var fx: int = int(fdata[0])
		if fx > 0:
			return Vector2i.RIGHT
		if fx < 0:
			return Vector2i.LEFT
	return Vector2i.RIGHT if float(seat.get("x", 0.0)) < SEAT_MID_X else Vector2i.LEFT


## 落座姿态：只取侧面两格（col1=左、col2=右）。坐姿行第 0/3 格是占位稿，永不使用。
func _sit_pose(dir: Vector2i) -> void:
	var col: int = 1 if dir.x < 0 else 2
	if _anim != null and _anim.has_method("play_pose"):
		_anim.play_pose(4, col, dir)


func _finish_leave() -> void:
	departed.emit(self)
	queue_free()


# ---- 交易 ---------------------------------------------------------------

## 这一位收不收这种东西。现在只收 kind=wine；以后要按口味挑，改这里。
func accepts(item_id: String) -> bool:
	return str(ItemDB.item(item_id).get("kind", "")) == "wine"


## 出价倍数（**预留接口**：现在 wine_pref 为空，恒为 1.0）。
func pref_multiplier(item_id: String) -> float:
	return float(wine_pref.get(item_id, 1.0))


## 这位顾客愿意为这瓶酒付多少铜。
func price_for(item_id: String) -> int:
	var base: int = ItemDB.price(item_id)
	return int(round(float(base) * pref_multiplier(item_id)))


## 好感档位，给反应台词/表情用（love / like / neutral / dislike）。
func reaction_for(item_id: String) -> String:
	var m: float = pref_multiplier(item_id)
	if m >= 1.4:
		return "love"
	if m > 1.05:
		return "like"
	if m < 0.75:
		return "dislike"
	return "neutral"


func can_afford(price: int) -> bool:
	return budget <= 0 or price <= _budget_left


## 卖 1 瓶：扣库存、加钱、记账。返回实收铜币（0 = 没卖成）。
func sell(item_id: String) -> int:
	if not accepts(item_id):
		return 0
	var price: int = price_for(item_id)
	if not can_afford(price):
		return 0
	if not Inventory.remove(item_id, 1):
		return 0
	Inventory.earn(price)
	_budget_left -= price
	_sold_count += 1
	# 打烊结算要报"售出 N 瓶"，只记本次营业的账（Revenue.session_wines /
	# session_wines_by_id，后者按酒种拆分，账簿据此分列）
	if Revenue != null:
		Revenue.note_wine_sold(item_id, 1)
	return price


func sold_count() -> int:
	return _sold_count


## 当前占的座位（没坐就是空字典）—— 跨场景快照要用。
func seat() -> Dictionary:
	return _seat


# ---- 跨场景快照 -----------------------------------------------------------
# 场景一切换，world.tscn 整个销毁，店里的人跟着没。下地窖再上来不该看见空店，
# 所以离场时把"谁、站哪个槽、什么状态、等多久了、买了几瓶"存成纯数据，
# 回来再照着摆回去。存在 CustomerSpawner 的 static 里，见那边的 _save_snapshot。

func snapshot(slot: int) -> Dictionary:
	return {
		"id": npc_id,
		"slot": slot,
		"state": state,
		"sold": _sold_count,
		"budget_left": _budget_left,
		"waited": _waited,
		"seat_id": str(_seat.get("id", "")),
	}


## 照快照恢复。返回 false = 这位不该回来（座位没了 / 状态不该留）。
## 注意：调用时本节点已经 add_child（_ready 跑过、动画器可用）。
func restore(snap: Dictionary, seat: Dictionary) -> bool:
	var st: int = int(snap.get("state", State.QUEUED))
	_sold_count = int(snap.get("sold", 0))
	_budget_left = int(snap.get("budget_left", budget))
	_waited = float(snap.get("waited", 0.0))

	if st == State.SITTING:
		if seat.is_empty():
			return false          # 凳子被别人坐了 —— 别硬挤，让他走
		_seat = seat
		_seated = true
		state = State.SITTING
		position = Vector2(float(seat.get("x", 0.0)), float(seat.get("y", 0.0)))
		_dir = _sit_dir_for(seat)
		_sit_pose(_dir)
		return true

	# WALKING / TALKING / QUEUED 一律按"已经站到吧台前"处理：
	# 卖酒面板随旧场景一起没了，没必要让他从门口再走一遍。
	state = State.QUEUED
	position = _queue_pos
	_leg = _path.size()
	_dir = Vector2i.UP
	_anim.update_anim(_dir, false)
	_update_prompt()
	return true


func greet_lines() -> PackedStringArray:
	return _greet


func bought_line() -> String:
	if _bought_lines.is_empty():
		return ""
	return _bought_lines[randi() % _bought_lines.size()]


func leave_line() -> String:
	if _leave_lines.is_empty():
		return ""
	return _leave_lines[randi() % _leave_lines.size()]


# ---- 交互：换成卖酒面板 --------------------------------------------------

func _open_dialogue() -> void:
	if _talking or state != State.QUEUED:
		return
	# 序章之后：有未播支线就先播剧情（播完仍留在队列里，可继续卖酒）
	if SideStory != null and SideStory.try_play(npc_id, self):
		return
	var layer: Node = _ui_layer()
	if layer == null:
		push_error("Customer %s：找不到 HUD 层" % npc_id)
		return
	var scene: PackedScene = load(SELL_PANEL) as PackedScene
	if scene == null:
		push_error("Customer：加载不了 %s" % SELL_PANEL)
		return
	var panel: UiPanel = scene.instantiate() as UiPanel
	panel.set("customer", self)
	panel.set("customer_name", display_name)
	layer.add_child(panel)
	_talking = true
	state = State.TALKING
	_waited = 0.0
	if _prompt != null:
		_prompt.visible = false
	_anim.update_anim(_dir, false)
	panel.closed.connect(_on_panel_closed)


## 打烊散场：正常走出去（保留走路动画，不凭空消失）。
## 正在卖酒的那位不打断 —— 面板关掉时由 _on_panel_closed 接手。
func dismiss() -> void:
	_dismissed = true
	if state == State.TALKING or state == State.LEAVING:
		return
	_begin_leave()


func _on_panel_closed() -> void:
	_talking = false
	if _dismissed:
		_begin_leave()
		return
	if _sold_count > 0:
		_begin_sit()
	else:
		state = State.QUEUED
		_anim.update_anim(Vector2i.UP, false)
		_update_prompt()
