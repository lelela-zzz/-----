class_name GameClock
extends Node
## 游戏时间源（唯一权威）——只管"现在几点"，不管怎么显示、也不管光照。
##
## 换算：`seconds_per_hour` = 30 现实秒 = 1 游戏小时 → 1 现实秒 = 2 游戏分钟，
## 一个完整昼夜 12 分钟。
##
## 对外只出两个信号：
##   time_changed(hour, minute) —— 显示层（ClockHUD）用，只在分钟变化时发
##   hour_changed(hour)         —— 系统层（光照等）用，只在整点变化时发
## 这样 HUD 不会因为一帧一帧刷而重绘，光照也不会被分钟级信号反复触发。

## 游戏内分钟变化时发出。
signal time_changed(hour: int, minute: int)
## 游戏内整点变化时发出。
signal hour_changed(hour: int)
## 游戏内"天"跨过 00:00 时发出（day 已是新的一天）。
signal day_changed(day: int)

@export_range(0, 23) var start_hour: int = 7
@export_range(0, 59) var start_minute: int = 30
## 宵禁：走到这个整点就当"一天结束"，不再往 23:00 之后走，直接跳第二天起床时间。
## <0 = 不宵禁（退回 00:00 跨天的老行为）。
@export_range(-1, 23) var curfew_hour: int = 23
## 宵禁后的起床时间（次日 07:30 开门备料）。
@export_range(0, 23) var wake_hour: int = 7
@export_range(0, 59) var wake_minute: int = 30
## 现实秒 / 游戏小时。30 = 半小时一小时…（默认 30 秒走 1 小时）
@export var seconds_per_hour: float = 30.0
## 关掉即暂停走时（菜单、对话时用）。
@export var running: bool = true

var hour: int = 0
var minute: int = 0
## 游戏内"天"计数：跨天时 +1（宵禁 23:00 → 次日 07:30；不宵禁则跨过 00:00）。
## 顾客"当天买过酒就不再上门"的账、营业时长、剧情放送节奏都挂在它身上。
##
## ⚠️ 天数**必须跨场景活着**：时钟是每个场景各一个（world / village / mine…），
## 场景一换，实例变量就重建。以前 day 写死初值 1，于是"出门买个料再回来"就把
## 日子退回第一天 —— 顾客那边「今天已经买过」的账（_purchased_day）全都对上了
## 号，四位客人全部被当成"今天买过"，第二天起怎么经营都一个人都不来。
## 现在天数用 static 兜住（`_shared_day`），新时钟起来先把它接过来。
var day: int = 1:
	set(value):
		day = maxi(value, 1)
		_shared_day = day

## 跨场景共享的"今天是第几天"。进程内唯一，换场景不丢。
static var _shared_day: int = 1

var _minute_accum: float = 0.0

## 「睡觉中」过场是否正在演。防重入：过场期间时钟 running=false，
## 但 advance() 仍可能被外部直接调用（跳过时间），别叠第二层遮罩。
var _sleeping: bool = false
## 过场前时钟本来是跑着还是停着 —— 演完照原样还回去。
var _was_running: bool = true


func _ready() -> void:
	# 进组是为了让"不挂在场景里的系统"（如 BrewingService）能自动找到当前时钟，
	# 换场景时旧时钟被释放、新时钟进组，它们重新认领即可。
	add_to_group("game_clock")
	# 接着上一天的日期往下走（别把换场景当成重新开局）
	day = _shared_day
	hour = clampi(start_hour, 0, 23)
	minute = clampi(start_minute, 0, 59)
	time_changed.emit(hour, minute)
	hour_changed.emit(hour)


## 重开一局 / 验收清场用：把日期拨回第 1 天。
static func reset_day(value: int = 1) -> void:
	_shared_day = maxi(value, 1)


func _process(delta: float) -> void:
	if running:
		advance(delta)


## 手动推进 [param real_seconds] 现实秒（测试和"跳过时间"用）。
func advance(real_seconds: float) -> void:
	if seconds_per_hour <= 0.0:
		return
	_minute_accum += real_seconds * (60.0 / seconds_per_hour)
	if _minute_accum < 1.0:
		return

	var prev_hour: int = hour
	while _minute_accum >= 1.0:
		_minute_accum -= 1.0
		minute += 1
		if minute >= 60:
			minute = 0
			hour = (hour + 1) % 24
			if curfew_hour >= 0 and hour == curfew_hour:
				# 宵禁：一天到此为止，直接跳次日清晨。剩余累积时间丢掉 ——
				# advance() 不是"快进 N 天"，长跳也只走一次跨天。
				_roll_over_curfew()
				return
			if hour == 0:   # 不宵禁时的老路径：跨过 00:00（23→00）新的一天
				day += 1
				day_changed.emit(day)
	time_changed.emit(hour, minute)
	if hour != prev_hour:
		hour_changed.emit(hour)


## 宵禁跨天：day+1、时间跳到起床点，然后三个信号都补一遍。
## 顺序要紧：先把 hour/minute 设好再发 day_changed，监听者读到的就是"次日 07:30"。
##
## 有 UI 注入点时先演一段「睡觉中」过场（SleepOverlay），演完才跳时间 ——
## 否则玩家只看到天色突然从夜变晨，不知道中间过了什么。
func _roll_over_curfew() -> void:
	_minute_accum = 0.0
	if _sleeping:
		return
	var layer: Node = UiStyle.ui_layer(self) if SleepOverlay.can_play() else null
	if layer == null:
		# headless / 没有 HUD 的场景：老路径，同步跳（回归用例依赖这份同步）
		_commit_new_day()
		return
	_sleeping = true
	_was_running = running
	running = false                      # 过场期间别让时钟自己偷偷往前走
	var ov: SleepOverlay = SleepOverlay.new()
	layer.add_child(ov)
	ov.finished.connect(_on_sleep_finished)
	ov.play()


func _on_sleep_finished() -> void:
	if not _sleeping:
		return
	_sleeping = false
	_commit_new_day()
	running = _was_running


## 真正把日子翻过去。过场版和瞬跳版共用这一段。
func _commit_new_day() -> void:
	day += 1
	hour = clampi(wake_hour, 0, 23)
	minute = clampi(wake_minute, 0, 59)
	day_changed.emit(day)
	time_changed.emit(hour, minute)
	hour_changed.emit(hour)


## 直接设定时间（读档、调试用）。
func set_time(new_hour: int, new_minute: int) -> void:
	var prev_hour: int = hour
	hour = clampi(new_hour, 0, 23)
	minute = clampi(new_minute, 0, 59)
	_minute_accum = 0.0
	time_changed.emit(hour, minute)
	if hour != prev_hour:
		hour_changed.emit(hour)


func get_time_string() -> String:
	return "%02d:%02d" % [hour, minute]
