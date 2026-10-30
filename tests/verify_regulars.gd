extends Node
## 「已认识 → 可当酒客」判定验收（Phase 1）。
##
## 覆盖：
##   1) 开局只有 4 位首发常客算已认识；绯村 / 萃歌不在候选
##   2) 搭话（Npc._open_dialogue）后登记为已认识，候选 +1
##   3) 已认识角色套默认顾客档案（预算 90、有台词）——没有 customer 块也能来买酒
##   4) 老板娘萃歌被排除（mark_known 无效）
##   5) reset() 回到 4 位
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_regulars.tscn --quit-after 9000

const WORLD: String = "res://scenes/world.tscn"
const NPC_SCENE: String = "res://scenes/npc.tscn"
const BASE: Array[String] = ["explorer_lucy", "miner_simon",
		"dwarf_war_edward", "market_catherine"]

var scene: Node2D
var spawner: CustomerSpawner
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Regulars.reset()
	scene = (load(WORLD) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	spawner = scene.get_node_or_null("Customers") as CustomerSpawner

	_check_initial()
	await _check_default_profile()
	await _check_talk_marks_known()
	_check_deny()
	_check_excluded()
	await _check_capacity_numbers()
	_check_reset()

	print("[regulars] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check_initial() -> void:
	var r: Array[String] = spawner.roster()
	var ok: bool = r.size() == 4
	for id: String in BASE:
		if not r.has(id):
			ok = false
	_report("开局候选 = 4 位首发常客", ok, "roster=%s" % [r])
	_report("绯村开局不算已认识", not Regulars.is_known("ronin_himura")
			and not r.has("ronin_himura"),
			"known=%s roster=%s" % [Regulars.is_known("ronin_himura"), r])


func _check_default_profile() -> void:
	# 手动让绯村"已认识"（等价于玩家与他对过话），再作为酒客生成
	Regulars.mark_known("ronin_himura")
	_report("搭话登记后进入候选", spawner.roster().has("ronin_himura"),
			"roster=%s" % [spawner.roster()])
	var c: Customer = spawner.spawn("ronin_himura")
	var ok: bool = c != null and c.budget == 90 and c.greet_lines().size() > 0
	_report("已认识角色套默认档案（预算 90 + 有台词）", ok,
			"cust=%s budget=%d greet=%d" % [c != null,
			c.budget if c != null else -1,
			c.greet_lines().size() if c != null else -1])
	if c != null:
		c.queue_free()
	await get_tree().process_frame


func _check_talk_marks_known() -> void:
	_report("搭话前奇斯未认识", not Regulars.is_known("broker_chiss"), "")
	var def: Dictionary = _npc_def("broker_chiss")
	var ps: PackedScene = load(NPC_SCENE) as PackedScene
	var npc: Npc = ps.instantiate() as Npc
	npc.configure(def, {"pos": [420, 300], "facing": "down", "wander": 0.0})
	var sorted: Node = scene.get_node("Sorted")
	sorted.add_child(npc)
	await get_tree().physics_frame
	npc._open_dialogue()
	await get_tree().process_frame
	_report("Npc._open_dialogue 后登记为已认识", Regulars.is_known("broker_chiss"),
			"known=%s" % Regulars.is_known("broker_chiss"))
	# 关掉可能弹出的对话框，别留下模态
	for m: Node in get_tree().get_nodes_in_group("modal_ui"):
		if m.has_method("close"):
			m.call("close")
	await get_tree().process_frame
	npc.queue_free()
	await get_tree().process_frame


func _check_deny() -> void:
	Regulars.mark_known("tavern_cuige")
	_report("老板娘萃歌被排除（mark_known 无效）",
			not Regulars.is_known("tavern_cuige")
			and not spawner.roster().has("tavern_cuige"),
			"known=%s roster=%s" % [Regulars.is_known("tavern_cuige"), spawner.roster()])


func _check_excluded() -> void:
	var deny: Array[String] = ["knight_ringe", "spring_nymph",
			"bartender_iori", "dragon_theresia"]
	var all_ok: bool = true
	var leaked: Array[String] = []
	for id: String in deny:
		Regulars.mark_known(id)   # 对排除名单应无效
		if Regulars.is_known(id) or spawner.roster().has(id):
			all_ok = false
			leaked.append(id)
	_report("林格/宁芙/伊织/特蕾西亚不在顾客名单", all_ok, "leaked=%s" % [leaked])


func _check_capacity_numbers() -> void:
	Regulars.reset()   # 干净状态：4 位首发常客
	_report("reset 后预计客流上限 = 4", spawner.daily_customer_cap() == 4,
			"cap=%d" % spawner.daily_customer_cap())
	var before: int = spawner.arrived_today()
	var c: Customer = spawner.spawn("explorer_lucy")
	await get_tree().process_frame
	_report("生成一位后「已来」+1", c != null and spawner.arrived_today() == before + 1,
			"before=%d after=%d" % [before, spawner.arrived_today()])
	if c != null:
		c.queue_free()
	await get_tree().process_frame
	# 多认识一位 → 今日客流上限 +1
	Regulars.mark_known("broker_chiss")
	_report("多认识一位后上限 +1", spawner.daily_customer_cap() == 5,
			"cap=%d" % spawner.daily_customer_cap())
	Regulars.reset()


func _check_reset() -> void:
	Regulars.reset()
	_report("reset 回到 4 位首发常客", spawner.roster().size() == 4,
			"roster=%s" % [spawner.roster()])


func _npc_def(id: String) -> Dictionary:
	var f: FileAccess = FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	for e: Variant in ((parsed as Dictionary).get("npcs", []) as Array):
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("id", "")) == id:
			return e as Dictionary
	return {}


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		print("[check] PASS  %s" % name)
	else:
		failed += 1
		print("[check] FAIL  %s  (%s)" % [name, detail])
