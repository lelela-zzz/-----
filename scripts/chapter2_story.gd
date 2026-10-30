extends Node
## 第二章「月痕将熄」剧情导演（autoload：Chapter2Story）。
##
## 独立于第一章 ChapterStory：复用同一套 place / brew / travel / talk 推进模型
## （摆人等待交谈、离场后自动恢复、任务步打勾），但**不含**矿井史莱姆演出。
## 数据源：data/story_chapter2.json 的 beats。
##
## 幕类型（与第一章一致）：
##   · place 幕：玩家进入该场景时自动播（复用 story_dialogue.tscn）；
##   · talk 幕：带 npc + spawn，摆人进场等玩家按 E 交谈（更符合"走上前对话"）；
##   · brew 幕：库存出现指定酒（且符文已准许）才推进；
##   · travel 幕：不弹对话，直接结算 unlock/gained 并打钩跳过。
##
## 启动：第一章结束后（或营业额解锁）由外部调 begin()，默认从第 0 幕整章播。

signal beat_changed(index: int)
signal finished

const DATA_PATH: String = "res://data/story_chapter2.json"
const DIALOGUE_SCENE: String = "res://scenes/ui/story_dialogue.tscn"
const NPC_SCENE: String = "res://scenes/npc.tscn"
const NPC_DATA_PATH: String = "res://data/npcs.json"
const QID: String = "ch2_moon"

## beat id → 任务步骤文案（未列出的幕不计入任务步）。
const STEP_TEXT: Dictionary = {
	"ch2_tavern_eris": "听俄莉斯说明委托（寻找魔导石）",
	"ch2_tavern_emt": "与来自雪山的 EMT 会合",
	"ch2_eris_lifewater": "用缥色符文炼制生命之水",
	"ch2_brew_lifewater": "酿造具有净化效果的生命之水",
	"ch2_to_snow": "前往黑松山脉·雪山",
	"ch2_snow_meet_emt": "在雪山与 EMT 会合",
	"ch2_snow_avalanche": "穿过雪崩后的山道",
	"ch2_to_spring": "前往雪山深处的泉水",
	"ch2_spring_wiz": "在泉水边与维兹交谈",
	"ch2_spring_purify": "用生命之水净化泉水",
	"ch2_spring_take_stone": "在净化后的泉水中取出魔导石",
	"ch2_void_nymph": "在灰空间里与宁芙、林格相遇",
	"ch2_spring_wake": "在泉边醒来",
	"ch2_to_tavern": "带着魔导石回到银辉酒馆",
	"ch2_tavern_elaina": "回银辉酒馆安置伊蕾娜与伊卡洛斯",
	"ch2_tavern_iori": "迎接前来应聘的伊织",
}

const PLACE_SCENE: Dictionary = {
	"world": "res://scenes/world.tscn",
	"tavern_exterior": "res://scenes/tavern_exterior.tscn",
	"village": "res://scenes/village.tscn",
	"mine_entrance": "res://scenes/mine_entrance.tscn",
	"mine": "res://scenes/mine.tscn",
	"snow_mountain": "res://scenes/snow_mountain.tscn",
	"spring": "res://scenes/spring.tscn",
	"dark_space": "res://scenes/dark_space.tscn",
}

## 走不到的"脚本化"位置：只能由剧情导演 change_scene 进出，玩家没法用门走到
## （灰空间是意识空间，不在 map_graph 里）。进出它的幕自动切场景，其余幕仍靠玩家走。
const SCRIPTED_JUMP_PLACES: Dictionary = {
	"dark_space": true,
}

## 是否在「场景切换 / 库存变化 / 上一幕关闭」后自动推进。
var auto_advance: bool = true
## true = 摆人等待交谈；false = 带 npc 的幕也自动播（供回归用例沿用）。
var wait_for_talk: bool = true
## true = 带 "wait_day" 的幕必须等游戏时间真的跨到次日（伊织是第二天晌午来的）；
## false = 不管天数直接放行（供旧回归用例沿用）。
var require_next_day: bool = true

var _beats: Array = []
var _active: bool = false
var _done: bool = false
var _index: int = 0
var _playing: bool = false
var _last_scene: String = ""
var _panel: UiPanel = null
var _npc_defs: Dictionary = {}
var _npc_nodes: Array[Node] = []
## 本幕"叫来站定"的常驻游荡角色（老板娘等）：对话期间冻结、幕关闭时 resume_wander() 恢复。
var _held_npcs: Array[Node] = []
var _awaiting_talk: bool = false
## 缥色符文已获准（ch2_eris_lifewater 播完置真）。酿造生命之水必须等它，
## 否则序章随手酿的酒会提前满足酿造幕。
var _rune_granted: bool = false
## 脚本化跳转进行中：change_scene_to_file 是延迟到空闲帧才换的，这段窗口里
## _pump 会被反复调用；不加闸门就会连发多次 change_scene，把目标场景叠着换。
var _jumping: bool = false
## 上一幕播完时的游戏天数：带 "wait_day" 的幕要等 `_game_day() > _day_mark`。
var _day_mark: int = -1


