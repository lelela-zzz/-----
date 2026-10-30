class_name StoryDirector
extends Node
## 序章导演（autoload：Story）—— 把开张第一天的剧情串起来。
##
## 阶段（一次游戏只走一遍，走完停在 OPEN）：
##   NONE       游戏刚启动，等第一次进酒馆
##   PROLOGUE   序言卡（黑底卷轴）→ 萃歌开场自动对话
##   GO_MARKET  「去集市进材料」：走出酒馆 → 和凯瑟琳搭上话
##   BUY        「采购酿酒材料」：姜4 / 莓6 / 麦6 / 草4，库存即进度
##   RETURN     「把材料带回酒馆」：回店触发萃歌第二段对话
##   BREW       「试试魔法酿造机」：酿出暖身姜酒 + 河鲜淡啤
##   OPEN       开门营业：顾客开始进店（CustomerSpawner 的闸门）
##
## 为什么是 autoload：玩家要跨酒馆 / 外观 / 集市三个场景，剧情状态必须像
## Inventory 一样常驻。它同时是几个轻量全局 UI 的家 —— 任务追踪卡注入、
## Q 任务面板、M 地图 —— 免得为了一行按键给四个场景各加一个节点。
##
## 回归约定：测试用例在实例化场景前置 StoryDirector.force_disable = true，
## 序章整套哑火（不播卡、不摆萃歌、不放客），不惊动既有采样点。

enum Stage { NONE, PROLOGUE, GO_MARKET, BUY, RETURN, BREW, OPEN }

## 测试总闸：true = 序章不工作，顾客闸门直接放行。
static var force_disable: bool = false

const DATA_PATH: String = "res://data/story_prologue.json"
const NPC_DATA_PATH: String = "res://data/npcs.json"
const NPC_SCENE: String = "res://scenes/npc.tscn"
const QUEST_PANEL_SCENE: String = "res://scenes/ui/quest_panel.tscn"
const MAP_PANEL_SCENE: String = "res://scenes/ui/map_panel.tscn"
const CHOICE_PANEL_SCENE: String = "res://scenes/ui/choice_panel.tscn"
const SHOP_PANEL_SCENE: String = "res://scenes/ui/shop_panel.tscn"
const SETTINGS_PANEL_SCENE: String = "res://scenes/ui/settings_panel.tscn"
const LEDGER_PANEL_SCENE: String = "res://scenes/ui/ledger_panel.tscn"
const DAY_REPORT_SCENE: String = "res://scenes/ui/day_report_panel.tscn"
const SAVE_PANEL_SCENE: String = "res://scenes/ui/save_panel.tscn"

const CUIGE_ID: String = "tavern_cuige"
const CATHERINE_ID: String = "market_catherine"

const Q_MARKET: String = "prologue_market"
const Q_SUPPLIES: String = "prologue_supplies"
const Q_RETURN: String = "prologue_return"
const Q_BREW: String = "prologue_brew"

# ---- 指引目的地（dest）----------------------------------------------------
## 每个任务的 dest 说明"最后要去哪儿"，指引系统据此算跨图路线。
## **优先绑节点**（node）：NPC 会游荡、以后挪位置指引也不漂；
## 节点不在了（比如还没刷出来）才退回 pos 坐标兜底。
const VILLAGE: String = "res://scenes/village.tscn"
const WORLD: String = "res://scenes/world.tscn"

## 凯瑟琳：集市南边摊位。村庄里由 npc_spawner 生成，挂到 Sorted 下，
## 节点名 = "Npc_" + id（见 npc_spawner.gd）。
const DEST_CATHERINE: Dictionary = {
	"scene": "res://scenes/village.tscn",
	"node": "Sorted/Npc_market_catherine",
	"pos": [300, 782],
}

## 魔法酿酒机（锅）：world 地窖里
const DEST_POT: Dictionary = {
	"scene": "res://scenes/world.tscn",
	"node": "Sorted/BrewingPot",
	"pos": [320, 634],
}

# ---- 营业时段（v2：玩家决定何时开张，22:00 系统强制关张）--------------------
## 能挂招牌的最早/最晚时刻（游戏分钟）。07:30 起床、18:00 天黑前。
const OPEN_FROM_MIN: int = 7 * 60 + 30
const OPEN_UNTIL_MIN: int = 18 * 60
## 系统强制关张的整点（含这一小时之前的营业时间）。23:00 由时钟跨天接管。
const FORCE_CLOSE_HOUR: int = 22

var stage: int = Stage.NONE
## data/story_prologue.json 的内容（台词 / 采购清单 / 序言页）。
var data: Dictionary = {}

# ---- 章节准备任务（2026-10-30：营业额 + 认识，双条件才解锁）--------------
## 以前"还差多少营业额才能进剧情"只写在打烊结算卡上，玩家看不见全貌、
## 更不知道为什么有钱了还是没进展。现在拆成一条**任务栏里的准备清单**：
## 营业额进度 + 还差谁没认识，两件都办妥才会有人找上门。
##
## 清单全部打勾时，它自己就转成"已完成"、被任务栏的滑动窗口挤走，
## 紧接着章节任务补进来 —— 衔接刚好。
const PREP_QID: Dictionary = {
	"snow_logistics": "prep_snow",
	"ch2_moon": "prep_ch2",
	"ch3_dragon_king": "prep_ch3",
}
const PREP_TITLE: Dictionary = {
	"snow_logistics": "为雪山之行做准备",
	"ch2_moon": "为下一段旅程做准备",
	"ch3_dragon_king": "为最后的旅程做准备",
}
const PREP_DESC: String = "生意要做起来，客人也得认得你。"

