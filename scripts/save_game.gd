extends Node
## 存档系统（autoload：SaveGame）—— 三个槽位 + 一个"上次游玩"指针。
##
## 【只存玩家做过什么，不存节点】
##   库存 / 营业额 / 任务清单 / 序章与三章的进度旗标 / 支线已播 / 已认识名单 /
##   顾客当天的账 / 时钟 / 玩家所在场景与坐标。
##   每个模块自己出 `snapshot()`、自己吃 `restore()`，本脚本只负责装箱、写盘、
##   切场景 —— 以后加系统只要在 `snapshot()` 那张表里补一行，不用懂格式。
##
## 【为什么连场景和坐标一起存】玩家可能正站在集市摊位前或矿道深处存档，
## 继续游戏应该回到原地，而不是被踢回酒馆重走一遍。
##
## 【读档为什么分两步】`change_scene_to_file` 是延后的：函数返回时新场景还没
## ready，拿不到 Player / Clock。所以先把内存状态灌回去，再把「落点 + 时钟」
## 塞进 pending，交给目标场景的 SceneBootstrap 在 _ready 里取走 ——
## 和 DoorArea 的传送落点是同一套机制，不另造轮子。
##
## 【存档格式】ConfigFile（`user://save_1.cfg` … `save_3.cfg`），meta 段给列表
## 面板读（不用整份解析），play 段是上面那些字典。带 VERSION，读档时版本不符
## 就拒绝并提示，不让半旧数据把游戏灌坏。

## 存档写好了（面板据此收摊 / 弹提示）
signal saved(slot: int)
## 存档删掉了（标题界面据此把「继续 / 读取」重新判一遍）
signal deleted(slot: int)
## 即将读档切场景
signal loading(slot: int)

## 版本号：格式一改就 +1，旧档读不了（比读进来半个状态好）
const VERSION: int = 1
const SLOT_COUNT: int = 3
const SLOT_FMT: String = "user://save_%d.cfg"
## "上次游玩的是哪个槽"——「继续游戏」直接用它
const LAST_PATH: String = "user://save_last.cfg"
const LAST_SECTION: String = "last"
const LAST_KEY: String = "slot"

const S_META: String = "meta"
const S_PLAY: String = "play"

## 只能在"玩家真能自由走动"的场景存档。灰空间（dark_space）是剧情专用的一次性
## 空间，存进去再读出来就成了死局，所以直接不让存。
const SAVE_SCENES: Array[String] = [
	"world", "village", "tavern_exterior", "mine", "mine_entrance",
	"snow_mountain", "spring", "dragon_lair",
]

## 待应用的角色落点 + 时钟（SceneBootstrap 取走）
var _pending: Dictionary = {}


# ---- 槽位查询（面板 / 标题界面读这些）--------------------------------------

func slot_path(slot: int) -> String:
	return SLOT_FMT % slot


func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func has_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false
	if not FileAccess.file_exists(slot_path(slot)):
		return false
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(slot_path(slot)) != OK:
		return false
	return cfg.has_section(S_PLAY) and int(cfg.get_value(S_META, "version", 0)) == VERSION


## 有没有任何一个能读的档（标题界面据此点亮「继续 / 读取」）
func any_slot() -> bool:
	for i: int in range(1, SLOT_COUNT + 1):
		if has_slot(i):
			return true
	return false


## 上次游玩的槽；0 = 没有（没存过档 / 指的那个槽被删了）
func last_slot() -> int:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(LAST_PATH) != OK:
		return 0
	var slot: int = int(cfg.get_value(LAST_SECTION, LAST_KEY, 0))
	return slot if has_slot(slot) else 0