func _ready() -> void:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("[Chapter2Story] 读不到 %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Chapter2Story] %s 不是合法 JSON" % DATA_PATH)
		return
	_beats = (parsed as Dictionary).get("beats", []) as Array
	_load_npc_defs()
	Inventory.changed.connect(_on_inventory)


func _load_npc_defs() -> void:
	_npc_defs.clear()
	var f: FileAccess = FileAccess.open(NPC_DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for entry: Variant in (parsed as Dictionary).get("npcs", []):
		if entry is Dictionary:
			var d: Dictionary = entry as Dictionary
			_npc_defs[str(d.get("id", ""))] = d


func is_active() -> bool:
	return _active and not _done


func is_done() -> bool:
	return _done


func index() -> int:
	return _index


func awaiting_talk() -> bool:
	return _awaiting_talk


func beat_count() -> int:
	return _beats.size()


func current_beat() -> Dictionary:
	if _index < 0 or _index >= _beats.size():
		return {}
	return _beats[_index] as Dictionary


## 彻底复位（测试窗口用）。
func reset() -> void:
	abort_current_beat()
	_active = false
	_done = false
	_index = 0
	_last_scene = ""
	_rune_granted = false
	_jumping = false
	_day_mark = -1


## 无副作用地撤掉当前正在播的对话：只关面板，不标记完成、不推进 index。
func abort_current_beat() -> void:
	if _panel != null and is_instance_valid(_panel):
		if _panel.closed.is_connected(_on_beat_closed):
			_panel.closed.disconnect(_on_beat_closed)
		_panel.close()
	_panel = null
	_playing = false
	_awaiting_talk = false
	_clear_beat_npcs()


## 由外部（第一章结束 / 营业额解锁）调用。幂等。
func begin(start_index: int = 0) -> void:
	if _active:
		return
	if _beats.is_empty():
		push_warning("[Chapter2Story] beats 为空，章节不启动")
		return
	_active = true
	_done = false
	_playing = false
	_awaiting_talk = false
	_rune_granted = false
	_index = clampi(start_index, 0, _beats.size() - 1)
	_last_scene = _scene_id()
	_day_mark = _game_day()
	_start_quest()


func _start_quest() -> void:
	QuestLog.add(QID, "第二章 · 月痕将熄", "月痕镇的泉水里藏着魔导石，也藏着一场将熄的月光。")
	for b: Variant in _beats:
		var bid: String = str((b as Dictionary).get("id", ""))
		if STEP_TEXT.has(bid):
			QuestLog.add_step(QID, str(STEP_TEXT[bid]))
	QuestLog.set_tracked(QID)
	_sync_objective()


func _process(_delta: float) -> void:
	if not is_active():
		return
	var sid: String = _scene_id()
	if sid != _last_scene:
		if _modal_open():
			return
		_last_scene = sid
		_jumping = false          # 场景真的换完了，闸门可以开了
		_recover_after_scene_change()
		if auto_advance:
			_pump()
		return
	if auto_advance and not _playing and not _awaiting_talk and not _modal_open():
		_pump()


## 换场景后收拾残局：面板/NPC 随旧场景释放，但 _playing/_awaiting_talk 是 autoload
## 变量不会跟着清；留成 true 会让 _pump 永久早退（第一章踩过的坑，这里同样兜住）。
func _recover_after_scene_change() -> void:
	if _panel != null and not is_instance_valid(_panel):
		_panel = null
		_playing = false
	_prune_npc_nodes()
	if not _awaiting_talk:
		return
	var b: Dictionary = current_beat()
	var want: String = str(PLACE_SCENE.get(str(b.get("place", "")), ""))
	if _scene_id() != want or not _npc_in_scene(str(b.get("npc", ""))):
		_awaiting_talk = false


func _prune_npc_nodes() -> void:
	var alive: Array[Node] = []
	for n: Node in _npc_nodes:
		if is_instance_valid(n):
			alive.append(n)
	_npc_nodes = alive


func _on_inventory() -> void:
	if auto_advance and is_active() and not _playing and not _modal_open():
		_pump()


func _modal_open() -> bool:
	return not get_tree().get_nodes_in_group("modal_ui").is_empty()


func _pump() -> void:
	if not is_active() or _playing:
		return
	if _awaiting_talk:
		return
	while _index < _beats.size():
		var b: Dictionary = _beats[_index] as Dictionary
		if str(b.get("place", "")) == "travel":
			_apply_side_effects(b)
			# travel 幕不弹对话，但任务步必须打钩，否则"前往…"永远○
			_mark_step_done(str(b.get("id", "")))
			_index += 1
			_day_mark = _game_day()
			_sync_objective()
			continue
		if not _beat_ready(b):
			# 人不在这一幕的场景里：若是灰空间这类走不到的场景，就脚本化跳过去
			_try_scripted_jump(b)
			return
		if _is_talk_beat(b):
			_spawn_beat_npc(b)
			_awaiting_talk = true
			beat_changed.emit(_index)
			return
		_play_beat(b)
		return
	_finish()


func _is_talk_beat(b: Dictionary) -> bool:
	if not wait_for_talk:
		return false
	if str(b.get("place", "")) == "travel":
		return false
	return str(b.get("npc", "")) != ""


func _beat_ready(b: Dictionary) -> bool:
	var brew: Variant = b.get("brew", null)
	if brew is Dictionary:
		# 酿造幕三条件：符文已准 + 酒已入库 + 人在酿造场景
		if not _rune_granted:
			return false
		if not Inventory.has(str((brew as Dictionary).get("wine", ""))):
			return false
		var bplace: String = str(b.get("place", "world"))
		return _scene_id() == str(PLACE_SCENE.get(bplace, ""))
	var place: String = str(b.get("place", ""))
	if _scene_id() != str(PLACE_SCENE.get(place, "")):
		return false
	# wait_day：该幕要等游戏时间真的跨到「上一幕播完的次日」才解锁
	# （伊织是"第二天晌午"来的，不能在当晚连播）。跨天由时钟自动推进，
	# _process 的每帧 _pump 会在 day 翻过去后自然放行。
	if bool(b.get("wait_day", false)) and require_next_day and _game_day() <= _day_mark:
		return false
	return true


## 当前游戏天数。以**当前场景的时钟**为准——场景树里可能残留旧场景的时钟
## （测试挂载/脚本跳转的孤儿实例），按"组里第一个"取会撞回旧天数；
## 灰空间等无 Clock 的场景退 GameClock 静态兜底（跨场景不退天）。
func _game_day() -> int:
	var scene: Node = get_tree().current_scene
	var clock: GameClock = (scene.get_node_or_null("Clock") as GameClock) \
			if scene != null else null
	if clock != null:
		return clock.day
	return GameClock._shared_day


## 本幕所在的场景走不到（灰空间）时，由导演直接切过去。
## 换场景后 _process 会检测到 sid 变化，再 _pump 一次，把这一幕真正播出来。
func _try_scripted_jump(b: Dictionary) -> void:
	if _jumping:
		return
	var target_place: String = str(b.get("place", ""))
	var here_place: String = _place_of_scene(_scene_id())
	if not bool(SCRIPTED_JUMP_PLACES.get(target_place, false)) \
			and not bool(SCRIPTED_JUMP_PLACES.get(here_place, false)):
		return
	var target_scene: String = str(PLACE_SCENE.get(target_place, ""))
	if target_scene == "" or target_scene == _scene_id():
		return
	# 幕上写了落点就走传送门那套静态变量，目标场景的 SceneBootstrap 会取走，
	# 于是「醒来」能落在泉边而不是地图默认入口。
	var sp: Variant = b.get("jump_spawn", null)
	if sp is Array and (sp as Array).size() >= 2:
		DoorArea.pending_position = Vector2(
				float((sp as Array)[0]), float((sp as Array)[1]))
		DoorArea.has_pending = true
	# 顺带把游戏时间带过去（同 DoorArea._travel 的做法）：跨场景不丢昼夜。
	# 灰空间里没有 Clock 节点不会消耗 pending_hour，所以进出的时间能原样带回来。
	var scene: Node = get_tree().current_scene
	var clock: Node = scene.get_node_or_null("Clock") if scene != null else null
	if clock != null:
		DoorArea.pending_hour = int(clock.get("hour"))
		DoorArea.pending_minute = int(clock.get("minute"))
	DoorArea.pending_target = target_scene
	_jumping = true
	get_tree().change_scene_to_file(target_scene)


## 场景文件 → place 名（PLACE_SCENE 的反查）。
func _place_of_scene(path: String) -> String:
	for k: String in PLACE_SCENE:
		if str(PLACE_SCENE[k]) == path:
			return k
	return ""


func _play_beat(b: Dictionary) -> void:
	_awaiting_talk = false
	_spawn_beat_npc(b)
	_face_cast(b)
	var hud: Node = UiStyle.ui_layer(self)
	var ps: PackedScene = load(DIALOGUE_SCENE) as PackedScene
	if hud == null or ps == null:
		push_warning("[Chapter2Story] 无法播放幕：hud=%s ps=%s" % [hud, ps])
		return
	var panel: UiPanel = ps.instantiate() as UiPanel
	panel.set("entries", b.get("entries", []))
	hud.add_child(panel)
	_panel = panel
	_playing = true
	panel.closed.connect(_on_beat_closed)
	beat_changed.emit(_index)


## 玩家与某个 NPC 交谈时由 Npc._open_dialogue 调用。
func try_talk(npc_id: String, _npc_node: Node) -> bool:
	if not is_active() or _playing:
		return false
	if _index < 0 or _index >= _beats.size():
		return false
	var b: Dictionary = _beats[_index] as Dictionary
	if str(b.get("npc", "")) != npc_id:
		return false
	_awaiting_talk = false
	_play_beat(b)
	return true


func _spawn_beat_npc(b: Dictionary) -> void:
	_place_npc(str(b.get("npc", "")), b.get("spawn", null), str(b.get("facing", "down")), b)
	var ex: Variant = b.get("extras", null)
	if ex is Array:
		for e: Variant in ex as Array:
			if e is Dictionary:
				var d: Dictionary = e as Dictionary
				_place_npc(str(d.get("npc", "")), d.get("spawn", null),
						str(d.get("facing", "down")), b, d)
	# 本幕人物到位后，把场景里其余正在游荡的常驻角色（老板娘等）一起站定，
	# 免得剧情对话时她们自顾自走掉；幕关闭时再 resume_wander() 恢复。
	_freeze_wanderers()


## 对话开始：本幕在场人物全部转向玩家（含被叫来的萃歌，免得她面朝外侧）。
func _face_cast(b: Dictionary) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var ids: Array[String] = []
	var nid: String = str(b.get("npc", ""))
	if nid != "":
		ids.append(nid)
	var ex: Variant = b.get("extras", null)
	if ex is Array:
		for e: Variant in ex as Array:
			if e is Dictionary:
				ids.append(str((e as Dictionary).get("npc", "")))
	for id: String in ids:
		var n: Node = _find_npc_node(id)
		if n != null and n.has_method("face_toward"):
			n.call("face_toward", player.global_position)


func _place_npc(nid: String, sp: Variant, facing: String, b: Dictionary,
		place_extra: Dictionary = {}) -> void:
	if nid == "":
		return
	if sp is Vector2:
		sp = [(sp as Vector2).x, (sp as Vector2).y]
	if not (sp is Array) or (sp as Array).size() < 2:
		return
	if (_npc_defs.get(nid, {}) as Dictionary).is_empty():
		push_warning("[Chapter2Story] 幕 %s 指定的 NPC 未知：%s" % [str(b.get("id", "")), nid])
		return
	if _npc_in_scene(nid):
		# 已存在（如酒馆常驻的萃歌）：这一幕若指定了位置，就把她挪过来并站定参与对话，
		# 而不是让老板娘的游荡逻辑继续"自顾自走"。
		var ex: Node = _find_npc_node(nid)
		if ex != null and sp is Array and ex.has_method("hold_at"):
			ex.call("hold_at", Vector2(float((sp as Array)[0]), float((sp as Array)[1])))
			if not _held_npcs.has(ex):
				_held_npcs.append(ex)
		return
	var scene: Node = get_tree().current_scene
	var sorted: Node = scene.get_node_or_null("Sorted") if scene != null else null
	if sorted == null:
		return
	var ps: PackedScene = load(NPC_SCENE) as PackedScene
	if ps == null:
		return
	var npc: Node = ps.instantiate()
	npc.name = "Npc_beat_" + nid
	var place: Dictionary = {
		"scene": "world",
		"pos": sp,
		"facing": facing,
		"wander": 0.0,
	}
	# extra 上的附加键（no_interact 等）透传给 Npc.configure。
	for k: String in place_extra:
		if k != "npc" and k != "spawn" and k != "offset" and not place.has(k):
			place[k] = place_extra[k]
	npc.call("configure", _npc_defs[nid], place)
	sorted.add_child(npc)
	_npc_nodes.append(npc)


func _clear_beat_npcs() -> void:
	# 先让被剧情"叫来站定"的常驻游荡角色恢复原来的巡逻/游荡
	for n: Node in _held_npcs:
		if is_instance_valid(n) and n.has_method("resume_wander"):
			n.call("resume_wander")
	_held_npcs.clear()
	for n: Node in _npc_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_npc_nodes.clear()


func _npc_in_scene(id: String) -> bool:
	return _find_npc_node(id) != null


## 场景里这个 NPC 的节点（找不到返回 null）。
func _find_npc_node(id: String) -> Node:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return n
	return null


## 本幕播出时，把场景里所有正在游荡的常驻角色（老板娘等）一起站定，
## 免得剧情对话中她们自顾自走掉；这些人登记到 _held_npcs，幕关闭时 resume_wander()。
## 顾客（Customer extends Npc）有自己的逻辑、且会自行离场，不参与冻结。
func _freeze_wanderers() -> void:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if _held_npcs.has(n):
			continue
		if n.has_method("wants_service"):
			continue   # 顾客不冻
		if n.has_method("is_wandering") and n.call("is_wandering"):
			n.call("hold")
			_held_npcs.append(n)


func _on_beat_closed() -> void:
	_playing = false
	_panel = null
	_awaiting_talk = false
	_clear_beat_npcs()
	if _index < _beats.size():
		var b: Dictionary = _beats[_index] as Dictionary
		_apply_side_effects(b)
		if str(b.get("id", "")) == "ch2_eris_lifewater":
			_rune_granted = true   # 缥色符文准许后，酿造幕才可触发
		_mark_step_done(str(b.get("id", "")))
		_index += 1
		_day_mark = _game_day()
	_sync_objective()
	if _index >= _beats.size():
		_finish()
	elif auto_advance:
		_pump()


## 手动推进一步（测试窗口用）。
func advance_now() -> bool:
	if not is_active() or _playing or _modal_open():
		return false
	var before: int = _index
	_pump()
	return _playing or _index != before or _done


func _apply_side_effects(b: Dictionary) -> void:
	var u: Variant = b.get("unlock", null)
	if u is Dictionary:
		var flag: String = str((u as Dictionary).get("flag", ""))
		if flag != "":
			SideStory.unlock(flag)
		var toast: String = str((u as Dictionary).get("toast", ""))
		if toast != "":
			_toast(toast)
	var gained: Variant = b.get("gained", null)
	if gained is Array:
		for g: Variant in gained as Array:
			_toast("获得：%s" % str(g))


func _mark_step_done(beat_id: String) -> void:
	if not STEP_TEXT.has(beat_id):
		return
	var i: int = 0
	for b: Variant in _beats:
		var bid: String = str((b as Dictionary).get("id", ""))
		if STEP_TEXT.has(bid):
			if bid == beat_id:
				QuestLog.set_step_done(QID, i, true)
				return
			i += 1


func _sync_objective() -> void:
	if _index >= _beats.size():
		return
	var b: Dictionary = _beats[_index] as Dictionary
	var dest: Dictionary = b.get("dest", {}) as Dictionary
	if not dest.is_empty():
		QuestLog.set_dest(QID, dest)


func _finish() -> void:
	if _done:
		return
	_done = true
	_clear_beat_npcs()
	QuestLog.complete(QID)
	_toast("第二章 · 月痕将熄 —— 完")
	finished.emit()


func _scene_id() -> String:
	var s: Node = get_tree().current_scene
	return s.scene_file_path if s != null else ""


func _toast(text: String) -> void:
	if Story != null and Story.has_method("_toast"):
		Story._toast(text, 4.0)


# ---- 存档 ------------------------------------------------------------------

## 存档快照：第二章推进状态。_awaiting_talk 不存 —— 读档后 _recover_after_scene_change
## 会按"这一幕的场景 / 人还在不在"重新判定，替玩家恢复一个"正等人说话"的假状态反而会卡住。
func snapshot() -> Dictionary:
	return {
		"active": _active,
		"done": _done,
		"index": _index,
		"rune_granted": _rune_granted,
		"day_mark": _day_mark,
	}


func restore(data: Dictionary) -> void:
	_active = bool(data.get("active", false))
	_done = bool(data.get("done", false))
	_index = clampi(int(data.get("index", 0)), 0, maxi(0, _beats.size() - 1))
	_rune_granted = bool(data.get("rune_granted", false))
	_day_mark = int(data.get("day_mark", -1))
	_playing = false
	_awaiting_talk = false
	_panel = null
	_last_scene = ""
