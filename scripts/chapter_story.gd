extends Node
## 第一章「雾凇无虞」剧情导演（autoload：ChapterStory）。
##
## 数据源：data/story_chapter1.json 的 beats（由 Story 在玩家于凯瑟琳处接委托时
## 调 begin() 启动）。每一幕按 place / brew / travel 三类推进：
##   · place 幕：玩家进入该场景时自动弹出多说话人剧情（复用 story_dialogue.tscn）；
##   · brew 幕：库存里出现指定酒（暖身姜酒）即推进；
##   · travel 幕：不弹对话，直接结算副作用（解锁矿道入口等）并跳过。
##
## 为什么用「按场景进入自动播放」而不是「找 NPC 对话」：
##  本章的关键人物（哈特菲利亚/奇斯/俄莉斯/西蒙）没有稳定驻场位置，靠随机顾客
##  或支线访客生成，不可靠；自动播放对谁在场没有依赖，任何场景都稳。
##
## 章节进行中会抑制 SideStory 的支线访客与支线播放（见 side_story.gd），
## 免得同一段剧情在访客线里再放一遍；章节结束后把被覆盖的支线标记为已播。
##
## 与回归的关系：默认 _active=false，只有 Story 真正接取委托（force_disable=false）
## 才会 begin()，所以 verify_prologue / verify_sidestory 等用例不会被它惊动。

signal beat_changed(index: int)
signal finished

const DATA_PATH: String = "res://data/story_chapter1.json"
const DIALOGUE_SCENE: String = "res://scenes/ui/story_dialogue.tscn"
const QID: String = "ch1_frost"
const NPC_SCENE: String = "res://scenes/npc.tscn"
const NPC_DATA_PATH: String = "res://data/npcs.json"

## ---- 矿井史莱姆演出（挂在矿井幕 ch1_mine_edward 上）--------------------------
## 这一幕的台词本就写了"满地道史莱姆 / 姜酒消融 / 史莱姆消失 / 你的酒杀死了史莱姆"，
## 这里把对应视觉实体接进去：进场摆一地存活史莱姆 → 对话开始朝二人靠近 →
## 讲到"姜酒杀死史莱姆"时逐只崩解 → 结束时场内只剩粘液尸体。
const MINE_BEAT_ID: String = "ch1_mine_edward"
const MINE_SCENE: String = "res://scenes/mine.tscn"
const SLIME_SCENE: String = "res://scenes/slime.tscn"
## 这一幕的**站位**：主角与爱德华并排站在洞穴里。
## 原来爱德华站在竖井里、主角在他上方，两人隔着一段距离，史莱姆也只能挤在
## 一条 40px 宽的窄道里 → 看着又散不开又不像"被包围"。挪到洞穴中央后两人并肩，
## 四周才有地方让史莱姆围成一圈。
## y 从 456 挪到 520：洞穴的地面其实在 y≈430~605 这一段（史莱姆的身子有 58px 高，
## 站在 y=456 时上半身会顶进上方的岩壁），整体下移后才整只都落在石头外面。
const MINE_STAGE_EDWARD: Vector2 = Vector2(486, 520)
const MINE_STAGE_PLAYER: Vector2 = Vector2(534, 520)
## 包围圈：7 只按角度均分站在这个半径上，另加一点抖动，免得像军训排队。
## 92 是"整只精灵框都在地面上"前提下能撑住的最大圈（再大，最下面那两个点就
## 顶到 y≈608 的矮石块）：相邻两只中心距 69~85px，相对 55px 宽的史莱姆留得开。
const MINE_SLIME_RING: float = 92.0
const MINE_SLIME_RING_JITTER: float = 4.0
const MINE_SLIME_ANGLE_JITTER: float = 0.05
## 洞穴里的投放点（同样按精灵框校验，整只都在地面上），大致绕着两人站成一圈。
const MINE_SLIME_SPAWNS: Array = [
	Vector2(425, 535), Vector2(596, 535), Vector2(450, 445),
	Vector2(572, 445), Vector2(452, 595), Vector2(568, 595),
	Vector2(510, 602),
]
## 台词推进到第几句开始"姜酒杀死史莱姆"（0 基；第 3 句西蒙说姜酒消掉了一整片）。
const SLIME_KILL_ENTRY: int = 3
## 摆放时用的**精灵框**尺寸（脚底 = 原点，身子往上是正的）。
## 关键：判定"会不会埋进岩壁"必须用整个精灵框，不能用脚下那 13px 的小圆 ——
## 否则就会出现"脚明明踩在地上、半个身子却插在石头里"的观感。
const SLIME_HALF_W: float = 28.0
const SLIME_HEIGHT: float = 58.0