# ---- 雪山后勤章节（序章开张后，营业额达标 + 次日，凯瑟琳主动委托）----
var snow_offered: bool = false       # 次日已弹出任务提示、凯瑟琳"接取任务"可用
var snow_started: bool = false       # 玩家已在凯瑟琳处接取
var _snow_revenue_day: int = 0       # 营业额达标的当天（0 = 未达标）

# ---- 第二章「月痕将熄」------------------------------------------------------
## 第一章完结 + 累计营业额达到此值 → 开启第二章（暂定 300）。
const REVENUE_THRESHOLD_CH2: float = 300.0
var _ch1_done: bool = false          # 第一章是否已完结
var _ch2_offered: bool = false       # 已提示过第二章解锁（只提示一次）

# ---- 第三章「龙王传说」------------------------------------------------------
## 第二章完结 + 累计营业额达到此值 → 奇斯带着密函上门（剧情文档写的是营业额门槛）。
const REVENUE_THRESHOLD_CH3: float = 400.0
var _ch2_done: bool = false          # 第二章是否已完结
var _ch3_offered: bool = false       # 已提示过第三章解锁（只提示一次）

# ---- 营业状态 --------------------------------------------------------------
## 招牌挂着没有。序章收尾会自动挂上，之后由玩家按 T 开关。
var business_open: bool = false
## 本次开张的"绝对分钟"（day*1440 + h*60 + m），用来算营业了几个小时。
var _open_abs_min: int = 0
## 这次关张是系统强制的（22:00 / 跨天 / 离店），提示语不一样。
var _last_close_forced: bool = false

var _npc_defs: Dictionary = {}
var _cuige: Npc = null
var _last_scene: String = "@"
## 正在播的萃歌自动台词 key（空 = 这次对话是玩家自己点的）。
var _pending_auto: String = ""
var _menu_open: bool = false
var _toast_label: Label = null


func _ready() -> void:
	_load_data()
	Inventory.changed.connect(_sync_progress)
	if Revenue != null:
		Revenue.revenue_changed.connect(_on_revenue)
	# 认识一位新客人 → 准备清单的认识进度要动、也可能就此凑齐开章条件
	if Regulars != null:
		Regulars.changed.connect(_on_regulars_changed)


func _process(_delta: float) -> void:
	if force_disable:
		return
	var id: String = _scene_id()
	if id != _last_scene:
		_on_scene_changed(id)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# 已有模态面板（对话框 / 集市 / 酿造）开着时不抢键
	if not get_tree().get_nodes_in_group("modal_ui").is_empty():
		return
	# 显示设置是系统级菜单：不受序章总闸控制，force_disable 的验收里也能开
	if key.keycode == KEY_F6:
		_open_panel(SETTINGS_PANEL_SCENE)
		return
	# 存档（F5）。同样放在总闸之前：验收要靠它开存档面板，玩家在序章里也该能存。
	if key.keycode == KEY_F5:
		open_save_panel()
		return
	if force_disable:
		return
	if key.keycode == KEY_Q:
		_open_panel(QUEST_PANEL_SCENE)
	elif key.keycode == KEY_M:
		_open_panel(MAP_PANEL_SCENE)
	elif key.keycode == KEY_T:
		toggle_business()
	elif key.keycode == KEY_X:
		# 结束经营后「睡到明天早上」：跳掉当天剩下的空等（见 _try_skip_day）
		_try_skip_day()
	elif key.keycode == KEY_R:
		# 账簿（酒谱 + 库存）：价格阶梯第一次对玩家可见的地方
		_open_panel(LEDGER_PANEL_SCENE)


## 顾客系统的闸门：序章没演完不放客进门，**招牌没挂也不放**。
func tavern_open() -> bool:
	return force_disable or (stage == Stage.OPEN and business_open)


# ---- 营业时段（玩家按 T 开关招牌）------------------------------------------
# 设计意图：让玩家自愿走成「早上进货 → 下午开张 → 晚市赚钱 → 22:00 打烊」。
# 靠两层引导，不靠硬拦：
#   1) 客流按时段有倍率（见 CustomerSpawner.TRAFFIC）——早上开门几乎没人；
#   2) 开张要 07:30 之后，且 22:00 系统强制关张 —— 深夜没有"开不完的门"。

func _clock() -> GameClock:
	return get_tree().get_first_node_in_group("game_clock") as GameClock


func _now_abs_min() -> int:
	var c: GameClock = _clock()
	if c == null:
		return 0
	return c.day * 1440 + c.hour * 60 + c.minute


## 现在能不能挂招牌（不能就返回原因，能就返回空串）。
func open_block_reason() -> String:
	if business_open:
		return "还在营业中"
	if stage != Stage.OPEN:
		return "酒馆还没开张（序章未完）"
	# 得站在店里：地窖/集市/雪山挂招牌没人看得见
	if not in_tavern():
		return "得回店里才能挂招牌。"
	var c: GameClock = _clock()
	if c == null:
		return ""
	var now: int = c.hour * 60 + c.minute
	if now < OPEN_FROM_MIN:
		return "太早了，天亮些再挂招牌吧。"
	if now > OPEN_UNTIL_MIN:
		return "天都黑了，明天白天再挂招牌吧。"
	return ""


# ---- 跳过当天（睡到明天早上）----------------------------------------------

## 「再按一次确认」的窗口（现实秒）。跳掉一整天不可逆，误触代价太大 —— 双按确认。
const SKIP_CONFIRM_SEC: float = 4.0
var _skip_armed_at: int = -1_000_000


