extends Node
## 顾客跨场景保持验收（靠快照）。
##
## 2026-10-28 起地窖并进了 world.tscn（同一张图的上半层），上楼看锅**不切场景**，
## 所以"下地窖快照"这条用例没意义了。现在还用快照的只剩一个真实场景：
## 走出店门到门口街上（`tavern_exterior.tscn` 仍算"自家屋檐下"），world 会被销毁，
## 靠快照把在场的人带回来；而真的走远（集市/村子）则当玩家离店，店里散场。
##
## 验收：
##   1) 上楼进地窖不换场景 → 顾客原地不动，也不需要快照；
##   2) 去门口街上再回来 → 两位顾客照原样摆回去（状态/座位/杯数不丢），快照一次性；
##   3) 真的出门去集市 → 不存快照，回来重新来客；
##   4) 离开期间跨了天 → 不恢复（当他们等不及走了）。
##   "<godot.exe>" --headless --path . res://tests/verify_customer_persist.tscn --quit-after 9000

const ENTRY := "res://scenes/world.tscn"
const EXTERIOR := "res://scenes/tavern_exterior.tscn"
const VILLAGE := "res://scenes/village.tscn"

var scene: Node2D
var spawner: CustomerSpawner
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = false
	CustomerSpawner.reset_session()
	Inventory.clear()

	await _make_world()
	await _check_cellar_same_scene()
	await _check_street_keeps_customers()
	await _check_door_to_outside()
	await _check_next_day()

	print("[persist] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 场景工具 --------------------------------------------------------------

func _make_world() -> void:
	scene = (load(ENTRY) as PackedScene).instantiate()
	add_child(scene)
	spawner = scene.get_node("Customers") as CustomerSpawner
	# 不许自动补位：在场人员全由用例摆，否则等着等着就多出一位
	spawner.auto_spawn = false
	await _wait(4)
	# _restore_snapshot 是 deferred 的，多等一帧让它跑完
	await _wait(3)


func _leave(target: String) -> void:
	# 真游戏里 DoorArea 先写 pending_target 再 change_scene；这里照做，只差没真换场景
	DoorArea.pending_target = target
	if is_instance_valid(scene):
		scene.queue_free()
	scene = null
	spawner = null
	await _wait(4)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# ---- 0. 上楼进地窖：不切场景，顾客原地不动 --------------------------------

func _check_cellar_same_scene() -> void:
	var has_door: bool = scene.get_node_or_null("Doors/Cellar") != null
	_report("酒馆里没有下地窖的传送门（上楼是同一张图，走过去就行）", not has_door,
			"Doors/Cellar=%s" % str(scene.get_node_or_null("Doors/Cellar")))

	var bg: Node = scene.get_node_or_null("CellarBackground")
	_report("地窖就在 world 里（CellarBackground 挂上了）", bg != null, "节点=%s" % str(bg))

	var guy: Customer = spawner.spawn("explorer_lucy")
	_report("（前置）能摆出一位顾客", guy != null, "spawn=%s" % str(guy))
	# 地窖在画面外的同一场景里 —— 不切场景，spawner 的 _exit_tree 不会跑
	_report("上楼看锅不会触发快照（场景没换）",
			CustomerSpawner._snap_customers.is_empty() and spawner.active_count() == 1,
			"快照 %d 条 / 在场 %d" % [CustomerSpawner._snap_customers.size(),
					spawner.active_count()])
	if guy != null:
		guy.queue_free()
	await _wait(2)


# ---- 1. 去门口街上（还属自家屋檐下）→ 快照 → 回来照原样 -------------------

func _check_street_keeps_customers() -> void:
	Inventory.add("wine_warm_ginger", 3)

	var luc_y: Customer = spawner.spawn("explorer_lucy")
	var simon: Customer = spawner.spawn("miner_simon")
	if luc_y == null or simon == null:
		_report("（前置）能摆出两位顾客", false, "spawn 返回 null")
		return
	simon.customer_speed = 400.0
	var price: int = simon.sell("wine_warm_ginger")
	var bought: int = simon._sold_count
	simon._begin_sit()
	for i in 240:
		await get_tree().physics_frame
		if simon._seated:
			break

	_report("（前置）一位排队、一位坐上凳子",
			price > 0 and simon.state == Customer.State.SITTING and simon._seated,
			"卖得 %d 铜 / simon state=%d seated=%s" % [price, simon.state, simon._seated])

	await _leave(EXTERIOR)
	_report("走到门口街上（world 销毁）时把两位顾客存进快照",
			CustomerSpawner._snap_customers.size() == 2,
			"快照 %d 条" % CustomerSpawner._snap_customers.size())

	await _make_world()
	_report("从街上回店里两位顾客都回来了",
			spawner.active_count() == 2,
			"在场 %d" % spawner.active_count())
	var simon2: Customer = _cust("miner_simon")
	_report("回来的人状态照旧（还坐着、已买杯数没丢）",
			simon2 != null and simon2.state == Customer.State.SITTING
			and simon2._seated and simon2._sold_count == bought,
			"state=%s seated=%s drinks=%s(期望 %d)" % [
					"<null>" if simon2 == null else str(simon2.state),
					"<null>" if simon2 == null else str(simon2._seated),
					"<null>" if simon2 == null else str(simon2._sold_count), bought])
	_report("快照是一次性的（用过就清空，不会重复摆人）",
			CustomerSpawner._snap_customers.is_empty(),
			"残留 %d 条" % CustomerSpawner._snap_customers.size())


# ---- 2. 真的出门去集市 ------------------------------------------------------

func _check_door_to_outside() -> void:
	await _leave(VILLAGE)
	_report("出门去集市 → 不存快照（店里散场）",
			CustomerSpawner._snap_customers.is_empty(),
			"快照 %d 条" % CustomerSpawner._snap_customers.size())
	await _make_world()
	_report("从集市回来：店里重新来客（不是刚才那批）",
			spawner.active_count() == 0,
			"在场 %d" % spawner.active_count())


# ---- 3. 离开期间跨了天 → 不恢复 ---------------------------------------------

func _check_next_day() -> void:
	spawner.spawn("explorer_lucy")
	spawner.spawn("miner_simon")
	await _leave(EXTERIOR)
	_report("（前置）再出门时又存了 2 条快照",
			CustomerSpawner._snap_customers.size() == 2,
			"快照 %d 条" % CustomerSpawner._snap_customers.size())
	# 模拟"玩家在街上待过了零点"：快照存的是昨天，现在是今天
	CustomerSpawner._snap_day -= 1
	await _make_world()
	_report("离开期间跨了天：顾客不恢复（等不及走了）",
			spawner.active_count() == 0,
			"在场 %d" % spawner.active_count())


# ---- 工具 ------------------------------------------------------------------

func _cust(id: String) -> Customer:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var c: Customer = n as Customer
		if c != null and is_instance_valid(c) and c.npc_id == id:
			return c
	return null


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
