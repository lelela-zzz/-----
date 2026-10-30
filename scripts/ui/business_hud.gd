class_name BusinessHud
extends Control
## 右上角常驻的「营业状态条」：一眼看见招牌挂没挂、还剩多久打烊、今天赚了多少、
## 今天预计还能来几位客人。
##
## 为什么要有它：营业时段改成玩家自定之后，"现在能不能开张 / 已经开了多久 /
## 今天进账多少"这三件事全靠 toast 播完就没，玩家得自己记。这里常驻显示，
## 用的是 ClockPanel 下沿的空白（右上角 y 92 起），不挡场景中央。
##
## 只读视图：数据全部来自 Story（状态/时段）与 Revenue（今日进账），
## 自己不存任何业务状态 —— 和 QuestTracker 一个套路。

const WIDTH: int = 192
const HEIGHT: int = 54
const POS: Vector2 = Vector2(640 - WIDTH - 8, 92)

var _plate: Panel = null
var _state: Label = null
var _detail: Label = null
## 第三行：今日预计客流（上限 + 已来），让玩家判断还有没有必要继续营业。
var _crowd: Label = null
var _cached_state: String = ""
var _cached_detail: String = ""
var _cached_crowd: String = ""


func _ready() -> void:
	position = POS
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顶层 HUD 在 CanvasLayer 下没有主题，字体必须显式挂（同 QuestTracker 的坑）
	theme = UiStyle.theme()
	_build()
	_refresh()


func _build() -> void:
	_plate = UiStyle.panel(Color(UiStyle.SHADOW.r, UiStyle.SHADOW.g, UiStyle.SHADOW.b, 0.78),
			UiStyle.BROWN)
	_plate.position = Vector2.ZERO
	_plate.size = Vector2(WIDTH, HEIGHT)
	add_child(_plate)

	_state = UiStyle.label("", UiStyle.LINEN_DARK)
	_state.position = Vector2(8, 4)
	_state.size = Vector2(WIDTH - 16, 14)
	# 像素字一旦超出 Label 就会画到屏幕外（实测 "[T] 挂招牌 · 07:30–18:00" 右端被切），
	# 文案已经压短，这里再兜一道：宁可截断也不出血。
	_state.clip_text = true
	add_child(_state)

	_detail = UiStyle.label("", UiStyle.LINEN_DARK)
	_detail.position = Vector2(8, 19)
	_detail.size = Vector2(WIDTH - 16, 14)
	_detail.clip_text = true
	add_child(_detail)

	_crowd = UiStyle.label("", UiStyle.LINEN_DARK)
	_crowd.position = Vector2(8, 34)
	_crowd.size = Vector2(WIDTH - 16, 14)
	_crowd.clip_text = true
	add_child(_crowd)


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _state == null or _detail == null or _crowd == null:
		return
	var story: StoryDirector = Story
	if story == null:
		return
	# 只在酒馆内部显示：出了门就整个收起来，别把"未开张"顶在集市/村子/雪山上。
	# 状态条是被注入到每个带 HUD 的场景里的，所以这里必须自己判场景。
	var in_tavern: bool = story.in_tavern()
	visible = in_tavern
	if not in_tavern:
		return
	var open: bool = story.business_open
	var line1: String = ""
	var line2: String = ""
	var col: Color = UiStyle.LINEN_DARK

	if open:
		line1 = "营业中 · 剩 %s" % _until_close()
		line2 = "今日 %d 铜 · [T] 收" % int(Revenue.session_total)
		col = UiStyle.FIRE_CORE
		_plate.add_theme_stylebox_override("panel", UiStyle.box(
				Color(UiStyle.SHADOW.r, UiStyle.SHADOW.g, UiStyle.SHADOW.b, 0.78), UiStyle.FIRE))
	else:
		var why: String = story.open_block_reason()
		if story.stage != StoryDirector.Stage.OPEN:
			line1 = "未开张"
			line2 = "酒馆还没开门"
		elif why == "":
			line1 = "[T] 挂招牌"
			line2 = "07:30–18:00 可开始运营"
		else:
			line1 = "未开张"
			line2 = _short_reason(why)
		_plate.add_theme_stylebox_override("panel", UiStyle.box(
				Color(UiStyle.SHADOW.r, UiStyle.SHADOW.g, UiStyle.SHADOW.b, 0.78), UiStyle.BROWN))

	if line1 != _cached_state:
		_state.text = line1
		_state.add_theme_color_override("font_color", col)
		_cached_state = line1
	if line2 != _cached_detail:
		_detail.text = line2
		_detail.add_theme_color_override("font_color",
				UiStyle.FIRE if open else UiStyle.LINEN_DARK)
		_cached_detail = line2

	# 今日预计客流：上限 = 已认识的候选数（每人每天最多来买一次）；
	# 营业中再补一句"已来 M"，玩家一眼看出还有没有新面孔可等。
	var sp: CustomerSpawner = _spawner()
	var crowd: String = ""
	if sp != null:
		crowd = "预计客流 %d 人" % sp.daily_customer_cap()
		if open:
			crowd += " · 已来 %d" % sp.arrived_today()
	if crowd != _cached_crowd:
		_crowd.text = crowd
		_crowd.add_theme_color_override("font_color",
				UiStyle.FIRE if open else UiStyle.LINEN_DARK)
		_cached_crowd = crowd


## 当前场景的顾客生成器（营业框在 HUD 下，得去当前场景的 Customers 节点取）。
func _spawner() -> CustomerSpawner:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Customers") as CustomerSpawner


## 距 22:00 强制关张还剩多久（游戏时间，格式 2h10m）。
func _until_close() -> String:
	var c: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if c == null:
		return "--"
	var now: int = c.hour * 60 + c.minute
	var end: int = StoryDirector.FORCE_CLOSE_HOUR * 60
	var left: int = end - now
	if left <= 0:
		return "即将打烊"
	var h: int = left / 60
	var m: int = left % 60
	return "%dh%02dm" % [h, m] if h > 0 else "%dm" % m


## 拒绝开张的原因太长，塞不进 152px 的条子，压成短句。
func _short_reason(why: String) -> String:
	if why.find("太早") >= 0:
		return "还没到 07:30"
	if why.find("天黑") >= 0:
		return "天黑了 · 明天请早"
	if why.find("店里") >= 0:
		return "回店里才能挂招牌"
	return why
