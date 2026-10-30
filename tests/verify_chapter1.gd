extends Node
## 第一章「雾凇无虞」剧情导演验收（ChapterStory）：
##   1) data/story_chapter1.json 骨架完整：13 幕、每幕有 id/place/entries、next 链首尾相连；
##   2) 没人接委托时导演不启动（别的回归用例不该被它惊动）；
##   3) begin() 后：发 ch1_frost 任务并自动追踪；
##   4) 章节进行中抑制支线访客（spawn_specs 空、try_play 不接管），但 pending 查询照常；
##   5) 按场景自动播幕：进酒馆连播 3 幕 → 卡在「酿造暖身姜酒」→ 有酒才继续；
##   6) travel 幕直接结算：解锁「黑松山脉·矿道入口」地图去处；
##   7) 走完 13 幕：任务完成、导演收尾、被本章覆盖的支线标记已播、访客恢复登场。
##
## 为什么这样测：本章靠「进场景自动播 + 酿造完成」推进，不依赖任何 NPC 在场，
## 所以用例也是"切场景 / 改库存"两步驱动，和玩家真实路径一致。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_chapter1.tscn --quit-after 9000

const WORLD: String = "res://scenes/world.tscn"
const TAVERN_EXTERIOR: String = "res://scenes/tavern_exterior.tscn"
const VILLAGE: String = "res://scenes/village.tscn"
const MINE_ENTRANCE: String = "res://scenes/mine_entrance.tscn"
const MINE: String = "res://scenes/mine.tscn"

const QID: String = "ch1_frost"

