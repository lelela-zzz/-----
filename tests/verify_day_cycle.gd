extends Node
## 「第二天没客人」的护栏（2026-10-29 修的 bug）：
##
## 时钟是每个场景各一个，以前 `day` 写死初值 1，出门买趟料再回来日子就退回
## 第 1 天。顾客那边「今天已经买过」的账（`CustomerSpawner._purchased_day`）
## 是按天记的，日子一回退，四位客人全被当成"今天买过" → 从此一个人都不来。
##
## 这里盯住四件事：
##   1) 第 1 天：全员买过 → 当天确实不再来客（规则本身是对的）
##   2) 跨天（宵禁 23:00 → 次日 07:30）→ 客人资格恢复，第二天的开场客会重放
##   3) **换场景重建时钟后，天数不回退**（本 bug 的根）
##   4) 换场景回来照样来客，且还能继续往后跨天
##
## 跑法： "<godot>" --headless --path . res://tests/verify_day_cycle.tscn --quit-after 9000

var _pass := 0
var _fail := 0
var scene: Node
var spawner: CustomerSpawner
var clock: GameClock


func _ready() -> void:
	GameClock.reset_day(1)
	CustomerSpawner.reset_session()
	StoryDirector.force_disable = true      # 让 Story 别插一脚（tavern_open 恒为真）
	CustomerSpawner.force_disable = false
	await get_tree().process_frame
	await _mount()

	_report("新开一局是第 1 天", clock.day == 1, "day=%d" % clock.day)

	# --- 1. 第 1 天：四个人今天都买过 -------------------------------------
	var roster: Array[String] = spawner.roster()
	_report("顾客名册 4 位", roster.size() == 4, "roster=%s" % str(roster))
	for id: String in roster:
		CustomerSpawner._purchased_day[id] = clock.day
	_clear_customers()
	_report("第 1 天全员买过 → 当天确实不再来客",
			spawner.spawn_random() == null,
			"spawn=%s" % str(spawner.spawn_random()))

	# --- 2. 熬到宵禁 → 第 2 天 -------------------------------------------
	clock.call("_roll_over_curfew")
	_report("宵禁跨天 → 第 2 天 07:30",
			clock.day == 2 and clock.hour == 7 and clock.minute == 30,
			"day=%d %02d:%02d" % [clock.day, clock.hour, clock.minute])
	var c2: Customer = spawner.spawn_random()
	_report("第 2 天客人资格恢复（能来人）", c2 != null,
			"spawn=%s" % (c2.npc_id if c2 != null else "null"))
	_clear_customers()

	# 第二天开张：开场客应当重放（_rush_day 还停在第 1 天）
	spawner._running = false
	spawner._rush_remaining = 0
	spawner._process(0.016)
	_report("第 2 天开张会重新放开场客",
			CustomerSpawner._rush_day == 2 and spawner._rush_remaining > 0,
			"rush_day=%d remaining=%d" % [CustomerSpawner._rush_day, spawner._rush_remaining])
	_clear_customers()

	# --- 3. 出门买趟料再回来（场景 + 时钟重建）----------------------------
	await _remount()
	_report("换场景后天数不回退（仍是第 2 天）", clock.day == 2,
			"day=%d" % clock.day)
	var c2b: Customer = spawner.spawn_random()
	_report("换场景回来照样来客", c2b != null,
			"spawn=%s" % (c2b.npc_id if c2b != null else "null"))
	_clear_customers()
	_report("同一天关掉招牌又开，不再重复涌人（rush 仍记在第 2 天）",
			CustomerSpawner._rush_day == 2, "rush_day=%d" % CustomerSpawner._rush_day)

	# --- 4. 新时钟也能继续跨天 -------------------------------------------
	clock.call("_roll_over_curfew")
	_report("换过场景的新时钟照样能跨到第 3 天", clock.day == 3, "day=%d" % clock.day)
	var c3: Customer = spawner.spawn_random()
	_report("第 3 天也来客（日子一直在往前走）", c3 != null,
			"spawn=%s" % (c3.npc_id if c3 != null else "null"))

	print("[day_cycle] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---- 场景装卸 -----------------------------------------------------------

func _mount() -> void:
	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame
	Story.stage = StoryDirector.Stage.OPEN
	spawner = scene.get_node("Customers") as CustomerSpawner
	clock = get_tree().get_first_node_in_group("game_clock") as GameClock


func _remount() -> void:
	get_tree().root.remove_child(scene)
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _mount()


## 清掉在场客人，好让"能不能再来人"验得干净（不然可能只是被上限挡住）。
func _clear_customers() -> void:
	for slot: int in spawner._occupancy.keys():
		var c: Customer = spawner._occupancy[slot] as Customer
		if is_instance_valid(c):
			c.queue_free()
	spawner._occupancy.clear()


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s | %s" % [name, detail])
	else:
		_fail += 1
		print("[check] FAIL  %s | %s" % [name, detail])