## beat id → 任务步骤文案（未列出的幕不计入任务步）。
const STEP_TEXT: Dictionary = {
	"ch1_tavern_hartfilia": "回银辉酒馆，听哈特菲利亚说明委托",
	"ch1_brew_antifreeze": "用符文酿造抗寒的暖身姜酒",
	"ch1_catherine_injured": "带抗寒姜酒去集市找凯瑟琳",
	"ch1_to_mine": "前往黑松山脉·矿道入口",
	"ch1_mine_entrance_simon": "在矿道入口与西蒙交谈",
	"ch1_mine_edward": "深入矿井，支援钢之炼金术士",
	"ch1_return_tavern": "回银辉酒馆休息",
}

const PLACE_SCENE: Dictionary = {
	"world": "res://scenes/world.tscn",
	"tavern_exterior": "res://scenes/tavern_exterior.tscn",
	"village": "res://scenes/village.tscn",
	"mine_entrance": "res://scenes/mine_entrance.tscn",
	"mine": "res://scenes/mine.tscn",
}

## 章节结束后，这些已被本章覆盖的支线不再作为访客重播。
const SUPERSEDED_ARCS: Array[String] = [
	"hartfilia_snow_intro", "chiss_brewing_machine", "eris_artifact_runes",
	"himura_otherworld", "edward_philosopher_stone", "simon_drill",
]

## 是否在「场景切换 / 库存变化 / 上一幕关闭」后自动推进下一幕。
## 正式游戏必须保持 true（玩家走进场景就播、酿完酒就播）；
## 测试窗口把它置 false，改用 advance_now() 手动触发，免得切场景就强制弹对话。
var auto_advance: bool = true

var _beats: Array = []
var _active: bool = false
var _done: bool = false
var _index: int = 0
var _playing: bool = false
var _last_scene: String = ""
## 正在播的对话面板（用于复位/切场景时安全关闭，避免面板与状态错位）。
var _panel: UiPanel = null
## NPC 定义表 + 本幕摆进场景的人物节点（幕数据带 "npc" 时用）。
var _npc_defs: Dictionary = {}
var _npc_nodes: Array[Node] = []
## 本幕"叫来站定"的常驻游荡角色（老板娘等）：对话期间冻结、幕关闭时 resume_wander() 恢复。
var _held_npcs: Array[Node] = []
## 本场景里的史莱姆实体（矿井幕投放；不随幕关闭释放，好让尸体留在原地）。
var _slime_nodes: Array[Node] = []
var _slimes_killed: bool = false
## 当前幕已把人物摆进场景、正等玩家按 E 交谈。
var _awaiting_talk: bool = false
## 俄莉斯已准许使用绯色符文（第 4 幕 ch1_eris_permission 播完置真）。
## 酿造抗寒姜酒必须等它——否则玩家序章随手酿的姜酒会提前满足酿造幕。
var _rune_granted: bool = false
## true = 摆人等待交谈（正式流程）；false = 带 npc 的幕也自动播（供旧回归用例沿用）。
var wait_for_talk: bool = true


func _ready() -> void:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("[ChapterStory] 读不到 %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[ChapterStory] %s 不是合法 JSON" % DATA_PATH)
		return
	_beats = (parsed as Dictionary).get("beats", []) as Array
	_load_npc_defs()
	Inventory.changed.connect(_on_inventory)


## 读 npcs.json：幕数据里写了 "npc":"xxx" 时，按这里的定义把这个人物摆进场景。
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


## 彻底复位（测试窗口用）：先收掉还在播的对话面板，再清空内部状态，下次 begin() 可重放整章。
## 任务数据由调用方（测试窗口）决定是否 QuestLog.reset()。
func reset() -> void:
	abort_current_beat()
	_active = false
	_done = false
	_index = 0
	_last_scene = ""
	_rune_granted = false
	_slime_nodes.clear()
	_slimes_killed = false


