extends Node
## 支线总控（autoload：SideStory）—— 序章结束（Story.stage == OPEN）之后，
## 玩家与对应 NPC 一交谈就播放那段支线；每条支线只播一次。
##
## 为什么单独一个 autoload 而不是塞进 Story：
## Story 是序章导演，已经有一套被验收脚本盯死的状态机；支线是"序章之后"的
## 另一层内容，独立出来既能跨场景存活，又不会碰序章逻辑、不惊动回归用例。
##
## 与测试的关系：所有支线都要求 Story 真的在跑（force_disable == false）且
## 已经到 OPEN。回归用例普遍把 StoryDirector.force_disable 置 true，于是
## SideStory.active() 恒为 false —— 不该触发的地方一句都不会冒出来。
##
## 放送节奏（2026-10 改）：**开张当天不出剧情**。第一天客人只是来喝酒，支线从
## 第二天起逐日放出（每条支线用 min_day 写自己第几天才能播）。天数由本模块自己
## 数：GameClock 是每场景重建的（day 每次都从 1 开始），跨场景会丢，所以这里
## 听各场景时钟的 day_changed 自己累加，autoload 存活 → 天数连续。

const DATA_PATH: String = "res://data/side_stories.json"
const DIALOGUE_SCENE: String = "res://scenes/ui/story_dialogue.tscn"
const NPC_SCENE: String = "res://scenes/npc.tscn"
const NPC_DATA_PATH: String = "res://data/npcs.json"

## 第几天才开始放支线。1 = 开张当天（第一天不出剧情）。
const FIRST_STORY_DAY: int = 2

var data: Dictionary = {}

## 已播过的支线 id。
var _played: Dictionary = {}
## 已解锁的地图/开关 flag。
var _unlocked: Dictionary = {}
## 已激活的章节（雪山后勤等）。支线可挂到某章节下，章节未激活时不视为 pending。
var _chapters: Dictionary = {}
## 剧情天数：1 = 开张当天。只在本模块里累加，跨场景连续。
var _story_day: int = 1
## 当前场景的时钟（每换场景会重建，靠 is_instance_valid 认领新的）。
var _clock: GameClock = null
## npcs.json 定义表：支线 extras 里写 "npc":"xxx" 时按它摆人。
var _npc_defs: Dictionary = {}
## 本段支线"叫来同台"的人物节点（矮人三兄弟等）：播完撤掉。
var _extra_nodes: Array[Node] = []
## 对话期间被冻结的常驻游荡角色（老板娘等）：播完 resume_wander() 恢复。
var _held_npcs: Array[Node] = []


func _ready() -> void:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("[SideStory] 读不到 %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[SideStory] %s 不是合法 JSON 对象" % DATA_PATH)
		return
	data = parsed as Dictionary
	_load_npc_defs()


## 读 npcs.json：支线 extras 里写了 "npc":"xxx" 时，按这里的定义把人摆进场景。
func _load_npc_defs() -> void:
	_npc_defs.clear()
	var f2: FileAccess = FileAccess.open(NPC_DATA_PATH, FileAccess.READ)
	if f2 == null:
		return
	var parsed2: Variant = JSON.parse_string(f2.get_as_text())
	f2.close()
	if typeof(parsed2) != TYPE_DICTIONARY:
		return
	for entry: Variant in (parsed2 as Dictionary).get("npcs", []):
		if entry is Dictionary:
			var d: Dictionary = entry as Dictionary
			_npc_defs[str(d.get("id", ""))] = d


func _process(_delta: float) -> void:
	_ensure_clock()


## 认领当前场景的时钟并听它跨天。换场景后旧时钟被释放，这里自动重连。
func _ensure_clock() -> void:
	if _clock != null and is_instance_valid(_clock):
		return
	var c: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if c == null:
		return
	_clock = c
	if not c.day_changed.is_connected(_on_day_changed):
		c.day_changed.connect(_on_day_changed)


## 跨天：剧情天数 +1；新的一天可能有新的支线/新的访客，让剧情导演重摆一次。
func _on_day_changed(_day: int) -> void:
	_story_day += 1
	if Story == null or StoryDirector.force_disable:
		return
	if active():
		Story.call_deferred("_ensure_side_npcs")


