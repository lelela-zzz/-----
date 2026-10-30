extends Node
## 营业额统计（autoload：Revenue）。
##
## 酒馆卖酒时 Inventory.earn(price) 会推高铜币；这里监听 copper_changed，
## 只把"正向增量"累加进营业额（花钱买料是负向，不计入）。
##
## 四个口径，别混用：
##   total         —— 累计营业额（历史全部，含本次营业）← **剧情解锁判据（雪山委托）**
##   total_wines_by_id —— 累计按酒种卖出的瓶数（wine_id -> 瓶），账簿"销售"列用此
##   session_total —— 本次营业进账（open_business → close_business 之间）
##   best_session  —— 历史单次营业最高进账（仅作"单次最高"展示，不再用于解锁）
##
## 为什么解锁用累计 total 而非"单次营业最高"：营业额（turnover）在经营类游戏里
## 本就是累计口径——"从开店到现在一共做了多少生意"。玩家自定开张时段后，单次制
## 反而会把"只开一小时"的玩家挡在门外（150 铜≈第一晚库存上限的 83%，开 3 小时
## 晚市才够），而累计制让"慢慢做起来"的玩家自然达标，更贴"小本经营滚雪球"的体感。

signal revenue_changed(total: float)

## 雪山后勤解锁门槛（铜）：累计营业额 ≥ 150。
## 150 ≈ 第一晚库存上限（约 12 瓶 / 180 铜）的 83%；累计制下，开张当晚认真卖一晚
## 基本就能摸到，是"小本经营做起来"的温柔门槛，而非硬卡。定档依据见
## 《炉火镇-营业时段-玩家控制-v2.md》§6（数值不变，仅判据从"单次"改为"累计"）。
## 第一章（雪山后勤）解锁门槛。2026-10-30 用户拍板 150 → 300：
## 光靠营业额会让玩家"还没跟人混熟就进剧情"，所以同时加了"认识名单"条件
## （见 Regulars.CHAPTER_REQUIRED），两个条件都满足才开章。
var REVENUE_THRESHOLD_SNOW: float = 300.0

var total: float = 0.0
## 本次营业（一次 open→close）的进账。
var session_total: float = 0.0
## 历史单次营业最高进账。
var best_session: float = 0.0
## 本次营业卖出的瓶数（打烊结算要报）。
var session_wines: int = 0
## 本次营业按酒种拆分的卖出瓶数（wine_id -> 瓶数）。
var session_wines_by_id: Dictionary = {}
## 累计按酒种卖出的瓶数（wine_id -> 瓶）—— 账簿"销售"列用此（累计，不清零）。
## 新增一种酒只要 data/items.json 里 kind=="wine" 即可，这里零改动。
var total_wines_by_id: Dictionary = {}

var _prev_copper: int = 0


func _ready() -> void:
	_prev_copper = Inventory.copper
	Inventory.copper_changed.connect(_on_copper)


func _on_copper(value: int) -> void:
	var delta: float = float(value - _prev_copper)
	_prev_copper = value
	if delta <= 0.0:
		return
	total += delta
	session_total += delta
	# 实时刷新最高单次：不放到 end_session 里做，是因为门槛判定发生在
	# "钱进账的那一刻"，而不是打烊那一刻（玩家可能在营业中就达标）。
	best_session = maxf(best_session, session_total)
	revenue_changed.emit(total)


## 开张时清零本次口径（不动 total / best_session）。
func begin_session() -> void:
	session_total = 0.0
	session_wines = 0
	session_wines_by_id.clear()


## 记一瓶卖出（Customer.sell 调）：wine_id 是卖出的酒种，count 是瓶数。
## 同时累加总量（打烊结算的"售出 N 瓶"）和分酒种账（账簿分列）。
func note_wine_sold(wine_id: String, count: int = 1) -> void:
	var n: int = maxi(count, 0)
	session_wines += n
	session_wines_by_id[wine_id] = int(session_wines_by_id.get(wine_id, 0)) + n
	# 累计分酒种账（不清零，供账簿"销售"列与累计营业额对账）
	total_wines_by_id[wine_id] = int(total_wines_by_id.get(wine_id, 0)) + n


## 打烊：收口本次口径，回一份结算报告，然后把 session 清零（best_session 留着）。
func end_session() -> Dictionary:
	best_session = maxf(best_session, session_total)
	var report: Dictionary = {
		"revenue": session_total,
		"wines": session_wines,
		"wines_by_id": session_wines_by_id.duplicate(),
	}
	session_total = 0.0
	session_wines = 0
	session_wines_by_id.clear()
	return report


# ---- 存档 ------------------------------------------------------------------

## 存档快照：只存"历史累计"三件套。本次营业的 session_* 不存 ——
## 读档进来这一刻没人在营业中，强行恢复半截 session 只会让打烊结算报错数。
func snapshot() -> Dictionary:
	return {
		"total": total,
		"best_session": best_session,
		"total_wines_by_id": total_wines_by_id.duplicate(),
	}


func restore(data: Dictionary) -> void:
	total = float(data.get("total", 0.0))
	best_session = float(data.get("best_session", 0.0))
	total_wines_by_id.clear()
	var wines: Dictionary = data.get("total_wines_by_id", {}) as Dictionary
	for key: Variant in wines:
		total_wines_by_id[str(key)] = int(wines[key])
	begin_session()
	# 关键：把基准价对齐到读档后的铜币，否则下一次进账会把"读档前的差额"
	# 也算成营业额（库存那边是整份替换，铜币可能比快照前更大或更小）。
	_prev_copper = Inventory.copper
	revenue_changed.emit(total)