## 无副作用地撤掉当前正在播的对话：只关面板，不标记完成、不推进 index。
## 测试窗口切场景时用它 —— 既不会强制弹新对话，也不会把半途的这一幕偷偷算作已完成。
func abort_current_beat() -> void:
	if _panel != null and is_instance_valid(_panel):
		# 先断开 closed，免得 close() 触发 _on_beat_closed 把 index 推进
		if _panel.closed.is_connected(_on_beat_closed):
			_panel.closed.disconnect(_on_beat_closed)
		_panel.close()
	_panel = null
	_playing = false
	_awaiting_talk = false
	_clear_beat_npcs()


## 当前幕序号（0 基，供调试/测试读）。
func index() -> int:
	return _index


## 章节是否已收尾（所有幕走完）。
func is_done() -> bool:
	return _done


## 由 Story 在玩家接取雪山委托后调用。幂等。
## [param start_index] 从第几幕开始（默认 1：第 0 幕凯瑟琳委托由 Story 接取时播放；
##   测试窗口传 0 可从委托幕整章重放）。
func begin(start_index: int = 1) -> void:
	if _active:
		return
	if _beats.is_empty():
		push_warning("[ChapterStory] beats 为空，章节不启动")
		return
	_active = true
	_done = false
	_playing = false
	_awaiting_talk = false
	_rune_granted = false
	_index = clampi(start_index, 0, _beats.size() - 1)
	_last_scene = _scene_id()
	_start_quest()


func _start_quest() -> void:
	QuestLog.add(QID, "第一章 · 雾凇无虞", "雪山科考队的委托：备好抗寒的酒，随队进山。")
	for b: Variant in _beats:
		var beat: Dictionary = b as Dictionary
		var bid: String = str(beat.get("id", ""))
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
			return   # 场景确实换了（比如刚进门），先让玩家把手上那段话读完，下一帧再说
		_last_scene = sid
		_recover_after_scene_change()
		if auto_advance:
			_pump()
		return
	# 场景没变、也没人正在说话/等交谈：条件可能刚满足（比如刚关掉酿造面板、酒已入库），
	# 这里补一次推进 —— 否则"面板关掉"不是场景变化，酿造幕就再没人顶出来。
	if auto_advance and not _playing and not _awaiting_talk and not _modal_open():
		_pump()


## 换场景后收拾残局。为什么必须有：
## 对话面板挂在「当前场景」的 HUD/UIRoot 下，玩家一旦在播对话/等人交谈时踩门，
## 面板和摆进来的 NPC 都随旧场景一起被释放 —— 但 _playing / _awaiting_talk 是
## 本 autoload 的变量，不会跟着清。留成 true 会让 _pump 永久早退：
## 剧情再也不推进、下一幕该登场的人永远不出现（矿道入口"西蒙不见、任务不打钩"就是这个）。
func _recover_after_scene_change() -> void:
	if _panel != null and not is_instance_valid(_panel):
		_panel = null
		_playing = false
	_prune_npc_nodes()
	_prune_slime_nodes()
	if not _awaiting_talk:
		return
	# 人已随旧场景消失（或本幕压根不在这个场景）→ 取消"等交谈"，回到该场景时重新登场。
	var b: Dictionary = current_beat()
	var want: String = str(PLACE_SCENE.get(str(b.get("place", "")), ""))
	if _scene_id() != want or not _npc_in_scene(str(b.get("npc", ""))):
		_awaiting_talk = false


## 清掉已被旧场景释放的 NPC 引用（否则 _clear_beat_npcs 会反复碰无效节点）。
func _prune_npc_nodes() -> void:
	var alive: Array[Node] = []
	for n: Node in _npc_nodes:
		if is_instance_valid(n):
			alive.append(n)
	_npc_nodes = alive


func _on_inventory() -> void:
	# 只在等待「酿造完成」时被库存变化推动；播对话中不打断。
	if auto_advance and is_active() and not _playing and not _modal_open():
		_pump()


## 有没有别的面板开着（对话/商店/地图…）。章节幕不该在别人台词中途插播。
func _modal_open() -> bool:
	return not get_tree().get_nodes_in_group("modal_ui").is_empty()