# ---- 查询 ---------------------------------------------------------------

## 支线系统当前是否工作：必须是真实的序章流程、且已经开张。
func active() -> bool:
	if Story == null:
		return false
	if StoryDirector.force_disable:
		return false
	return Story.stage == StoryDirector.Stage.OPEN


func arcs() -> Array:
	return data.get("arcs", []) as Array


## 某角色还有没有没播的支线。
func has_pending(npc_id: String) -> bool:
	if not active():
		return false
	return not pending_for(npc_id).is_empty()


## 某角色"下一段该播"的支线（没有就返回空字典）。
func pending_for(npc_id: String) -> Dictionary:
	for arc: Variant in arcs():
		var a: Dictionary = arc as Dictionary
		if str(a.get("npc_id", "")) != npc_id:
			continue
		if bool(_played.get(str(a.get("id", "")), false)):
			continue
		if not _chapter_ok(a):
			continue
		if not _day_ok(a):
			continue
		return a
	return {}


## 剧情天数（1 = 开张当天）。
func day() -> int:
	return _story_day


## 支线是否已经"开闸"：系统在跑，且已经过了第一天。
func unlocked() -> bool:
	return active() and _story_day >= FIRST_STORY_DAY


## 这条支线今天能不能播：第一天一律不行；之后看 min_day（没写就是第二天）。
func _day_ok(a: Dictionary) -> bool:
	if _story_day < FIRST_STORY_DAY:
		return false
	return _story_day >= int(a.get("min_day", FIRST_STORY_DAY))


func is_unlocked(flag: String) -> bool:
	return bool(_unlocked.get(flag, false))


## 由章节导演（ChapterStory）解锁一个 flag，比如「矿道入口」写进 M 地图面板。
func unlock(flag: String) -> void:
	if flag != "":
		_unlocked[flag] = true


## 章节进行中：支线访客不登场、也不抢 E 交互。
## 本章要讲的故事由 ChapterStory 按幕播，同一段剧情不该再从访客线里演一遍。
## 注意只抑制"登场/播放"，不抑制 pending_for —— 任务/验收仍要看得到支线状态。
func _suppressed() -> bool:
	return ChapterStory != null and ChapterStory.is_active()


## 激活一个章节（雪山后勤等）。被章节 gate 的支线，章节激活前不视为 pending。
func activate_chapter(name: String) -> void:
	_chapters[name] = true


func is_chapter_active(name: String) -> bool:
	return bool(_chapters.get(name, false))


## 某条支线是否受章节 gate：没有 chapter 字段 → 永远可播；有 chapter 字段 → 章节须激活。
func _chapter_ok(a: Dictionary) -> bool:
	var ch: Variant = a.get("chapter", null)
	if ch == null or str(ch) == "":
		return true
	return is_chapter_active(str(ch))


func has_played(id: String) -> bool:
	return bool(_played.get(id, false))


## 章节导演收尾时把已被本章覆盖的支线标记为已播，免得章节结束后它们再以访客身份重演。
func mark_played(id: String) -> void:
	if id != "":
		_played[id] = true


## 需要在序章后静态摆进酒馆的 NPC 位置（数据里带 spawn 的支线）。
##
## **一次只摆一位**：按数据顺序取第一位"还没播"的访客，播完他才退场、下一位才登场。
## 三位一起杵在店里（外加 3 位排队的顾客和老板娘）会把 640×384 的酒馆挤成集市。
func spawn_specs() -> Array:
	if _suppressed():
		return []
	for arc: Variant in arcs():
		var a: Dictionary = arc as Dictionary
		var sp: Variant = a.get("spawn", null)
		if not (sp is Dictionary):
			continue
		if bool(_played.get(str(a.get("id", "")), false)):
			continue
		if not _chapter_ok(a):
			continue
		if not _day_ok(a):
			continue
		var d: Dictionary = sp as Dictionary
		return [{
			"id": str(a.get("npc_id", "")),
			"pos": d.get("pos", [0, 0]),
			"facing": str(d.get("facing", "down")),
		}]
	return []