## 槽位摘要（面板/标题列表用）：{} = 空档。只读 meta 段，不碰 play 段。
func meta_of(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(slot_path(slot)) != OK:
		return {}
	return {
		"slot": slot,
		"day": int(cfg.get_value(S_META, "day", 1)),
		"hour": int(cfg.get_value(S_META, "hour", 0)),
		"minute": int(cfg.get_value(S_META, "minute", 0)),
		"money": int(cfg.get_value(S_META, "money", 0)),
		"revenue": float(cfg.get_value(S_META, "revenue", 0.0)),
		"scene": str(cfg.get_value(S_META, "scene", "")),
		"saved_at": str(cfg.get_value(S_META, "saved_at", "")),
	}


## 面板上那行摘要：「第 3 天 14:20 · 累计 320 铜」
func summary_of(meta: Dictionary) -> String:
	if meta.is_empty():
		return "空存档位"
	return "第 %d 天 %02d:%02d · 累计 %d 铜" % [
		int(meta.get("day", 1)), int(meta.get("hour", 0)),
		int(meta.get("minute", 0)), int(round(float(meta.get("revenue", 0.0)))),
	]


## 存档场景名（"world" / "village" …），给面板显示"在哪儿存的"
func place_of(meta: Dictionary) -> String:
	var path: String = str(meta.get("scene", ""))
	var key: String = path.get_file().get_basename()
	match key:
		"world": return "龙与粗麦酒酒馆"
		"village": return "卢迪克集市"
		"tavern_exterior": return "酒馆门前"
		"mine": return "矿道"
		"mine_entrance": return "矿道入口"
		"snow_mountain": return "雪山"
		"spring": return "月痕泉"
		"dragon_lair": return "龙巢"
	return "—"


# ---- 写档 ------------------------------------------------------------------

## 当前场景能不能存（不能就返回原因，能就返回空串）。
func block_reason() -> String:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return "还没进游戏"
	var key: String = scene.scene_file_path.get_file().get_basename()
	if not SAVE_SCENES.has(key):
		return "这里存不了档"
	if get_tree().get_first_node_in_group("player") == null:
		return "找不到角色"
	return ""


func save_to(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false
	var reason: String = block_reason()
	if not reason.is_empty():
		push_warning("[SaveGame] %s" % reason)
		return false
	var data: Dictionary = snapshot()
	var cfg: ConfigFile = ConfigFile.new()
	var clock: Dictionary = data.get("clock", {}) as Dictionary
	var player: Dictionary = data.get("player", {}) as Dictionary
	cfg.set_value(S_META, "version", VERSION)
	cfg.set_value(S_META, "saved_at", Time.get_datetime_string_from_system(false, true))
	cfg.set_value(S_META, "day", int(clock.get("day", 1)))
	cfg.set_value(S_META, "hour", int(clock.get("hour", 0)))
	cfg.set_value(S_META, "minute", int(clock.get("minute", 0)))
	cfg.set_value(S_META, "money", Inventory.copper)
	cfg.set_value(S_META, "revenue", Revenue.total)
	cfg.set_value(S_META, "scene", str(player.get("scene", "")))
	for key: String in data:
		cfg.set_value(S_PLAY, key, data[key])
	var err: int = cfg.save(slot_path(slot))
	if err != OK:
		push_warning("[SaveGame] 写 %s 失败（err=%d）" % [slot_path(slot), err])
		return false
	remember_last(slot)
	saved.emit(slot)
	print("[SaveGame] 已存入槽 %d（第 %d 天 %02d:%02d）" % [slot,
			int(clock.get("day", 1)), int(clock.get("hour", 0)),
			int(clock.get("minute", 0))])
	return true


## 把"上次游玩"指向这个槽（继续游戏直接跳这里）
func remember_last(slot: int) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(LAST_SECTION, LAST_KEY, slot)
	cfg.save(LAST_PATH)


## 删一格。删的正好是"上次游玩"指的那格时，把指针一起清掉 ——
## 否则「继续游戏」会指着一个不存在的槽（虽然 last_slot() 会兜回 0，
## 但把脏指针留在盘上，以后排查问题会多绕一圈）。
func delete_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false
	var path: String = ProjectSettings.globalize_path(slot_path(slot))
	if not FileAccess.file_exists(path):
		return false
	var err: int = DirAccess.remove_absolute(path)
	if err != OK:
		push_warning("[SaveGame] 删 %s 失败（err=%d）" % [path, err])
		return false
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(LAST_PATH) == OK and int(cfg.get_value(LAST_SECTION, LAST_KEY, 0)) == slot:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LAST_PATH))
	deleted.emit(slot)
	print("[SaveGame] 已删除槽 %d" % slot)
	return true


## 清空全部槽位（测试 / 验收 / "重新开始"用）。返回删掉的个数。
func clear_all_slots() -> int:
	var n: int = 0
	for i: int in range(1, SLOT_COUNT + 1):
		if delete_slot(i):
			n += 1
	# 没有槽了，指针也没有意义
	var last: String = ProjectSettings.globalize_path(LAST_PATH)
	if FileAccess.file_exists(last):
		DirAccess.remove_absolute(last)
	return n