## 推进：travel 幕直接结算并跳过；"摆人交谈"幕只摆出人物、等玩家去对话；
## 其余幕（酿造/旁白）自动播。播完靠 _on_beat_closed 续。
func _pump() -> void:
	if not is_active() or _playing:
		return
	if _awaiting_talk:
		return   # 人已经摆好、在等玩家过去按 E，别重复推进
	while _index < _beats.size():
		var b: Dictionary = _beats[_index] as Dictionary
		if str(b.get("place", "")) == "travel":
			_apply_side_effects(b)
			# travel 幕不弹对话（被跳过），但它的任务步必须打钩，否则"前往矿道入口"永远○
			_mark_step_done(str(b.get("id", "")))
			_index += 1
			_sync_objective()
			continue
		if not _beat_ready(b):
			return
		if _is_talk_beat(b):
			# 人物登场，但不自动开口 —— 等玩家走到他身边按 E
			_spawn_beat_npc(b)
			_awaiting_talk = true
			beat_changed.emit(_index)
			return
		_play_beat(b)
		return
	_finish()


## 这一幕是否"摆人等待交谈"：带 npc 且不是 travel（酿造/旁白幕没有 npc，自动播）。
func _is_talk_beat(b: Dictionary) -> bool:
	if not wait_for_talk:
		return false
	if str(b.get("place", "")) == "travel":
		return false
	return str(b.get("npc", "")) != ""


## 该幕是否有角色正在场景里等玩家交谈。
func awaiting_talk() -> bool:
	return _awaiting_talk


func _beat_ready(b: Dictionary) -> bool:
	var brew: Variant = b.get("brew", null)
	if brew is Dictionary:
		# 酿造幕三条件缺一不可：
		#   1) 符文已获准（俄莉斯放开绯色符文，避免序章早期酿的酒提前触发）
		#   2) 酒已入库
		#   3) 人在酿造场景（锅所在），否则会在集市/雪山上莫名弹酿造台词
		if not _rune_granted:
			return false
		if not Inventory.has(str((brew as Dictionary).get("wine", ""))):
			return false
		var bplace: String = str(b.get("place", "world"))
		return _scene_id() == str(PLACE_SCENE.get(bplace, ""))
	var place: String = str(b.get("place", ""))
	return _scene_id() == str(PLACE_SCENE.get(place, ""))


func _play_beat(b: Dictionary) -> void:
	_awaiting_talk = false
	_spawn_beat_npc(b)   # 先让这一幕该在场的人物出现（比如酒馆里的哈特菲利亚）
	_face_cast(b)   # 本幕在场人物全部转向玩家（含被叫来的老板娘，免得面朝外侧）
	var hud: Node = UiStyle.ui_layer(self)
	var ps: PackedScene = load(DIALOGUE_SCENE) as PackedScene
	if hud == null or ps == null:
		push_warning("[ChapterStory] 无法播放幕：hud=%s ps=%s" % [hud, ps])
		return
	var panel: UiPanel = ps.instantiate() as UiPanel
	panel.set("entries", b.get("entries", []))
	hud.add_child(panel)
	_panel = panel
	_playing = true
	panel.closed.connect(_on_beat_closed)
	# 矿井幕：对话一开始就让史莱姆围上来，并在"姜酒杀死史莱姆"那句开始逐只崩解。
	if str(b.get("id", "")) == MINE_BEAT_ID:
		_start_slimes_approach()
		panel.connect("entry_shown", _on_dialogue_entry)
	beat_changed.emit(_index)


## 玩家与某个 NPC 交谈時由 Npc._open_dialogue 调用：
## 若这人正是当前幕该交谈的对象，就播本幕的多人对话并接管，返回 true。
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


## 按幕数据把人物摆进当前场景：beat 带 "npc" + "spawn":[x,y]（可选 "facing"）。
## 酒馆原本没人（world 的 NpcSpawner 是关的），而哈特菲利亚/奇斯/俄莉斯又没有
## 常驻 placement —— 不摆的话这几段戏就是"空屋子里的画外音"。
##
## 一幕里可能不止一个人有台词（矿道入口：西蒙 + 哈特菲利亚），所以支持 "extras":
##   [{"npc":"explorer_lucy","spawn":[838,178],"facing":"right"}, ...]
## 主 npc 负责被玩家按 E 触发，extras 只是"s也在场"，各自的台词由 entries 的 speaker 走。
func _spawn_beat_npc(b: Dictionary) -> void:
	_place_npc(str(b.get("npc", "")), b.get("spawn", null), str(b.get("facing", "down")), b)
	var ex: Variant = b.get("extras", null)
	if ex is Array:
		for e: Variant in ex as Array:
			if e is Dictionary:
				var d: Dictionary = e as Dictionary
				_place_npc(str(d.get("npc", "")), d.get("spawn", null),
						str(d.get("facing", "down")), b, d)
	# 矿井幕：进场就在中央洞穴摆出一地存活史莱姆。
	if str(b.get("id", "")) == MINE_BEAT_ID:
		_spawn_mine_slimes()
	# 本幕人物到位后，把场景里其余正在游荡的常驻角色（老板娘等）一起站定，
	# 免得剧情对话时她们自顾自走掉；幕关闭时再 resume_wander() 恢复。
	_freeze_wanderers()