## 现在能不能「睡到明天」：序章演完、招牌没挂着、人站在店里。
## 只影响营业框要不要显示 [X] 提示和按 X 是否生效；真正跳天在 GameClock.skip_to_morning。
func can_skip_day() -> bool:
	if force_disable or stage != Stage.OPEN:
		return false
	if business_open:
		return false
	return in_tavern()


## [X] 两段式：第一按武装确认（toast 提示），窗口内再按一次才真的睡。
func _try_skip_day() -> void:
	if not can_skip_day():
		return
	var now: int = Time.get_ticks_msec()
	if now - _skip_armed_at > int(SKIP_CONFIRM_SEC * 1000.0):
		_skip_armed_at = now
		_toast("再按一次 [X]，直接睡到明天早上", 2.5)
		return
	_skip_armed_at = -1_000_000
	var clock: GameClock = _clock()
	if clock != null:
		clock.skip_to_morning()


func toggle_business() -> void:
	if stage != Stage.OPEN:
		return
	if business_open:
		close_business(false)
		return
	var why: String = open_block_reason()
	if why != "":
		_toast(why)
		return
	open_business()


func open_business() -> void:
	if business_open or stage != Stage.OPEN:
		return
	business_open = true
	_open_abs_min = _now_abs_min()
	Revenue.begin_session()


## 关张：结算本次营业 + 弹出今日小结 + 让在场顾客散场。
## forced = 系统强制（22:00 / 跨天 / 离店），小结上的副标不同。
## 不扣任何运营开支（灯油柴火那套已按用户要求去掉）。
func close_business(forced: bool = false) -> void:
	if not business_open:
		return
	business_open = false
	_last_close_forced = forced
	var hours: int = business_hours()
	var session: Dictionary = Revenue.end_session()
	var revenue: int = int(round(float(session.get("revenue", 0.0))))
	var wines: int = int(session.get("wines", 0))
	# 先让客人往外走，再弹小结 —— 免得卡片一出来人就凭空没了
	_dismiss_nearby_customers()
	# 离店打烊不弹卡（人已经在别的场景，卡片会跟着旧场景一起销毁）
	if _scene_id().ends_with("world.tscn"):
		_show_day_report(revenue, wines, hours, forced)
	else:
		_toast("打烊了。今日进账 %d 铜（%d 瓶）。" % [revenue, wines], 5.0)


## 今日小结卡。若已有别的面板开着（比如正在卖酒），退化成一条 toast，不叠卡。
func _show_day_report(revenue: int, wines: int, hours: int, forced: bool) -> void:
	var hud: Node = _hud()
	if hud == null:
		return
	if not get_tree().get_nodes_in_group("modal_ui").is_empty():
		_toast("打烊了。今日进账 %d 铜（%d 瓶）。" % [revenue, wines], 5.0)
		return
	var ps: PackedScene = load(DAY_REPORT_SCENE) as PackedScene
	if ps == null:
		_toast("打烊了。今日进账 %d 铜（%d 瓶）。" % [revenue, wines], 5.0)
		return
	var panel: DayReportPanel = ps.instantiate() as DayReportPanel
	panel.report = {
		"day": _current_day(),
		"revenue": revenue,
		"wines": wines,
		"hours": hours,
		"best": int(round(Revenue.best_session)),
		"threshold": int(Revenue.REVENUE_THRESHOLD_SNOW),
		"forced": forced,
	}
	hud.add_child(panel)


func business_hours() -> int:
	if _open_abs_min <= 0:
		return 0
	var span: int = maxi(_now_abs_min() - _open_abs_min, 0)
	return maxi(1, int(ceil(float(span) / 60.0)))


func _dismiss_nearby_customers() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var spawner: CustomerSpawner = scene.get_node_or_null("Customers") as CustomerSpawner
	if spawner != null:
		spawner.dismiss_all()


## 22:00 强制关张（时钟整点信号）。
func _on_hour_changed(hour: int) -> void:
	if force_disable or stage != Stage.OPEN:
		return
	if hour == FORCE_CLOSE_HOUR and business_open:
		close_business(true)


# ---- 场景感知 --------------------------------------------------------------

func _scene_id() -> String:
	var scene: Node = get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


## 玩家此刻是否身处酒馆建筑内部。
## 地窖 2026-10-28 起并在 world.tscn 里（从左上角那扇门往上是同一张图的另一半），
## 所以这里只要认 world.tscn 一个场景。
## 挂招牌的准入、营业状态条的显隐都以这一处为准 —— 出了门就别把酒馆的东西
## 顶在集市 / 村子 / 雪山的屏幕上。
func in_tavern() -> bool:
	var id: String = _scene_id()
	return id.ends_with("world.tscn")


func _on_scene_changed(id: String) -> void:
	_last_scene = id
	if force_disable:
		return
	# 营业中走远（去集市/村子/雪山）＝ 店里没人看门，自动打烊结算。
	# 地窖 / 门口街上 / 地图面板传送回店都算"还在自家屋檐下"，不打烊。
	if business_open and not CustomerSpawner.TAVERN_INTERIOR.has(id):
		close_business(true)
	_ensure_tracker()
	if id.ends_with("world.tscn"):
		_spawn_cuige()
		if stage == Stage.NONE:
			_begin_prologue()
		elif stage == Stage.RETURN:
			_cuige_say("cuige_return")
		elif stage == Stage.OPEN:
			_ensure_side_npcs()
	elif id.ends_with("village.tscn") and stage == Stage.GO_MARKET:
		QuestLog.set_step_done(Q_MARKET, 0, true)
	# 连线必须在 spawn 之后：萃歌是上面刚生成的，先连她就漏接了
	_link_npcs()
	_sync_progress()
	# 雪山后勤：盯住本场景时钟的"跨天"信号（每场景重连一次）
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock != null:
		if not clock.day_changed.is_connected(_on_day_changed):
			clock.day_changed.connect(_on_day_changed)
		# 22:00 强制关张也挂在时钟上（同样每场景重连）
		if not clock.hour_changed.is_connected(_on_hour_changed):
			clock.hour_changed.connect(_on_hour_changed)