## 装箱：全部状态拍一张快照。
func snapshot() -> Dictionary:
	return {
		"clock": _clock_state(),
		"player": _player_state(),
		"inventory": Inventory.snapshot(),
		"revenue": Revenue.snapshot(),
		"quests": QuestLog.snapshot(),
		"story": Story.snapshot(),
		"ch1": ChapterStory.snapshot(),
		"ch2": Chapter2Story.snapshot(),
		"ch3": Chapter3Story.snapshot(),
		"side": SideStory.snapshot(),
		"regulars": Regulars.snapshot(),
		"customers": CustomerSpawner.snapshot(),
	}


func _clock_state() -> Dictionary:
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock == null:
		return {"day": GameClock._shared_day, "hour": 7, "minute": 30}
	return {"day": clock.day, "hour": clock.hour, "minute": clock.minute}


func _player_state() -> Dictionary:
	var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var scene: Node = get_tree().current_scene
	var path: String = scene.scene_file_path if scene != null else ""
	var pos: Vector2 = Vector2.ZERO
	var facing: Vector2i = Vector2i.DOWN
	if p != null:
		pos = p.global_position
		facing = p.facing
	return {"scene": path, "x": pos.x, "y": pos.y,
			"fx": facing.x, "fy": facing.y}


# ---- 读档 ------------------------------------------------------------------

func load_slot(slot: int) -> bool:
	if not has_slot(slot):
		return false
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(slot_path(slot)) != OK:
		return false
	var data: Dictionary = {}
	for key: String in cfg.get_section_keys(S_PLAY):
		data[key] = cfg.get_value(S_PLAY, key)
	var player: Dictionary = data.get("player", {}) as Dictionary
	var scene: String = str(player.get("scene", ""))
	if scene.is_empty() or not ResourceLoader.exists(scene):
		push_warning("[SaveGame] 槽 %d 里的场景 %s 不存在" % [slot, scene])
		return false
	_apply(data)
	_pending = {
		"slot": slot,
		"pos": Vector2(float(player.get("x", 0.0)), float(player.get("y", 0.0))),
		"facing": Vector2i(int(player.get("fx", 0)), int(player.get("fy", 1))),
		"day": int((data.get("clock", {}) as Dictionary).get("day", 1)),
		"hour": int((data.get("clock", {}) as Dictionary).get("hour", 7)),
		"minute": int((data.get("clock", {}) as Dictionary).get("minute", 30)),
	}
	remember_last(slot)
	loading.emit(slot)
	print("[SaveGame] 读取槽 %d → %s" % [slot, scene])
	get_tree().change_scene_to_file(scene)
	return true


## 灌内存状态。顺序有讲究：先库存/营业额（其它系统的 restore 可能读它们），
## 再任务，再剧情旗标，最后顾客的当日账。
func _apply(data: Dictionary) -> void:
	# 读档前先清掉"正在播的东西"：面板、待说话、跨场景残留
	Story.abort_pending_dialogue()
	ChapterStory.abort_current_beat()
	Chapter2Story.abort_current_beat()
	Chapter3Story.abort_current_beat()

	Inventory.restore(data.get("inventory", {}) as Dictionary)
	Revenue.restore(data.get("revenue", {}) as Dictionary)
	QuestLog.restore(data.get("quests", {}) as Dictionary)
	Regulars.restore(data.get("regulars", {}) as Dictionary)
	SideStory.restore(data.get("side", {}) as Dictionary)
	ChapterStory.restore(data.get("ch1", {}) as Dictionary)
	Chapter2Story.restore(data.get("ch2", {}) as Dictionary)
	Chapter3Story.restore(data.get("ch3", {}) as Dictionary)
	Story.restore_progress(data.get("story", {}) as Dictionary)
	CustomerSpawner.restore(data.get("customers", {}) as Dictionary)

	# 时钟：新场景的 Clock 还没起来，先写共享天数；时分由 SceneBootstrap 落到本地钟
	GameClock._shared_day = int((data.get("clock", {}) as Dictionary).get("day", 1))


func has_pending_spawn() -> bool:
	return not _pending.is_empty()


func consume_pending_spawn() -> Dictionary:
	var out: Dictionary = _pending
	_pending = {}
	return out