## 把单个 npc 摆进当前场景（内部用）。已在场的同 id 人物不重复摆。
## [param place_extra] extra/幕数据里除 npc/spawn/facing 外的附加键
## （如 no_interact）原样透传给 Npc.configure 的 place 覆盖。
func _place_npc(nid: String, sp: Variant, facing: String, b: Dictionary,
		place_extra: Dictionary = {}) -> void:
	if nid == "":
		return
	# 允许直接传 Vector2（剧本里手写的常量比 [x,y] 数组好读）。
	if sp is Vector2:
		sp = [(sp as Vector2).x, (sp as Vector2).y]
	if not (sp is Array) or (sp as Array).size() < 2:
		return
	if (_npc_defs.get(nid, {}) as Dictionary).is_empty():
		push_warning("[ChapterStory] 幕 %s 指定的 NPC 未知：%s" % [str(b.get("id", "")), nid])
		return
	if _npc_in_scene(nid):
		# 场景里已有这个人（比如集市常驻的凯瑟琳，或酒馆里原本就在的老板娘）：
		# 别重复摆，但要把她"叫到身边"参与对话——停下游荡并站定，免得老板娘之类
		# 自顾自走掉；幕结束再 resume_wander() 恢复。
		var ex: Node = _find_npc_node(nid)
		if ex != null and ex.has_method("hold_at") and sp is Array and (sp as Array).size() >= 2:
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


## 撤掉本幕摆进来的人物（幕关闭 / 中止 / 复位 / 收尾时调用）。
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


## 当前场景里是否已经有这个 NPC（避免和 NpcSpawner 摆的人重复）。
func _npc_in_scene(id: String) -> bool:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		# 忽略"已排队待删除"的旧节点：上一幕刚撤掉的人不能挡住下一幕同名人登场。
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return true
	return false


## 场景里这个 NPC 的节点（找不到返回 null）。
func _find_npc_node(id: String) -> Node:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("npc_id")) == id:
			return n
	return null


## 对话开始：本幕在场人物全部转向玩家（含被叫来的老板娘，免得她面朝外侧）。
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
	# 矿井幕收尾：玩家点得快时逐只崩解可能还没播完，这里兜底让场内只剩尸体。
	if _index >= 0 and _index < _beats.size() \
			and str((_beats[_index] as Dictionary).get("id", "")) == MINE_BEAT_ID:
		_force_kill_slimes()
	_clear_beat_npcs()
	if _index < _beats.size():
		var b: Dictionary = _beats[_index] as Dictionary
		_apply_side_effects(b)
		if str(b.get("id", "")) == "ch1_eris_permission":
			_rune_granted = true   # 俄莉斯准许用绯色符文后，酿造幕才可触发
		_mark_step_done(str(b.get("id", "")))
		_index += 1
	_sync_objective()
	# 末幕关闭后必须收尾。手动模式下不会再 _pump，所以要在这里兜住；
	# 否则 index 走到末尾但 is_done 永远为 false，章节卡在"未完成"。
	if _index >= _beats.size():
		_finish()
	elif auto_advance:
		_pump()


## 手动推进（测试窗口「播放当前幕」用）：跳过 travel 幕，播放当前这一可播的幕。
## 返回 true = 有进展（播放了 / 结算了 travel / 收尾了）；false = 当前条件不满足。
## 与自动推进的区别只在于「不由场景切换/库存变化触发」，逻辑完全一致。
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