# ---- 序章各幕 --------------------------------------------------------------

func _begin_prologue() -> void:
	stage = Stage.PROLOGUE
	_spawn_cuige()
	var pages: Array = data.get("intro", []) as Array
	var hud: Node = _hud()
	if pages.is_empty() or hud == null:
		_after_intro()
		return
	var card_scene: PackedScene = load("res://scenes/ui/prologue_card.tscn") as PackedScene
	if card_scene == null:
		_after_intro()
		return
	var card: PrologueCard = card_scene.instantiate() as PrologueCard
	card.book_title = str(data.get("intro_title", "序言"))
	card.pages = PackedStringArray(pages)
	hud.add_child(card)
	card.closed.connect(_after_intro)


func _after_intro() -> void:
	if stage != Stage.PROLOGUE:
		return
	_cuige_say("cuige_open")


func _enter_market_stage() -> void:
	if stage != Stage.PROLOGUE:
		return
	stage = Stage.GO_MARKET
	QuestLog.add(Q_MARKET, "去集市进一批酿酒材料", "开张头一天，材料得备足。", DEST_CATHERINE)
	QuestLog.add_step(Q_MARKET, "走出酒馆，前往卢迪克集市")
	QuestLog.add_step(Q_MARKET, "和集市管理员凯瑟琳搭上话")
	# 极端情况：玩家开场就站在村口 —— 立即按现状刷一遍
	if _scene_id().ends_with("village.tscn"):
		QuestLog.set_step_done(Q_MARKET, 0, true)
	_refresh_cuige_lines()


func _open_supplies_quest() -> void:
	QuestLog.add(Q_SUPPLIES, "采购酿酒材料", "凯瑟琳的摊位就在集市南边，先聊两句再挑货。", DEST_CATHERINE)
	var supplies: Array = data.get("supplies", []) as Array
	for i: int in supplies.size():
		var d: Dictionary = supplies[i] as Dictionary
		QuestLog.add_step(Q_SUPPLIES, ItemDB.item_name(str(d["id"])), int(d["need"]))
	_sync_progress()


func _enter_brew_stage() -> void:
	if stage != Stage.RETURN:
		return
	stage = Stage.BREW
	QuestLog.complete(Q_RETURN)
	QuestLog.add(Q_BREW, "试试魔法酿造机", "魔法酿酒机刻着旧王朝大炼金师的符文。", DEST_POT)
	for wine: Variant in (data.get("brew", []) as Array):
		QuestLog.add_step(Q_BREW, "酿一瓶%s" % ItemDB.item_name(str(wine)))
	_sync_progress()
	_refresh_cuige_lines()


func _enter_open_stage() -> void:
	if stage != Stage.BREW:
		return
	stage = Stage.OPEN
	QuestLog.complete(Q_BREW)
	_toast(str(_story_lines().get("rush_notice", "顾客涌进了店里……")), 5.0)
	_refresh_cuige_lines()
	# 序章收尾=萃歌把招牌挂出去（不算玩家操作，所以跳过开张时段限制）；
	# 之后关掉再开就得自己按 T，并遵守 07:30–18:00 的挂招牌窗口。
	open_business()
	# 隔几秒补一句操作提示，别和上面那条 toast 挤在一起
	var hint: Tween = create_tween()
	hint.tween_interval(6.0)
	hint.tween_callback(func() -> void: _toast("按 T 可以随时挂 / 收招牌。", 4.0))
	# 开张后：把支线里"非顾客"的访客摆进酒馆（有支线数据才摆）
	_ensure_side_npcs()
	# 任务栏里挂上「为雪山之行做准备」——营业额进度 + 还差谁没认识，写在一处
	_ensure_prep("snow_logistics")


## 库存变化时刷新采购/酿造进度（Inventory.changed → 这里）。
func _sync_progress() -> void:
	if force_disable or stage < Stage.BUY:
		return
	if not QuestLog.is_complete(Q_SUPPLIES):
		var supplies: Array = data.get("supplies", []) as Array
		var all_done: bool = not supplies.is_empty()
		for i: int in supplies.size():
			var d: Dictionary = supplies[i] as Dictionary
			var got: int = Inventory.count(str(d["id"]))
			QuestLog.set_progress(Q_SUPPLIES, i, got)
			if got < int(d["need"]):
				all_done = false
		if all_done and stage == Stage.BUY:
			stage = Stage.RETURN
			QuestLog.complete(Q_SUPPLIES)
			QuestLog.add(Q_RETURN, "把材料带回酒馆", "萃歌在店里等着开锅。", DEST_POT)
			QuestLog.add_step(Q_RETURN, "回银辉酒馆，和萃歌说话")
	if stage >= Stage.BREW and not QuestLog.is_complete(Q_BREW):
		var brew: Array = data.get("brew", []) as Array
		var brewed_all: bool = not brew.is_empty()
		for i: int in brew.size():
			var wine: String = str(brew[i])
			QuestLog.set_step_done(Q_BREW, i, Inventory.has(wine))
			brewed_all = brewed_all and Inventory.has(wine)
		if brewed_all:
			_enter_open_stage()


# ---- 雪山后勤章节 ----------------------------------------------------------
# 触发：序章开张（stage==OPEN）后，**累计营业额**（Revenue.total）达到
# Revenue.REVENUE_THRESHOLD_SNOW，次日（GameClock 跨过 00:00）凯瑟琳主动弹出委托
# 提示；玩家去集市找她"接取任务"才正式激活 snow_logistics 章节，哈特菲利亚/奇斯/
# 厄里斯 三条支线才解锁可播。