# ---- 播放 ---------------------------------------------------------------

## 尝试替某位 NPC 播放支线。返回 true = 已接管这次「按 E」，调用方别再开常规对话。
func try_play(npc_id: String, npc_node: Node) -> bool:
	if not active():
		return false
	if _suppressed():
		return false
	var arc: Dictionary = pending_for(npc_id)
	if arc.is_empty():
		return false
	var hud: Node = _hud()
	if hud == null:
		return false
	var ps: PackedScene = load(DIALOGUE_SCENE) as PackedScene
	if ps == null:
		push_error("[SideStory] 加载不了 %s" % DIALOGUE_SCENE)
		return false

	var panel: UiPanel = ps.instantiate() as UiPanel
	panel.set("entries", arc.get("entries", []))
	# 交接环节要显示"给谁"：把这一段支线的人物名带过去
	panel.set("gift_guest", str(arc.get("npc_name", "")))
	# 卖酒要收钱：把付款人交过去，顾客有钱袋、站桩 NPC 走标价
	panel.set("trade_payer", npc_node)
	if npc_node != null:
		# 说话期间别让对方乱走/走掉（Customer 的耐心计时也看这个）
		npc_node.set("_talking", true)
	# 多人同台：支线带 extras 时把同伴摆到说话人身边一起入镜；
	# 同时把场景里正在游荡的常驻角色（老板娘等）站定，免得剧情里自顾自走掉。
	_spawn_arc_extras(arc, npc_node)
	_freeze_wanderers()
	hud.add_child(panel)
	panel.closed.connect(_on_arc_closed.bind(arc, npc_node))
	return true


func _on_arc_closed(arc: Dictionary, npc_node: Node) -> void:
	# 这段戏演完了：恢复被冻结的游荡者、撤掉同台的 extras。
	_clear_arc_extras()
	var id: String = str(arc.get("id", ""))
	if id != "":
		_played[id] = true
	if npc_node != null and is_instance_valid(npc_node):
		npc_node.set("_talking", false)
	_apply_quest(arc)
	_apply_unlock(arc)
	# 这段戏演完了：这位访客退场、下一位登场（增删节点由 Story 负责）。
	# call_deferred：此刻面板刚关，别在同一帧里删自己脚下的节点。
	if Story != null and not StoryDirector.force_disable:
		Story.call_deferred("_ensure_side_npcs")


func _apply_quest(arc: Dictionary) -> void:
	var q: Variant = arc.get("quest", null)
	if not (q is Dictionary):
		return
	var qd: Dictionary = q as Dictionary
	var qid: String = str(qd.get("id", ""))
	if qid == "":
		return
	QuestLog.add(qid, str(qd.get("title", "")), str(qd.get("desc", "")),
			qd.get("dest", {}) as Dictionary)
	for step: Variant in (qd.get("steps", []) as Array):
		QuestLog.add_step(qid, str(step))
	for i: Variant in (qd.get("done_steps", []) as Array):
		QuestLog.set_step_done(qid, int(i), true)


func _apply_unlock(arc: Dictionary) -> void:
	var u: Variant = arc.get("unlock", null)
	if not (u is Dictionary):
		return
	var ud: Dictionary = u as Dictionary
	var flag: String = str(ud.get("flag", ""))
	if flag != "":
		_unlocked[flag] = true
	var toast: String = str(ud.get("toast", ""))
	if toast != "":
		Story._toast(toast, 5.0)


# ---- 多人同台 ------------------------------------------------------------