## 任务目的地看着"当前该做的那一幕"。
func _sync_objective() -> void:
	if _index >= _beats.size():
		return
	var b: Dictionary = _beats[_index] as Dictionary
	var dest: Dictionary = b.get("dest", {}) as Dictionary
	# 这一幕没写 dest 也要**照样写进去（等于清空）**：早期只在 dest 非空时才更新，
	# 结果缺 dest 的幕会残留在上一幕的目的地上 —— 玩家人都到新图了，箭头还指着
	# 旧图的旧目标，这就是"指引乱指"的根源。没目的地就让它空着，箭头自然收起。
	QuestLog.set_dest(QID, dest)


func _finish() -> void:
	if _done:
		return
	_done = true
	_clear_beat_npcs()
	_prune_slime_nodes()
	QuestLog.complete(QID)
	_toast("第一章 · 雾凇无虞 —— 完")
	for id: String in SUPERSEDED_ARCS:
		SideStory.mark_played(id)
	finished.emit()


## 当前该做的一幕（供测试/调试读）。
func current_beat() -> Dictionary:
	if _index < 0 or _index >= _beats.size():
		return {}
	return _beats[_index] as Dictionary


func beat_count() -> int:
	return _beats.size()


func _scene_id() -> String:
	var s: Node = get_tree().current_scene
	return s.scene_file_path if s != null else ""


func _toast(text: String) -> void:
	if Story != null and Story.has_method("_toast"):
		Story._toast(text, 4.0)


# ---- 矿井史莱姆演出 -------------------------------------------------------

## 在中央洞穴摆一批存活态史莱姆（幂等：本场景已有就不重复摆）。
func _spawn_mine_slimes() -> void:
	if _has_mine_slimes():
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var sorted: Node = scene.get_node_or_null("Sorted")
	if sorted == null:
		return
	var ps: PackedScene = load(SLIME_SCENE) as PackedScene
	if ps == null:
		push_warning("[ChapterStory] 找不到史莱姆场景 %s" % SLIME_SCENE)
		return
	# 读矿井碰撞箱（岩壁/结构件）+ 可行走边界，交给史莱姆做移动阻挡与避让。
	var rects: Array = _load_prop_collision_rects(sorted)
	var bounds: Rect2 = _walkable_bounds(scene)
	_slimes_killed = false
	for i: int in MINE_SLIME_SPAWNS.size():
		var s: Node2D = ps.instantiate() as Node2D
		if s == null:
			continue
		s.name = "Slime_%d" % i
		s.position = _free_spawn(rects, bounds, MINE_SLIME_SPAWNS[i] as Vector2)
		sorted.add_child(s)
		if s.has_method("configure_collision"):
			s.call("configure_collision", rects, bounds)
		_slime_nodes.append(s)


## 读 props.json 里可阻挡的 collision_rect（跳过 no_collision 的纯装饰件）。
func _load_prop_collision_rects(sorted: Node) -> Array:
	var path: String = "res://assets/mine/v1/objects/props.json"
	if sorted != null:
		var p: Variant = sorted.get("props_path")
		if p is String and str(p) != "":
			path = str(p)
	var out: Array = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for entry: Variant in (parsed as Dictionary).get("props", []):
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry as Dictionary
		if bool(d.get("no_collision", false)):
			continue
		var cr: Variant = d.get("collision_rect", null)
		if cr is Array and (cr as Array).size() >= 4:
			var a: Array = cr as Array
			out.append(Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])))
	return out


func _walkable_bounds(scene: Node) -> Rect2:
	var st: Node = scene.get_node_or_null("Static")
	if st != null:
		var w: Variant = st.get("walkable")
		if w is Rect2 and (w as Rect2).size.x > 0.0:
			return w as Rect2
	return Rect2(8, 8, 1008, 1008)


## 该点放不放得下一只**整只**史莱姆：用精灵框（脚底为原点、身子往上长）去判，
## 不是脚下那 13px 的小圆 —— 只测小圆就会出现"脚在地上、身子埋进岩壁"。
func _point_blocked(rects: Array, bounds: Rect2, p: Vector2) -> bool:
	var l: float = p.x - SLIME_HALF_W
	var r: float = p.x + SLIME_HALF_W
	var t: float = p.y - SLIME_HEIGHT
	var b: float = p.y
	if bounds.size.x > 0.0:
		if l < bounds.position.x or r > bounds.end.x \
				or t < bounds.position.y or b > bounds.end.y:
			return true
	for entry: Variant in rects:
		var rr: Rect2 = entry as Rect2
		if l < rr.end.x and r > rr.position.x and t < rr.end.y and b > rr.position.y:
			return true
	return false