# ---- 章节准备清单（任务栏里能看到"还差什么"）------------------------------

## 这一章的营业额门槛。
func _threshold_for(chapter: String) -> int:
	match chapter:
		"snow_logistics":
			return int(Revenue.REVENUE_THRESHOLD_SNOW)
		"ch2_moon":
			return int(REVENUE_THRESHOLD_CH2)
		"ch3_dragon_king":
			return int(REVENUE_THRESHOLD_CH3)
	return 0


## 建立准备清单（幂等：已存在就只刷进度）。
## 步骤顺序：0 = 累计营业额（计数型），1..N = 每位该认识的客人（布尔型）。
func _ensure_prep(chapter: String) -> void:
	var qid: String = str(PREP_QID.get(chapter, ""))
	if qid.is_empty() or Regulars == null:
		return
	if not QuestLog.has(qid):
		QuestLog.add(qid, str(PREP_TITLE.get(chapter, "准备")), PREP_DESC)
		QuestLog.add_step(qid, "累计营业额", maxi(1, _threshold_for(chapter)))
		for id: String in Regulars.required_for(chapter):
			QuestLog.add_step(qid, "跟 " + Regulars.display_name(id) + " 对话")
	_sync_prep(chapter)


## 把准备清单刷成真实进度（营业额 + 每个人认识没）。
## 两件都办妥时把清单**正式结档**（complete）：它从"还差活儿"名单退场、
## 触发 QuestLog 的追踪接力 —— 指引从准备阶段无缝交棒给章节主线。
func _sync_prep(chapter: String) -> void:
	var qid: String = str(PREP_QID.get(chapter, ""))
	if qid.is_empty() or Regulars == null or not QuestLog.has(qid):
		return
	if QuestLog.is_complete(qid):
		return
	QuestLog.set_progress(qid, 0, int(round(Revenue.total)))
	var req: Array[String] = Regulars.required_for(chapter)
	var all_done: bool = true
	for i: int in req.size():
		var known: bool = Regulars.is_known(req[i])
		QuestLog.set_step_done(qid, 1 + i, known)
		all_done = all_done and known
	if all_done and int(round(Revenue.total)) >= _threshold_for(chapter):
		QuestLog.complete(qid)
		_toast("万事俱备。消息很快就会传到该听见的人耳朵里。", 5.0)


## 第一章双条件都满足没：累计营业额够 **且** 该认识的人都认识了。
func _snow_ready() -> bool:
	if Regulars == null:
		return Revenue.total >= Revenue.REVENUE_THRESHOLD_SNOW
	return Revenue.total >= Revenue.REVENUE_THRESHOLD_SNOW \
			and Regulars.all_known_for("snow_logistics")


## 认识状态变了：刷清单，并重看一遍能不能开章。
func _on_regulars_changed() -> void:
	_sync_prep("snow_logistics")
	_sync_prep("ch2_moon")
	_sync_prep("ch3_dragon_king")
	if StoryDirector.force_disable or stage != Stage.OPEN:
		return
	_try_start_ch2()
	_try_start_ch3()
	if snow_started or snow_offered:
		return
	# 认识可能是"差的最后一块拼图"：钱早在口袋里了，今天才把人认全 → 当天达标
	if _snow_revenue_day == 0 and _snow_ready():
		_snow_revenue_day = _current_day()


func _current_day() -> int:
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	return clock.day if clock != null else 1


## 营业额变化：累计达标当天记下"达标日"，等跨天再提示（不立刻弹，避免当天正忙着）。
## 判据是**累计营业额**（Revenue.total），不是单次营业 —— 营业额本就是累计口径，
## "从开店到现在一共做了多少生意"，让"慢慢做起来"的玩家自然达标。
func _on_revenue(_total: float) -> void:
	_try_start_ch2()   # 第二章：第一章完成 + 营业额 + 认识名单
	_try_start_ch3()   # 第三章：第二章完成 + 营业额 + 认识名单（终章）
	# 营业额那条步骤就挂在准备清单里，跟着刷
	_sync_prep("snow_logistics")
	_sync_prep("ch2_moon")
	_sync_prep("ch3_dragon_king")
	if snow_started or snow_offered:
		return
	if StoryDirector.force_disable or stage != Stage.OPEN:
		return
	# **双条件**：钱够了、人也认全了，才算达标（记下当天，次日才弹委托）
	if _snow_revenue_day == 0 and _snow_ready():
		_snow_revenue_day = _current_day()


## 跨天：若已达标且已是"达标的次日"，凯瑟琳弹出委托提示。
func _on_day_changed(day: int) -> void:
	if snow_offered or snow_started:
		return
	if StoryDirector.force_disable or stage != Stage.OPEN:
		return
	if _snow_revenue_day > 0 and day > _snow_revenue_day:
		_offer_snow_logistics()


func _offer_snow_logistics() -> void:
	snow_offered = true
	_toast("凯瑟琳有新的委托：雪山科考队需要抗寒的酒品。去集市找她接取。", 6.0)


