extends Node
## 常客 / 「已认识」注册表（autoload：Regulars）。
##
## 需求（2026-10-30）：玩家**真正对过话**的角色，之后可以来酒馆买酒（当顾客）。
## 判定口径（用户拍板）：
##   · 「已认识」= 玩家主动搭话、真开过对话。钩子在 Npc._open_dialogue 的最前面：
##     无论走常规对话、支线、还是章节对话，只要对话被打开，就先登记为已认识。
##   · 只有「已认识」且不属于 NOT_CUSTOMER 的角色，才进 CustomerSpawner 的候选。
##   · 首发四位常客（哈特菲利亚/西蒙/爱德华/凯瑟琳）开局即视为已认识 ——
##     否则开张第一天没人来，卖酒-营业额主循环直接断掉。这是唯一的预置例外。
##
## 为什么单独一个 autoload：对话发生在各个场景，登记点分散；spawner 只问 is_known()，
## autoload 跨场景存活 → 认识状态自然连续。

## 开局就认识的首发常客（4 位原始顾客）。
const BASE_KNOWN: Array[String] = [
	"explorer_lucy", "miner_simon", "dwarf_war_edward", "market_catherine",
]
## 设定上不当酒客的角色（认识也不会来买酒）：
##   · 老板娘萃歌自己不会来买酒
##   · 终章古龙卡兹是 BOSS，不摆成顾客
##   · 林格 / 宁芙 / 伊织 / 特蕾西亚（2026-10-30 用户点名去掉）
## （以后想改成数据驱动，可挪到 npcs.json 的 no_customer 字段，这里只管判定。）
## 设定上不当酒客的角色（认识也不会来买酒）：
##   · 老板娘萃歌自己不会来买酒
##   · 终章古龙卡兹是 BOSS，不摆成顾客
##   · 林格 / 宁芙 / 伊织 / 特蕾西亚（2026-10-30 用户点名去掉）
##   · 俄莉斯（2026-10-30 追加）：剧情上不宜在经营里反复露脸，支线聊完即退场，
##     之后不再作为普通客人进店 —— 但她的支线访客资格不受此影响（见
##     CustomerSpawner._story_visitors 走 _all_defs，不走这份名单）。
const NOT_CUSTOMER: Array[String] = [
	"tavern_cuige", "ancient_kaz", "thief_eris",
	"knight_ringe", "spring_nymph", "bartender_iori", "dragon_theresia",
]

## 进剧情前**必须认识**的角色（用户 2026-10-30 拍板：营业额 + 认识 双条件解锁章节）。
##
## 名单口径 = 该章登场角色 − NOT_CUSTOMER（设定上不当酒客，mark_known 也会忽略）
##          − BASE_KNOWN（开局就是老熟人，不必再认识）
##          − **既无常驻位置、又没支线**的人（reception_icarus 就是这种：只在剧情里
##            露个脸，序章根本没途径遇到，列进来就是永远做不完的死锁）。
##
## chiss / eris 的支线已解绑章节门槛 → 第 2 天起他们就像访客一样进酒馆，
## 玩家聊一句即算认识。这就是"开张后自然进店"，不靠额外摆桩。
##
## ⚠ 第三章没有新人登场（卡兹 / 特蕾西亚 / 林格 / 萃歌 都不当酒客），名单为空 =
## 那一章的认识条件自动满足，实际仍只看营业额。
const CHAPTER_REQUIRED: Dictionary = {
	# thief_eris（俄莉斯）不进名单：她已列入 NOT_CUSTOMER（不再当酒客），
	# mark_known 对她直接忽略，「跟俄莉斯对话」这步永远打不了勾 —— 死锁。
	"snow_logistics": ["broker_chiss", "ronin_himura"],
	# brewer_greym（灰毛）不在名单里：他的 placement 挂在 world，而 world 的
	# NpcSpawner 是关的（酒馆不站常驻人），序章根本没途径遇到 —— 列进去就是死锁。
	# 要把他算进来，得先给他补一条支线或别的登场方式。
	"ch2_moon": ["elf_emt", "lich_wiz"],
	"ch3_dragon_king": [] as Array[String],
}

const NPC_DATA: String = "res://data/npcs.json"

## 认识/清单状态变了 → 章节准备任务要重刷进度、顺手重算能不能开章。
signal changed

var _known: Dictionary = {}
var _names: Dictionary = {}


func _ready() -> void:
	_load_names()
	for id: String in BASE_KNOWN:
		_known[id] = true


## 读一遍 npcs.json 的 id→显示名，任务栏要写"认识 奇斯"这种人话，不能甩 id。
func _load_names() -> void:
	var f: FileAccess = FileAccess.open(NPC_DATA, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for e: Variant in ((parsed as Dictionary).get("npcs", []) as Array):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e as Dictionary
		var id: String = str(d.get("id", ""))
		if id != "":
			_names[id] = str(d.get("name", id))


## 玩家与某角色对过话 → 记为已认识。幂等；NOT_CUSTOMER 直接忽略。
func mark_known(npc_id: String) -> void:
	if npc_id == "" or NOT_CUSTOMER.has(npc_id):
		return
	if bool(_known.get(npc_id, false)):
		return
	_known[npc_id] = true
	changed.emit()


func is_known(npc_id: String) -> bool:
	return bool(_known.get(npc_id, false))


## 这位角色是否"可以是酒客"（不看是否已认识）—— 排除老板娘/终章 Boss。
func allows_customer(npc_id: String) -> bool:
	return npc_id != "" and not NOT_CUSTOMER.has(npc_id)


## 已认识的 id 列表（调试/验收用）。
func known_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _known:
		if _known[id]:
			out.append(id)
	return out


## 某章"进剧情前要认识"的名单（副本，改它不影响常量）。
func required_for(chapter: String) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in (CHAPTER_REQUIRED.get(chapter, []) as Array):
		out.append(str(id))
	return out


## 某章还差谁没认识（任务栏就按这个列"还差 XX"）。
func missing_for(chapter: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in required_for(chapter):
		if not is_known(id):
			out.append(id)
	return out


## 某章的认识条件达成没。名单为空 = 视为达成（该章没有需要认识的新面孔）。
func all_known_for(chapter: String) -> bool:
	return missing_for(chapter).is_empty()


## (已认识数, 总数) —— 任务栏画"3/5"这种进度。
func progress_for(chapter: String) -> Vector2i:
	var req: Array[String] = required_for(chapter)
	var have: int = req.size() - missing_for(chapter).size()
	return Vector2i(have, req.size())


## 角色显示名（读不到就退回 id）。
func display_name(npc_id: String) -> String:
	return str(_names.get(npc_id, npc_id))


## 验收/重开用：恢复到只预置首发 4 位。
func reset() -> void:
	_known.clear()
	for id: String in BASE_KNOWN:
		_known[id] = true
	changed.emit()


# ---- 存档 ------------------------------------------------------------------

## 存档快照：已认识名单（id 数组，比字典更好读也更好跨版本兼容）。
func snapshot() -> Dictionary:
	return {"known": known_ids()}


## 读档：整份替换。空名单 = 退回开局预置，免得读到一个残缺档后一个客人都没有。
func restore(data: Dictionary) -> void:
	_known.clear()
	var ids: Array = data.get("known", []) as Array
	for entry: Variant in ids:
		_known[str(entry)] = true
	if _known.is_empty():
		for id: String in BASE_KNOWN:
			_known[id] = true
	changed.emit()