## 投放点若压在碰撞箱里，就螺旋外扩找最近空地（避免出生即卡死）。
func _free_spawn(rects: Array, bounds: Rect2, p: Vector2) -> Vector2:
	if not _point_blocked(rects, bounds, p):
		return p
	for ring: int in range(1, 8):
		var rad: float = float(ring) * 16.0
		for k: int in 16:
			var ang: float = TAU * float(k) / 16.0
			var q: Vector2 = p + Vector2(cos(ang), sin(ang)) * rad
			if not _point_blocked(rects, bounds, q):
				return q
	return p


## 本场景里是否已经有有效史莱姆（避免一幕里重复投放）。
func _has_mine_slimes() -> bool:
	for n: Node in _slime_nodes:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			return true
	return false


## 让史莱姆从洞穴外圈围上来：每只分一个**环形站位**（不是同一个人脚下那个点），
## 于是最后是一圈散开的包围，而不是挤成一坨。
func _start_slimes_approach() -> void:
	if _slime_nodes.is_empty():
		return
	_snap_mine_cast()
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var center: Vector2 = (MINE_STAGE_PLAYER + MINE_STAGE_EDWARD) * 0.5
	if not _is_in_mine():
		center = player.global_position
	var scene: Node = get_tree().current_scene
	var sorted: Node = null
	if scene != null:
		sorted = scene.get_node_or_null("Sorted")
	var rects: Array = _load_prop_collision_rects(sorted)
	var bounds: Rect2 = _walkable_bounds(scene)

	var n: int = _slime_nodes.size()
	var anchors: Array[Vector2] = []
	var aangs: Array[float] = []
	anchors.resize(n)
	aangs.resize(n)
	for i: int in n:
		var ang: float = -PI * 0.5 + TAU * float(i) / float(n)
		ang += _slime_jitter(i) * MINE_SLIME_ANGLE_JITTER
		var rad: float = MINE_SLIME_RING + _slime_jitter(i + 37) * MINE_SLIME_RING_JITTER
		# 兜底：万一某个环点还是压到岩壁（洞穴不是正圆），就把半径往里收，
		# 直到整只精灵框都落在地面上。宁可圈小一点，也不要半只埋进石头里。
		anchors[i] = _shrink_to_free(rects, bounds, center, ang, rad)
		aangs[i] = fposmod(ang, TAU)

	# 按方位角配对：史莱姆和环点各自按"从包围中心看出去的方位角"排序，
	# 再试遍所有循环平移，取总角差最小的一组。这样每只都朝自己那个方向往里收，
	# 路线互不交叉（用"最近点"配对的话，最下面那只可能横穿两人跑到对面去）。
	var idx_s: Array[int] = []
	var bear: Array[float] = []
	for node: Node in _slime_nodes:
		if not is_instance_valid(node):
			continue
		var s: Node2D = node as Node2D
		if s == null:
			continue
		idx_s.append(idx_s.size())
		bear.append(fposmod((s.global_position - center).angle(), TAU))
	var live: Array[Node] = []
	for node: Node in _slime_nodes:
		if is_instance_valid(node) and node is Node2D:
			live.append(node)
	var cnt: int = mini(idx_s.size(), n)
	idx_s.sort_custom(func(a: int, b: int) -> bool: return bear[a] < bear[b])
	var idx_a: Array[int] = []
	for k: int in n:
		idx_a.append(k)
	idx_a.sort_custom(func(a: int, b: int) -> bool: return aangs[a] < aangs[b])

	var best_r: int = 0
	var best_tot: float = 1e20
	for r: int in n:
		var tot: float = 0.0
		for k: int in cnt:
			tot += _angle_delta(bear[idx_s[k]], aangs[idx_a[(k + r) % n]])
		if tot < best_tot:
			best_tot = tot
			best_r = r

	for k: int in cnt:
		var s2: Node2D = live[idx_s[k]] as Node2D
		if s2 == null:
			continue
		var g: Vector2 = anchors[idx_a[(k + best_r) % n]]
		if s2.has_method("set_goal"):
			s2.call("set_goal", g)
		elif s2.has_method("start_approach"):
			s2.call("start_approach", player)