## 玩家在凯瑟琳处接取 → 激活章节、播放委托台词、发任务进 Q 面板。
func _start_snow_logistics() -> void:
	snow_started = true
	if SideStory != null:
		SideStory.activate_chapter("snow_logistics")
	var entries: Array = _story_lines().get("catherine_snow_offer", []) as Array
	if not entries.is_empty():
		_play_scripted(entries)
	# 第一章正式开场：任务「第一章 · 雾凇无虞」和后续 12 幕都由 ChapterStory 接管。
	# （第 0 幕"凯瑟琳委托"就是上面这段 scripted 台词，不重复播放。）
	# 原先这里另发一条 side_snow_logistics 任务，内容与第一章第一步完全重叠，
	# 会让 Q 面板同时挂着两条"去找哈特菲利亚"，已并进 ch1_frost。
	if ChapterStory != null:
		ChapterStory.begin()
		if not ChapterStory.finished.is_connected(_on_ch1_finished):
			ChapterStory.finished.connect(_on_ch1_finished)


## 第一章完结：记下，之后等累计营业额达标再开第二章。
func _on_ch1_finished() -> void:
	_ch1_done = true
	_ensure_prep("ch2_moon")   # 下一章的准备清单接上（营业额 + 还差谁没认识）
	_try_start_ch2()


## 第二章解锁：第一章已完成，且累计营业额 ≥ REVENUE_THRESHOLD_CH2（暂定 300）。
func _try_start_ch2() -> void:
	if StoryDirector.force_disable:
		return
	if not _ch1_done:
		return
	if Chapter2Story == null:
		return
	if Chapter2Story.is_active() or Chapter2Story.is_done():
		return
	if Revenue.total < REVENUE_THRESHOLD_CH2:
		return
	# 双条件之二：第二章该认识的人也得认全（名单见 Regulars.CHAPTER_REQUIRED）
	if Regulars != null and not Regulars.all_known_for("ch2_moon"):
		return
	if not _ch2_offered:
		_ch2_offered = true
		_toast("累计营业额达到 %d 铜。夜里，银辉酒馆似有新客人登门——回去看看。" % int(REVENUE_THRESHOLD_CH2), 6.0)
	if Chapter2Story != null and not Chapter2Story.finished.is_connected(_on_ch2_finished):
		Chapter2Story.finished.connect(_on_ch2_finished)
	Chapter2Story.begin()


## 第二章完结：记下，之后等累计营业额达标再开第三章。
func _on_ch2_finished() -> void:
	_ch2_done = true
	_ensure_prep("ch3_dragon_king")   # 终章的准备清单
	_try_start_ch3()


## 第三章解锁：第二章已完成，且累计营业额 ≥ REVENUE_THRESHOLD_CH3（400）。
## 第三章就是终章，播完 Chapter3Story.finished 即全篇结束。
func _try_start_ch3() -> void:
	if StoryDirector.force_disable:
		return
	if not _ch2_done:
		return
	if Chapter3Story == null:
		return
	if Chapter3Story.is_active() or Chapter3Story.is_done():
		return
	if Revenue.total < REVENUE_THRESHOLD_CH3:
		return
	# 双条件之二：第三章名单目前是空的（没有新面孔登场）→ 自动满足，仍只看营业额
	if Regulars != null and not Regulars.all_known_for("ch3_dragon_king"):
		return
	if not _ch3_offered:
		_ch3_offered = true
		_toast("累计营业额达到 %d 铜。那位行商又踏着雪沫进门了——回酒馆见见他。" % int(REVENUE_THRESHOLD_CH3), 6.0)
	Chapter3Story.begin()


## 直接播一段多说话人剧情（凯瑟琳委托台词等），复用支线面板。
func _play_scripted(entries: Array) -> void:
	var hud: Node = _hud()
	if hud == null:
		return
	var ps: PackedScene = load("res://scenes/ui/story_dialogue.tscn") as PackedScene
	if ps == null:
		return
	var panel: UiPanel = ps.instantiate() as UiPanel
	panel.set("entries", entries)
	hud.add_child(panel)


# ---- NPC 交互 --------------------------------------------------------------

func _spawn_cuige() -> void:
	if is_instance_valid(_cuige):
		return
	var def: Dictionary = _npc_defs.get(CUIGE_ID, {})
	var places: Array = def.get("placement", []) as Array
	var scene: Node = get_tree().current_scene
	var sorted: Node = scene.get_node_or_null("Sorted") if scene != null else null
	if def.is_empty() or places.is_empty() or sorted == null:
		push_error("[Story] 萃歌摆不进场景（缺数据或缺 Sorted 容器）")
		return
	var ps: PackedScene = load(NPC_SCENE) as PackedScene
	if ps == null:
		return
	var npc: Npc = ps.instantiate() as Npc
	npc.name = "Npc_" + CUIGE_ID
	npc.configure(def, places[0] as Dictionary)
	sorted.add_child(npc)
	_cuige = npc
	# 刚摆进来就该是"当前阶段该说的话"，不是 npcs.json 的常驻台词。
	_refresh_cuige_lines()


const SIDE_NPC_PREFIX: String = "Npc_side_"

## 序章结束后，把"非顾客"的支线访客摆进酒馆 —— **一次只摆一位**。
## 位置来自 data/side_stories.json 的 spawn；已经在场的不重复摆（跨场景往返幂等）。
## 数据里已经播完的那位会被撤走（他退场，下一位登场），所以这个函数既加也删。
## 剧情访客**不再静态摆位**（2026-10-30 用户要求）：
## 他们改由 CustomerSpawner 以**顾客身份**、和普通客人一样从门口走进来
## （见 CustomerSpawner._story_visitors），坐下点酒、按 [E] 交谈就播支线。
## 这里只剩一件事：把老存档／上一帧遗留的静态访客清掉，别和新来的顾客撞脸。
func _ensure_side_npcs() -> void:
	if force_disable:
		return
	for node: Node in get_tree().get_nodes_in_group("npc"):
		var old: Npc = node as Npc
		if old == null or not old.name.begins_with(SIDE_NPC_PREFIX):
			continue
		old.queue_free()


