extends Node
## 序章验收：序言卡 → 萃歌开场 → 去集市 → 凯瑟琳采购 → 回店 → 酿造 → 开门。
##   "<godot.exe>" --headless --path . res://tests/verify_prologue.tscn --quit-after 6000
##
## 这是唯一一个**故意不关** StoryDirector 的测试：它把 world / village 实例
## 挂到 root 上并手动切 current_scene，逼 Story 的场景感知走完整条序章链。
## 判定看 [check] 行，结尾打印 [prologue] 总账。

var scene: Node2D
var village: Node2D
var story: StoryDirector
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	story = get_node_or_null("/root/Story") as StoryDirector
	_check_data()
	_check_stage_lines()
	await _run_prologue()

	print("[prologue] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 0b. 萃歌的"阶段提示台词"是否真的接上 ---------------------------------
# cuige_wait / cuige_wait_brew / cuige_open_done 这三条以前只写在 JSON 里、
# story.gd 没有任何触发点，等于死文案。这里按阶段逐个核对"该说哪一条"。
func _check_stage_lines() -> void:
	var bad: String = ""
	var lmap: Dictionary = {
		StoryDirector.Stage.GO_MARKET: "cuige_wait",
		StoryDirector.Stage.BUY: "cuige_wait",
		StoryDirector.Stage.RETURN: "cuige_wait_brew",
		StoryDirector.Stage.BREW: "cuige_wait_brew",
		StoryDirector.Stage.OPEN: "cuige_open_done",
	}
	var lines_root: Dictionary = story.data.get("lines", {}) as Dictionary
	for st: int in lmap.keys():
		var key: String = str(lmap[st])
		var want: Array = lines_root.get(key, []) as Array
		var got: Array = story._cuige_lines_for(st)
		if want.is_empty():
			bad += "词条 %s 为空 " % key
		elif got != want:
			bad += "stage%d 没给 %s " % [st, key]

	# 还没开张的两个阶段必须退回 npcs.json 的常驻台词（别乱说"该出门了"）
	var idle: Array = story._cuige_idle_lines()
	if idle.is_empty():
		bad += "常驻台词为空 "
	for st: int in [StoryDirector.Stage.NONE, StoryDirector.Stage.PROLOGUE]:
		if story._cuige_lines_for(st) != idle:
			bad += "stage%d 未退回常驻台词 " % st

	_report("萃歌的阶段提示台词全部接上（等出门 / 等开锅 / 开张收尾）",
			bad == "" and idle.size() > 0,
			"常驻 %d 句 / %s" % [idle.size(), bad])


# ---- 0. 数据 -------------------------------------------------------------

func _check_data() -> void:
	var supplies: Array = story.data.get("supplies", []) as Array
	var total: int = 0
	var names_ok: bool = not supplies.is_empty()
	for s: Variant in supplies:
		var d: Dictionary = s as Dictionary
		var id: String = str(d["id"])
		if ItemDB.item(id).is_empty():
			names_ok = false
		total += ItemDB.price(id) * int(d["need"])
	_report("首单采购清单四味料齐全、且总价 ≤ 起始铜币",
			names_ok and total <= Inventory.START_COPPER and supplies.size() == 4,
			"清单 %d 项 / 总价 %d 铜 / 起始 %d 铜"
					% [supplies.size(), total, Inventory.START_COPPER])

	var inputs: Array = ItemDB.recipe("r_warm_ginger").get("inputs", []) as Array
	var has_barley: bool = false
	for e: Variant in inputs:
		if str((e as Dictionary)["id"]) == "barley":
			has_barley = true
	_report("暖身姜酒配方按剧情补了大麦（姜/莓/麦）",
			has_barley and inputs.size() == 3,
			"inputs=%s" % [inputs])


# ---- 1. 走一遍序章 -------------------------------------------------------

func _run_prologue() -> void:
	# 等一帧再挂场景 —— _ready 期间 root 还在摆自己的孩子，直接 add_child 会报忙
	await get_tree().process_frame
	# 世界与村庄都挂 root，靠切 current_scene 模拟传送（同 vshot 的做法）
	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	village = (load("res://scenes/village.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(village)

	# 进世界 → 序言卡自动弹出
	for i in 30:
		await get_tree().process_frame
		if not _modals().is_empty():
			break
	var card: PrologueCard = _modal_of(PrologueCard) as PrologueCard
	_report("进酒馆即弹序言卡（卡里 6 页）",
		card != null and card.pages.size() == 6 and story.stage == StoryDirector.Stage.PROLOGUE,
			"card=%s / pages=%s / stage=%d" % [card != null,
			card.pages.size() if card != null else -1, story.stage])

	# 关卡 → 萃歌开场白自动开口
	if card != null:
		card.close()
	for i in 10:
		await get_tree().process_frame
	var box: UiPanel = _modal_of(UiPanel)
	_report("序言收尾接萃歌开场自动对话",
			box != null and str(box.get("speaker")) == "萃歌",
			"speaker=%s" % (box.get("speaker") if box != null else "<无>"))

	# 连按 E 走完台词 → 进入 GO_MARKET，任务上板
	await _finish_dialogue()
	_report("开场白说完 → 进入「去集市」任务",
			story.stage == StoryDirector.Stage.GO_MARKET and QuestLog.has(story.Q_MARKET),
			"stage=%d / has_q=%s" % [story.stage, QuestLog.has(story.Q_MARKET)])
	var market: Dictionary = QuestLog.quest(story.Q_MARKET)
	_report("追踪任务有两个步骤（出门 / 找凯瑟琳）",
			(market.get("steps", []) as Array).size() == 2,
			"steps=%s" % [(market.get("steps", []) as Array).size()])

	# 自动台词播完，萃歌的话必须换回"当前阶段该说的"，不能还留着开场独白
	var cuige: Npc = _npc_by_id("tavern_cuige")
	var cuige_lines: Array = []
	if cuige != null:
		for s: String in cuige.lines:
			cuige_lines.append(s)
	var wait_lines: Array = (story.data.get("lines", {}) as Dictionary).get("cuige_wait", []) as Array
	_report("开场白播完萃歌改说「还没出门」（不再重播独白）",
			cuige != null and not wait_lines.is_empty() and cuige_lines == wait_lines,
			"lines=%s" % str(cuige_lines))

	# 序章没完，顾客闸门必须关着
	var spawner: CustomerSpawner = scene.get_node("Customers") as CustomerSpawner
	for i in 40:
		await get_tree().physics_frame
	_report("序章期间顾客闸门关闭（不开张）",
			not story.tavern_open() and not spawner._running,
			"tavern_open=%s / running=%s" % [story.tavern_open(), spawner._running])

	# 切到村庄 → 第一步自动打勾；凯瑟琳已按数据摆在集市
	get_tree().current_scene = village
	for i in 10:
		await get_tree().process_frame
	var market_q: Dictionary = QuestLog.quest(story.Q_MARKET)
	var steps: Array = market_q.get("steps", []) as Array
	var step0: bool = not steps.is_empty() and bool((steps[0] as Dictionary)["done"])
	var catherine: Npc = _npc_by_id("market_catherine")
	_report("到村自动勾掉「走出酒馆」，凯瑟琳站在集市摊位旁",
			step0 and catherine != null,
			"step0=%s / catherine=%s" % [step0, catherine != null])

	# 和凯瑟琳聊完 → 进入采购任务 + 弹出「采购物资 / 接取任务」菜单
	if catherine != null:
		catherine.talk()
	for i in 10:
		await get_tree().process_frame
	# 菜单一弹出来就停手 —— 再按 E 会把「采购物资」确认下去
	await _finish_dialogue(ChoicePanel)
	var menu: ChoicePanel = _modal_of(ChoicePanel) as ChoicePanel
	_report("凯瑟琳聊完弹选项菜单（接任务置灰）",
			menu != null and menu.options.size() == 2 and not bool(menu.options[1]["enabled"]),
			"menu=%s / options=%d" % [menu != null,
			menu.options.size() if menu != null else -1])
	_report("聊完进入「采购酿酒材料」任务（四条计数步骤）",
			story.stage == StoryDirector.Stage.BUY and QuestLog.has(story.Q_SUPPLIES)
					and (QuestLog.quest(story.Q_SUPPLIES).get("steps", []) as Array).size() == 4,
			"stage=%d / steps=%s" % [story.stage,
			(QuestLog.quest(story.Q_SUPPLIES).get("steps", []) as Array).size()
					if QuestLog.has(story.Q_SUPPLIES) else -1])
	if menu != null:
		menu.close()
	for i in 6:
		await get_tree().process_frame

	# 按清单把材料塞进库存（采购面板买的就是这些数）—— 凑齐即转「回店」
	Inventory.clear()
	Inventory.add("ginger", 4)
	Inventory.add("wild_berry", 6)
	Inventory.add("barley", 6)
	Inventory.add("fish_mint", 4)
	for i in 10:
		await get_tree().process_frame
	_report("材料凑齐 → 采购完成，转入「把材料带回酒馆」",
			QuestLog.is_complete(story.Q_SUPPLIES) and story.stage == StoryDirector.Stage.RETURN,
			"stage=%d" % story.stage)

	# 回到酒馆 → 萃歌第二段自动对话 → 进入酿造任务
	get_tree().current_scene = scene
	for i in 10:
		await get_tree().process_frame
	var box2: UiPanel = _modal_of(UiPanel)
	_report("回店触发萃歌第二段自动对话",
			box2 != null and str(box2.get("speaker")) == "萃歌",
			"speaker=%s" % (box2.get("speaker") if box2 != null else "<无>"))
	await _finish_dialogue()
	_report("第二段说完 → 进入「试试魔法酿造机」（两条酿造步骤）",
			story.stage == StoryDirector.Stage.BREW and QuestLog.has(story.Q_BREW)
					and (QuestLog.quest(story.Q_BREW).get("steps", []) as Array).size() == 2,
			"stage=%d" % story.stage)

	# 酿造阶段再点萃歌，她该催去开锅（cuige_wait_brew）
	var cuige_b: Npc = _npc_by_id("tavern_cuige")
	var brew_got: Array = []
	if cuige_b != null:
		for s: String in cuige_b.lines:
			brew_got.append(s)
	var brew_want: Array = (story.data.get("lines", {}) as Dictionary).get("cuige_wait_brew", []) as Array
	_report("酿造阶段萃歌催去开锅（cuige_wait_brew 接上）",
			cuige_b != null and not brew_want.is_empty() and brew_got == brew_want,
			"lines=%s" % str(brew_got))

	# 两瓶酒入库 → 开门营业，顾客闸门放行
	Inventory.add("wine_warm_ginger", 1)
	Inventory.add("wine_river_ale", 1)
	for i in 20:
		await get_tree().physics_frame
	_report("姜酒 + 淡啤入库 → 序章完成、酒馆开张",
			story.stage == StoryDirector.Stage.OPEN and story.tavern_open()
					and QuestLog.is_complete(story.Q_BREW),
			"stage=%d / open=%s" % [story.stage, story.tavern_open()])
	# 开门瞬间涌进一拨人（错峰入场，~2s 内到齐 opening_rush_count 人），其余仍按原节奏零星补位。
	for i in 200:   # ~3.3s @60Hz 物理帧，足够 rush 错峰进场
		await get_tree().physics_frame
	_report("开张即涌进一拨人（开场 rush = %d）" % spawner.opening_rush_count,
			spawner._running and spawner.active_count() >= spawner.opening_rush_count,
			"running=%s / active=%d / rush_count=%d" % [spawner._running,
			spawner.active_count(), spawner.opening_rush_count])

	# 开张后萃歌的收尾台词也要换过来（cuige_open_done）
	var cuige2: Npc = _npc_by_id("tavern_cuige")
	var done_got: Array = []
	if cuige2 != null:
		for s: String in cuige2.lines:
			done_got.append(s)
	var done_want: Array = (story.data.get("lines", {}) as Dictionary).get("cuige_open_done", []) as Array
	_report("开张后萃歌改说「酒香都飘出街了」（收尾台词接上）",
			cuige2 != null and not done_want.is_empty() and done_got == done_want,
			"lines=%s" % str(done_got))


# ---- 工具 ---------------------------------------------------------------

func _modals() -> Array[Node]:
	return get_tree().get_nodes_in_group("modal_ui")


func _modal_of(type: Variant) -> UiPanel:
	for n: Node in _modals():
		if is_instance_valid(n) and is_instance_of(n, type):
			return n as UiPanel
	return null


## 连按 E 直到对话框收摊（每句最多两下：补全 + 翻页）。
## stop_at 传面板类型时，看到那个面板就停手（比如凯瑟琳的选项菜单）。
func _finish_dialogue(stop_at: Variant = null) -> void:
	for i in 40:
		if stop_at != null and _modal_of(stop_at) != null:
			break
		if _modal_of(UiPanel) == null:
			break
		_push_key(KEY_E)
		await get_tree().process_frame
		await get_tree().process_frame
	for i in 4:
		await get_tree().process_frame


func _npc_by_id(id: String) -> Npc:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = n as Npc
		if npc != null and npc.npc_id == id:
			return npc
	return null


func _push_key(keycode: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_viewport().push_input(down)
	var up: InputEventKey = InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_viewport().push_input(up)


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