## 支线带 extras 时，把同伴（Npc）摆到说话人身边一起入镜。
## offset 相对说话人脚下（顾客站在吧台前 / 静态访客站在 spawn 点）：
##   "extras": [{"npc":"dwarf_serv_kain","offset":[-40,22],"facing":"right"}, ...]
## 摆完后全场看向玩家（玩家不在就看向说话人），与两章导演同一套纪律。
func _spawn_arc_extras(arc: Dictionary, visitor: Node) -> void:
	var ex: Variant = arc.get("extras", null)
	if not (ex is Array) or (ex as Array).is_empty():
		return
	var scene: Node = get_tree().current_scene
	var sorted: Node = scene.get_node_or_null("Sorted") if scene != null else null
	if sorted == null:
		push_warning("[SideStory] 当前场景没有 Sorted，extras 摆不出来")
		return
	var ps: PackedScene = load(NPC_SCENE) as PackedScene
	if ps == null:
		return
	var base: Vector2 = (visitor as Node2D).global_position \
			if visitor is Node2D else Vector2(320, 300)
	for e: Variant in ex as Array:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e as Dictionary
		var nid: String = str(d.get("npc", ""))
		if nid == "" or not _npc_defs.has(nid):
			push_warning("[SideStory] extras 里的人物未定义：%s" % nid)
			continue
		if _find_npc_node(nid) != null:
			continue   # 已在场（常驻）就不重复摆
		var off: Array = d.get("offset", [-30, 0]) as Array
		var npc: Node = ps.instantiate()
		npc.name = "Npc_side_" + nid
		var place: Dictionary = {
			"pos": [base.x + float(off[0]), base.y + float(off[1])],
			"facing": str(d.get("facing", "down")),
			"wander": 0.0,
		}
		# extra 上的附加键（no_interact 等）透传给 Npc.configure。
		for k: String in d:
			if k != "npc" and k != "offset" and k != "spawn" and not place.has(k):
				place[k] = d[k]
		npc.call("configure", _npc_defs[nid], place)
		sorted.add_child(npc)
		_extra_nodes.append(npc)
	var look_at: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if look_at == null and visitor is Node2D:
		look_at = visitor as Node2D
	if look_at != null:
		for n: Node in _extra_nodes:
			if is_instance_valid(n) and n.has_method("face_toward"):
				n.call("face_toward", look_at.global_position)


## 对话期间把正在游荡的常驻角色（老板娘等）一起站定；顾客不冻。
func _freeze_wanderers() -> void:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if _held_npcs.has(n) or _extra_nodes.has(n):
			continue
		if n.has_method("wants_service"):
			continue   # 顾客有自己的逻辑、且会自行离场
		if n.has_method("is_wandering") and n.call("is_wandering"):
			n.call("hold")
			_held_npcs.append(n)


## 支线收尾：恢复被冻结的游荡者，撤掉同台的 extras。
## 节点若已随旧场景释放（is_instance_valid 兜底），引用清掉即可。
func _clear_arc_extras() -> void:
	for n: Node in _held_npcs:
		if is_instance_valid(n) and n.has_method("resume_wander"):
			n.call("resume_wander")
	_held_npcs.clear()
	for n: Node in _extra_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_extra_nodes.clear()


## 场景里这个 NPC 的节点（找不到返回 null）。
func _find_npc_node(id: String) -> Node:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return n
	return null


## 剧情面板挂 HUD/UIRoot（640×384 + 整体放大），别挂 CanvasLayer —— 见 UiStyle.ui_layer。
func _hud() -> Node:
	return UiStyle.ui_layer(self)


# ---- 存档 ------------------------------------------------------------------

## 存档快照：已播过的支线 + 已解锁的旗标 + 章节标记 + 支线天的游标。
## 不存"正在播的那条"：读档时把当前对话关了重来，比恢复半截对话安全。
func snapshot() -> Dictionary:
	return {
		"played": _played.duplicate(),
		"unlocked": _unlocked.duplicate(),
		"chapters": _chapters.duplicate(),
		"story_day": _story_day,
	}


func restore(data: Dictionary) -> void:
	_played.clear()
	var played: Dictionary = data.get("played", {}) as Dictionary
	for key: Variant in played:
		_played[str(key)] = bool(played[key])
	_unlocked.clear()
	var unlocked: Dictionary = data.get("unlocked", {}) as Dictionary
	for key: Variant in unlocked:
		_unlocked[str(key)] = bool(unlocked[key])
	_chapters.clear()
	var chapters: Dictionary = data.get("chapters", {}) as Dictionary
	for key: Variant in chapters:
		_chapters[str(key)] = bool(chapters[key])
	_story_day = int(data.get("story_day", 1))
	_clear_arc_extras()