var passed: int = 0
var failed: int = 0
var _scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	ChapterStory.wait_for_talk = false   # 本回归沿用"进场景自动播"的旧路径
	QuestLog.reset()
	# 先等一帧再往 root 挂场景（_ready 这条链还在跑时 root 正忙着布置子节点）
	await get_tree().process_frame

	_check_data()
	await _run()

	QuestLog.reset()
	print("[chapter1] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 数据 -------------------------------------------------------------

func _check_data() -> void:
	var beats: Array = ChapterStory._beats
	_report("第一章数据 13 幕", beats.size() == 13, "beats=%d" % beats.size())

	var bad: String = ""
	var ids: Array[String] = []
	var bad_place: String = ""
	for b: Variant in beats:
		var beat: Dictionary = b as Dictionary
		var id: String = str(beat.get("id", ""))
		var place: String = str(beat.get("place", ""))
		if id == "" or place == "":
			bad += "%s(缺字段) " % id
		if (beat.get("entries", []) as Array).is_empty():
			bad += "%s(无台词) " % id
		if ids.has(id):
			bad += "%s(重复) " % id
		ids.append(id)
		if place != "travel" and not ChapterStory.PLACE_SCENE.has(place):
			bad_place += "%s→%s " % [id, place]
	_report("每幕都有 id/place/entries，且 id 唯一", bad == "", bad)
	_report("place 都是已知场景或 travel", bad_place == "", bad_place)

	# next 链：第 i 幕的 next 必须等于第 i+1 幕的 id，末幕为 null
	var chain: String = ""
	for i: int in beats.size():
		var nxt: Variant = (beats[i] as Dictionary).get("next", null)
		var want: Variant = null
		if i + 1 < beats.size():
			want = str((beats[i + 1] as Dictionary).get("id", ""))
		if nxt != want:
			chain += "%d:%s≠%s " % [i, str(nxt), str(want)]
	_report("13 幕 next 链首尾相连（末幕 next=null）", chain == "", chain)


# ---- 2~7. 跑一遍 ---------------------------------------------------------

func _run() -> void:
	_report("接委托前导演不启动", not ChapterStory.is_active(),
			"active=%s" % ChapterStory.is_active())

	# 导演启动（真实链路由 Story._start_snow_logistics 调用，这里直接调）
	ChapterStory.begin()
	await _tick()
	_report("begin() 后章节启动", ChapterStory.is_active(),
			"active=%s" % ChapterStory.is_active())
	_report("begin() 后发 ch1_frost 任务并自动追踪",
			QuestLog.has(QID) and QuestLog.is_tracked(QID),
			"has=%s tracked=%s" % [QuestLog.has(QID), QuestLog.tracked_id()])
	_report("begin() 后从第 2 幕开始（第 1 幕凯瑟琳委托由 Story 播过）",
			_beat_id() == "ch1_tavern_hartfilia", "beat=%s" % _beat_id())

	# 章节进行中抑制支线：临时让支线系统真的"活着"，才验得出抑制
	StoryDirector.force_disable = false
	Story.stage = StoryDirector.Stage.OPEN
	# 第一天不出支线（SideStory.FIRST_STORY_DAY = 2），这里直接把剧情天数推到第 2 天
	SideStory._story_day = 2
	SideStory.activate_chapter("snow_logistics")   # Story._start_snow_logistics 里同一句
	var alive: bool = SideStory.active()
	var pending: bool = not SideStory.pending_for("broker_chiss").is_empty()
	_report("支线系统此刻是活的（pending 查得到）", alive and pending,
			"active=%s pending=%s day=%d chiss_played=%s" % [
				alive, pending, SideStory.day(), SideStory.has_played("chiss_brewing_machine")])
	_report("章节进行中不摆支线访客", SideStory.spawn_specs().is_empty(),
			"specs=%s" % str(SideStory.spawn_specs()))
	_report("章节进行中支线不抢 E 交互", not SideStory.try_play("broker_chiss", null),
			"played=%s" % SideStory.try_play("broker_chiss", null))
	StoryDirector.force_disable = true

	# 酒馆外：哈特菲利亚；进酒馆后：奇斯 → 俄莉斯
	await _mount(TAVERN_EXTERIOR)
	var p: Node = await _await_panel()
	_report("酒馆外自动播第 2 幕（哈特菲利亚）",
			p != null and _beat_id() == "ch1_tavern_hartfilia",
			"beat=%s panel=%s" % [_beat_id(), p != null])
	await _close_current(p)
	await _mount(WORLD)
	var p2: Node = await _await_panel()
	_report("进酒馆后接第 3 幕（奇斯给绯色符文）",
			p2 != null and _beat_id() == "ch1_chiss_rune",
			"beat=%s panel=%s" % [_beat_id(), p2 != null])
	await _close_current(p2)
	var p3: Node = await _await_panel()
	_report("关掉后接第 4 幕（俄莉斯准许用符文）",
			p3 != null and _beat_id() == "ch1_eris_permission",
			"beat=%s panel=%s" % [_beat_id(), p3 != null])
	await _close_current(p3)

	# 第 5 幕是酿造幕：没有暖身姜酒就不该播
	var no_panel: Node = await _await_panel(10)
	_report("没有暖身姜酒时卡在酿造幕（不空放台词）",
			no_panel == null and _beat_id() == "ch1_brew_antifreeze",
			"beat=%s panel=%s" % [_beat_id(), no_panel != null])

	Inventory.add("wine_warm_ginger", 1)
	var bp: Node = await _await_panel()
	_report("库存出现暖身姜酒后，酿造幕播放",
			bp != null and _beat_id() == "ch1_brew_antifreeze",
			"beat=%s panel=%s" % [_beat_id(), bp != null])
	await _close_current(bp)
	await _tick()
	var still_none: Node = await _await_panel(6)
	_report("酿完后下一幕=去集市（凯瑟琳求救），且只在集市播",
			_beat_id() == "ch1_catherine_injured" and still_none == null,
			"beat=%s panel=%s" % [_beat_id(), still_none != null])
	_report("任务目的地看着集市凯瑟琳",
			str(QuestLog.dest_of(QID).get("scene", "")) == VILLAGE,
			"dest=%s" % str(QuestLog.dest_of(QID)))

	# 进集市：凯瑟琳求救 → 绯村恢复 → travel 解锁矿道入口
	await _mount(VILLAGE)
	var cp: Node = await _await_panel()
	_report("进集市播第 6 幕（凯瑟琳）",
			cp != null and _beat_id() == "ch1_catherine_injured",
			"beat=%s panel=%s" % [_beat_id(), cp != null])
	await _close_current(cp)
	var hp: Node = await _await_panel()
	_report("接着播第 7 幕（绯村恢复）",
			hp != null and _beat_id() == "ch1_himura_recover",
			"beat=%s panel=%s" % [_beat_id(), hp != null])
	await _close_current(hp)
	await _tick()
	_report("第 8 幕 travel 直接结算：解锁「矿道入口」",
			SideStory.is_unlocked("mine_entrance"),
			"unlocked=%s" % SideStory.is_unlocked("mine_entrance"))
	# travel 幕不弹对话（在 _pump 里被跳过），但它的任务步必须打钩，
	# 否则任务栏里「前往黑松山脉·矿道入口」永远是 ○（玩家以为剧情坏了）。
	_report("travel 幕的任务步也打钩（前往矿道入口）",
			_step_done("前往黑松山脉·矿道入口"),
			"steps=%s" % str(_step_texts()))
	_report("解锁后下一幕=矿道入口的西蒙",
			_beat_id() == "ch1_mine_entrance_simon", "beat=%s" % _beat_id())

	# M 地图面板：解锁后该去处要露脸
	var mp: MapPanel = MapPanel.new()
	add_child(mp)
	await _tick()
	var ids: Array[String] = []
	for r: Dictionary in mp._rows:
		ids.append(str((r["place"] as Dictionary).get("id", "")))
	_report("M 地图出现「黑松山脉·矿道入口」", ids.has("mine_entrance"), str(ids))
	mp.queue_free()
	await _tick()

	# 进矿道入口：西蒙 → 哈特菲利亚给 taurus → travel 跳过 → 矿井
	await _mount(MINE_ENTRANCE)
	# 这一幕哈特菲利亚也有台词（她留在这里照顾队员），必须在场 —— 只有西蒙站着的话，
	# 玩家会看到"画外音"，就是"对应角色没有正常显示出来"。
	_report("矿道入口一幕把同场人物都摆出来（西蒙 + 哈特菲利亚）",
			_npc_present("miner_simon") and _npc_present("explorer_lucy"),
			"simon=%s lucy=%s" % [_npc_present("miner_simon"), _npc_present("explorer_lucy")])
	var sp: Node = await _await_panel()
	_report("进矿道入口播第 10 幕（西蒙）",
			sp != null and _beat_id() == "ch1_mine_entrance_simon",
			"beat=%s panel=%s" % [_beat_id(), sp != null])
	await _close_current(sp)
	var tp: Node = await _await_panel()
	_report("接着播第 11 幕（哈特菲利亚交给 taurus）",
			tp != null and _beat_id() == "ch1_hartfilia_taurus",
			"beat=%s panel=%s" % [_beat_id(), tp != null])
	await _close_current(tp)
	await _tick()
	_report("第 12 幕 travel 被跳过 → 下一幕=矿井里的爱德华",
			_beat_id() == "ch1_mine_edward", "beat=%s" % _beat_id())

	# 矿井：爱德华 → 回酒馆收尾
	await _mount(MINE)
	var ep: Node = await _await_panel()
	_report("进矿井播第 13 幕（钢之炼金术士）",
			ep != null and _beat_id() == "ch1_mine_edward",
			"beat=%s panel=%s" % [_beat_id(), ep != null])
	await _close_current(ep)
	await _tick()

	await _mount(WORLD)
	var rp: Node = await _await_panel()
	_report("回酒馆播末幕（沉睡的粉发少女）",
			rp != null and _beat_id() == "ch1_return_tavern",
			"beat=%s panel=%s" % [_beat_id(), rp != null])
	await _close_current(rp)
	await _tick()
	await _tick()

	_report("走完 13 幕 → 任务完成", QuestLog.is_complete(QID),
			"complete=%s" % QuestLog.is_complete(QID))
	_report("走完 13 幕 → 导演收尾（is_active=false）", not ChapterStory.is_active(),
			"active=%s" % ChapterStory.is_active())
	_report("收尾后不再追踪第一章", not QuestLog.is_tracked(QID),
			"tracked=%s" % QuestLog.tracked_id())
	_report("被本章覆盖的支线标记为已播（哈特菲利亚/奇斯）",
			SideStory.has_played("hartfilia_snow_intro")
			and SideStory.has_played("chiss_brewing_machine"),
			"hartfilia=%s chiss=%s" % [
				SideStory.has_played("hartfilia_snow_intro"),
				SideStory.has_played("chiss_brewing_machine")])
	# 本章把前六条支线都吃掉之后，能摆进店的只剩更晚放送的访客（爱蜜莉雅第 7 天、
	# 维兹第 8 天）—— 所以要把剧情天数推到那时候，才验得到"访客恢复登场"。
	SideStory._story_day = 8
	_report("收尾后支线访客恢复登场", not SideStory.spawn_specs().is_empty(),
			"specs=%d" % SideStory.spawn_specs().size())


# ---- 工具 ---------------------------------------------------------------

## 当前该做的那一幕的 id（播放中 = 正在播的那幕）。
func _beat_id() -> String:
	return str(ChapterStory.current_beat().get("id", ""))


## 任务里某一步是否已打钩（按文案前缀匹配，文案改字不影响判据）。
func _step_done(prefix: String) -> bool:
	var q: Dictionary = QuestLog.quest(QID)
	for s: Variant in q.get("steps", []):
		var d: Dictionary = s as Dictionary
		if str(d.get("text", "")).begins_with(prefix):
			return bool(d.get("done", false))
	return false


func _step_texts() -> Array[String]:
	var out: Array[String] = []
	var q: Dictionary = QuestLog.quest(QID)
	for s: Variant in q.get("steps", []):
		var d: Dictionary = s as Dictionary
		out.append(("✓" if bool(d.get("done", false)) else "○") + str(d.get("text", "")))
	return out


## 场景里此刻站着这个 npc 吗。
func _npc_present(id: String) -> bool:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return true
	return false


## 把某张图挂成 current_scene，导演靠它判断"玩家现在在哪"。
func _mount(path: String) -> Node:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	var ps: PackedScene = load(path) as PackedScene
	_scene = ps.instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	await _tick()
	return _scene


## 等最多 max_frames 帧，直到出现一个可用的模态面板（章节对话）。没有就返回 null。
func _await_panel(max_frames: int = 40) -> Node:
	for i: int in max_frames:
		for n: Node in get_tree().get_nodes_in_group("modal_ui"):
			if is_instance_valid(n) and not n.is_queued_for_deletion() and n is UiPanel:
				return n
		await get_tree().process_frame
	return null


## 只关掉**这一个**面板（连播时下一幕会在同一帧里冒出来，别把它一起吃掉）。
func _close_current(panel: Node) -> void:
	if panel == null:
		return
	var guard: int = 0
	while is_instance_valid(panel) and not panel.is_queued_for_deletion() and guard < 120:
		_push_key(KEY_E)
		await get_tree().process_frame
		await get_tree().process_frame
		guard += 1
	await _tick()


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


## 等两帧：一帧让面板/场景 _ready 跑完，一帧让导演 _process 推进。
func _tick() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