func _npc_exists(id: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = node as Npc
		if npc != null and npc.npc_id == id:
			return true
	return false


## 场景里所有 NPC 的对话关闭信号都汇到这里：凯瑟琳聊完弹菜单。
func _link_npcs() -> void:
	for node: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = node as Npc
		if npc == null or npc.has_meta("story_linked"):
			continue
		npc.set_meta("story_linked", true)
		npc.dialogue_closed.connect(_on_npc_dialogue_closed)


func _on_npc_dialogue_closed(id: String) -> void:
	if id == CUIGE_ID and _pending_auto != "":
		var key: String = _pending_auto
		_pending_auto = ""
		if key == "cuige_open":
			_enter_market_stage()
		elif key == "cuige_return":
			_enter_brew_stage()
		# 自动台词播完必须把她的话换回"当前阶段该说的话"。
		# 以前 _cuige_say() 只是把 lines 覆盖掉、播完不还原 —— 玩家再点她就会把
		# 开场独白/回店那段重听一遍。
		_refresh_cuige_lines()
		return
	if id == CATHERINE_ID and stage >= Stage.GO_MARKET:
		if stage == Stage.GO_MARKET:
			QuestLog.set_step_done(Q_MARKET, 1, true)
			QuestLog.complete(Q_MARKET)
			stage = Stage.BUY
			_open_supplies_quest()
		_open_catherine_menu()


func _open_catherine_menu() -> void:
	if _menu_open:
		return
	var hud: Node = _hud()
	var ps: PackedScene = load(CHOICE_PANEL_SCENE) as PackedScene
	if hud == null or ps == null:
		return
	var panel: ChoicePanel = ps.instantiate() as ChoicePanel
	panel.title = "集市管理处"
	var can_take: bool = snow_offered and not snow_started
	panel.options = [
		{"text": "采购物资", "enabled": true},
		# 雪山后勤解锁前灰色不可选中；达标次日凯瑟琳弹出委托后变为可接取
		{"text": "接取任务", "enabled": can_take, "hint": "雪山科考队" if not can_take else ""},
	]
	_menu_open = true
	hud.add_child(panel)
	panel.option_chosen.connect(_on_catherine_choice)
	panel.closed.connect(func() -> void: _menu_open = false)


func _on_catherine_choice(index: int) -> void:
	match index:
		0:
			_open_panel(SHOP_PANEL_SCENE)
		1:
			# 选项为可用（达标次日已弹出委托、且尚未接取）才接取，否则提示"暂无委托"
			if snow_offered and not snow_started:
				_start_snow_logistics()
			else:
				var no_quest: Array = _story_lines().get("catherine_no_quest", []) as Array
				if not no_quest.is_empty():
					_toast(str(no_quest[0]))


## 萃歌的自动台词：临时换上剧情文本再开口，收尾由 dialogue_closed 汇报。
func _cuige_say(key: String) -> void:
	if not is_instance_valid(_cuige):
		return
	var lines: Array = _story_lines().get(key, []) as Array
	if lines.is_empty():
		push_warning("[Story] 缺台词：%s" % key)
		return
	_pending_auto = key
	_cuige.lines = PackedStringArray(lines)
	_cuige.talk()


# ---- 萃歌的"阶段提示台词" ------------------------------------------------
# 玩家在中间态主动搭话时，她该说当前该做的事，而不是常驻寒暄。
#   GO_MARKET / BUY   → cuige_wait       「还没出门啊？凯瑟琳的摊位就在集市南边……」
#   RETURN / BREW     → cuige_wait_brew  「酿造机在锅上等着呢……」
#   OPEN 及之后        → cuige_open_done 「酒香都飘出街了……」
# 其余阶段（还没开张）退回 npcs.json 的常驻台词。
# 这些 key 以前只写在 JSON 里、没有任何触发点，所以永远播不到。

func _refresh_cuige_lines() -> void:
	if not is_instance_valid(_cuige):
		return
	# 有自动台词在播/待播时别抢：那条台词播完会再刷一次。
	if _pending_auto != "":
		return
	_cuige.lines = PackedStringArray(_cuige_lines_for(stage))


func _cuige_lines_for(s: int) -> Array:
	var key: String = ""
	match s:
		Stage.GO_MARKET, Stage.BUY:
			key = "cuige_wait"
		Stage.RETURN, Stage.BREW:
			key = "cuige_wait_brew"
		Stage.OPEN:
			key = "cuige_open_done"
	if key != "":
		var ls: Array = _story_lines().get(key, []) as Array
		if not ls.is_empty():
			return ls
		push_warning("[Story] 缺阶段台词：%s（退回常驻台词）" % key)
	return _cuige_idle_lines()


## npcs.json 里萃歌的常驻台词（数据驱动，不在这里硬编码文本）。
func _cuige_idle_lines() -> Array:
	var def: Dictionary = _npc_defs.get(CUIGE_ID, {}) as Dictionary
	return def.get("lines", []) as Array


# ---- 全局 UI（任务追踪卡 / Q / M / 提示条）---------------------------------

func _ensure_tracker() -> void:
	var hud: Node = _hud()
	if hud == null:
		return
	var has_tracker: bool = false
	var has_business: bool = false
	var has_arrow: bool = false
	var has_save_hint: bool = false
	var has_settings_hint: bool = false
	for child: Node in hud.get_children():
		if child is QuestTracker:
			has_tracker = true
		elif child is BusinessHud:
			has_business = true
		elif child is GuideArrow:
			has_arrow = true
		elif child is SaveHint:
			has_save_hint = true
		elif child is SettingsHint:
			has_settings_hint = true
	if not has_tracker:
		hud.add_child(QuestTracker.new())
	# 营业状态条（右上角）：招牌挂没挂 / 还剩多久打烊 / 今日进账
	if not has_business:
		hud.add_child(BusinessHud.new())
	# 屏幕边缘罗盘箭头：指当前地图里「下一跳」的传送门 / 目的地
	if not has_arrow:
		hud.add_child(GuideArrow.new())
	# 存档提示条（左上角、任务书下面）：[F5] 存档，点它也能开
	if not has_save_hint:
		hud.add_child(SaveHint.new())
	# 设置提示条（存档条下面）：[F6] 设置，点它也能开
	if not has_settings_hint:
		hud.add_child(SettingsHint.new())


func _open_panel(scene_path: String) -> void:
	var hud: Node = _hud()
	if hud == null:
		return
	var ps: PackedScene = load(scene_path) as PackedScene
	if ps == null:
		return
	hud.add_child(ps.instantiate())


## 打开存档面板（F5 / 点左上角那条提示都走这里）。
## 面板自己判断"这里能不能存"（灰空间之类不让存），所以这里只挡重复开面板。
func open_save_panel() -> void:
	if not get_tree().get_nodes_in_group("modal_ui").is_empty():
		return
	# 上一档的"已存档"浮字会压在面板标题上，开面板前先收掉
	if _toast_label != null and is_instance_valid(_toast_label):
		_toast_label.queue_free()
		_toast_label = null
	_open_panel(SAVE_PANEL_SCENE)


## 打开设置面板（F6 / 点左上角「[F6] 设置」都走这里）。
func open_settings_panel() -> void:
	if not get_tree().get_nodes_in_group("modal_ui").is_empty():
		return
	_open_panel(SETTINGS_PANEL_SCENE)


func _toast(text: String, seconds: float = 3.5) -> void:
	var hud: Node = _hud()
	if hud == null:
		return
	if _toast_label != null and is_instance_valid(_toast_label):
		_toast_label.queue_free()
	var label: Label = UiStyle.outlined_label(text, UiStyle.FIRE_CORE)
	label.position = Vector2(0, 92)
	label.size = Vector2(640, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 300
	hud.add_child(label)
	_toast_label = label
	var tween: Tween = create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


## 注入点 = HUD 下的 UIRoot（640×384 逻辑坐标 + 整体缩放的容器）。
## 规则写在 UiStyle.ui_layer 里，四处（Story/Npc/SideStory/InteractZone）共用一份。
func _hud() -> Node:
	return UiStyle.ui_layer(self)


# ---- 数据 ------------------------------------------------------------------

func _load_data() -> void:
	data = _read_json(DATA_PATH)
	if data.is_empty():
		push_error("[Story] 读不到 %s，序章退化为无剧情模式" % DATA_PATH)
		force_disable = true
	_npc_defs = {}
	var npcs: Dictionary = _read_json(NPC_DATA_PATH)
	for entry: Variant in (npcs.get("npcs", []) as Array):
		var d: Dictionary = entry as Dictionary
		_npc_defs[str(d.get("id", ""))] = d


func _read_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _story_lines() -> Dictionary:
	return data.get("lines", {}) as Dictionary


# ---- 存档 ------------------------------------------------------------------

## 存档快照：序章阶段 + 各章解锁旗标 + 当前营业状态。
## `_last_scene` 之类的不存 —— 读档必然换一次场景，让 _process 自己重判更安全。
func snapshot() -> Dictionary:
	return {
		"stage": stage,
		"snow_offered": snow_offered,
		"snow_started": snow_started,
		"snow_revenue_day": _snow_revenue_day,
		"ch1_done": _ch1_done,
		"ch2_offered": _ch2_offered,
		"ch2_done": _ch2_done,
		"ch3_offered": _ch3_offered,
		"business_open": business_open,
		"open_abs_min": _open_abs_min,
		"last_close_forced": _last_close_forced,
	}


## 读档：把阶段和旗标放回去。真正的"进店后该干什么"由下一次
## _on_scene_changed（换了场景必然触发）按恢复出来的 stage 重新分派。
func restore_progress(data: Dictionary) -> void:
	stage = clampi(int(data.get("stage", Stage.NONE)), Stage.NONE, Stage.OPEN)
	if stage == Stage.PROLOGUE:
		# 序章那一段全程在模态面板后面（按不动 F5），正常玩存不到 PROLOGUE。
		# 真存到了就退回 NONE：读档进店会重播一遍开场 —— 唯一不会把人卡死的处理。
		stage = Stage.NONE
	snow_offered = bool(data.get("snow_offered", false))
	snow_started = bool(data.get("snow_started", false))
	_snow_revenue_day = int(data.get("snow_revenue_day", 0))
	_ch1_done = bool(data.get("ch1_done", false))
	_ch2_offered = bool(data.get("ch2_offered", false))
	_ch2_done = bool(data.get("ch2_done", false))
	_ch3_offered = bool(data.get("ch3_offered", false))
	business_open = bool(data.get("business_open", false))
	_open_abs_min = int(data.get("open_abs_min", 0))
	_last_close_forced = bool(data.get("last_close_forced", false))
	# 瞬时状态一律清空：面板随旧场景释放，指针留着会指向已释放的节点
	_pending_auto = ""
	_menu_open = false
	_toast_label = null
	if _cuige != null and not is_instance_valid(_cuige):
		_cuige = null


## 读档前清场：把"还没说完的那句"丢掉，别让它落到新场景的 HUD 上。
func abort_pending_dialogue() -> void:
	_pending_auto = ""
	_menu_open = false


## 给别的系统（存档面板 / 自动存档）用的浮字提示。
func toast(text: String, seconds: float = 3.0) -> void:
	_toast(text, seconds)