## 两个方位角之间的最短夹角（0..PI）。
func _angle_delta(a: float, b: float) -> float:
	var d: float = absf(fposmod(a - b, TAU))
	return minf(d, TAU - d)


## 沿某个方向找最近的合法落脚点：从 rad 开始逐步往里收，收到整只精灵框都不压墙为止。
func _shrink_to_free(rects: Array, bounds: Rect2, center: Vector2, ang: float, rad: float) -> Vector2:
	var dir: Vector2 = Vector2(cos(ang), sin(ang))
	var r: float = rad
	var p: Vector2 = center + dir * r
	for k: int in 16:
		if not _point_blocked(rects, bounds, p):
			return p
		r -= 5.0
		if r < 18.0:
			break
		p = center + dir * r
	return p


## 固定站位：把主角挪到爱德华旁边（这一幕两人是并肩的），顺便让镜头跟上。
func _snap_mine_cast() -> void:
	if not _is_in_mine():
		return
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		player.global_position = MINE_STAGE_PLAYER
		var cam: Node = player.get_node_or_null("Camera")
		if cam != null and cam.has_method("snap_now"):
			cam.call("snap_now")
	var edward: Node2D = _find_sorted_node("Npc_beat_dwarf_war_edward")
	if edward != null:
		edward.global_position = MINE_STAGE_EDWARD


func _is_in_mine() -> bool:
	return _scene_id() == MINE_SCENE


## 确定性抖动 [-1,1]（不用 random，跑测试时结果可复现）。
func _slime_jitter(k: int) -> float:
	var v: float = sin(float(k) * 12.9898 + 4.1414) * 43758.5453
	return (v - floor(v)) * 2.0 - 1.0


func _find_sorted_node(node_name: String) -> Node2D:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Sorted/" + node_name) as Node2D


## 对话逐句回调：到"姜酒杀死史莱姆"那一句时开始逐只崩解。
func _on_dialogue_entry(index: int) -> void:
	if str(current_beat().get("id", "")) != MINE_BEAT_ID:
		return
	if index >= SLIME_KILL_ENTRY and not _slimes_killed:
		_slimes_killed = true
		_kill_slimes_gradually()


## 逐只错开时间死亡，做出"逐渐死掉"的观感。
func _kill_slimes_gradually() -> void:
	var alive: Array[Node] = []
	for n: Node in _slime_nodes:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			alive.append(n)
	for i: int in alive.size():
		_kill_slime_after(alive[i], float(i) * 0.18)


func _kill_slime_after(s: Node, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# 场景可能在错峰死亡播完前就卸载（玩家/测试提前离开矿井），此时节点已被释放。
	if not is_instance_valid(s):
		return
	_kill_slime(s)


func _kill_slime(s: Node) -> void:
	if is_instance_valid(s) and s.has_method("die"):
		s.call("die")


## 立即让所有史莱姆崩解（幕收尾兜底，保证"残存的都是尸体"）。
func _force_kill_slimes() -> void:
	for n: Node in _slime_nodes:
		if is_instance_valid(n) and n.has_method("die"):
			n.call("die")
	_slimes_killed = true


func _prune_slime_nodes() -> void:
	var alive: Array[Node] = []
	for n: Node in _slime_nodes:
		if is_instance_valid(n):
			alive.append(n)
	_slime_nodes = alive


# ---- 存档 ------------------------------------------------------------------

## 存档快照：章节进度（走到第几幕 / 是否已完结 / 关键旗标）。
## 不存"正在播的那条对话"——读档时 current_beat 会重播，比恢复半截对话安全。
func snapshot() -> Dictionary:
	return {
		"active": _active,
		"done": _done,
		"index": _index,
		"rune_granted": _rune_granted,
		"slimes_killed": _slimes_killed,
	}


## 读档：把推进指针放回去，然后把"正在播 / 正在等人说话"这类瞬时状态清干净，
## 交给下一次 _process（场景切换后）重新 _pump 出来。
func restore(data: Dictionary) -> void:
	_active = bool(data.get("active", false))
	_done = bool(data.get("done", false))
	_index = clampi(int(data.get("index", 0)), 0, maxi(0, _beats.size() - 1))
	_rune_granted = bool(data.get("rune_granted", false))
	_slimes_killed = bool(data.get("slimes_killed", false))
	_playing = false
	_awaiting_talk = false
	_panel = null
	_last_scene = ""
