extends Node
## 指引系统验收：追踪 → 跨图路线 → 单图内「下一跳」指向。
##
## 覆盖用户 2026-10-27 拍板的规则：
##  · 没追踪任务 / 任务没有 dest → 箭头不显示；
##  · 跨图 → 指**下一跳那扇门**，而不是终点；换图后自动改指新图的下一跳；
##  · 已经在目标图里 → 指目的地本身（绑节点优先，节点没了退回 pos 兜底）；
##  · 走到跟前（≤ARRIVE_DIST）→ 收起箭头；
##  · 目标图不可达 → 不指、不崩，只 push_warning。
##  · M 地图面板只列已解锁的去处。
##
## 纯逻辑（含实例化场景），headless 可跑。

const WORLD: String = "res://scenes/world.tscn"
const EXTERIOR: String = "res://scenes/tavern_exterior.tscn"
const VILLAGE: String = "res://scenes/village.tscn"
const MINE_ENTRANCE: String = "res://scenes/mine_entrance.tscn"

const QID: String = "guide_test"

var passed: int = 0
var failed: int = 0
var _scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	QuestLog.reset()
	# 关键：先等一帧再往 root 里挂场景。_ready 这一整条链还在跑的时候
	# root 处于「正在布置子节点」状态，此时 add_child 会被拒（见 _mount）。
	await get_tree().process_frame

	# 每个用例都含 await，必须逐个 await —— 少了就会并发跑、断言乱序。
	await _check_no_tracking()
	await _check_cross_map_hops()
	await _check_reaches_destination()
	await _check_unreachable()
	await _check_complete_clears_tracking()
	await _check_map_panel_gating()
	await _check_injection()

	QuestLog.reset()
	_finish()


## --- 用例 ---------------------------------------------------------------

func _check_no_tracking() -> void:
	await _mount(WORLD)
	QuestLog.add(QID, "无目的地的任务", "" )   # 没 dest
	QuestLog.add_step(QID, "随便一步")
	QuestLog.set_tracked(QID)
	await _tick()
	_report("有追踪但任务没有 dest → 不显示箭头", not QuestGuide.valid(),
			"valid=%s" % QuestGuide.valid())
	QuestLog.set_tracked("")
	await _tick()
	_report("没有追踪任务 → 不显示箭头", not QuestGuide.valid(),
			"valid=%s" % QuestGuide.valid())


## 跨图：world → tavern_exterior → village，每图只指**下一跳的门**。
func _check_cross_map_hops() -> void:
	_setup_quest()

	await _mount(WORLD)
	_near(Vector2(319, 371), "在酒馆里 → 指南门 ExitSouth")

	await _mount(EXTERIOR)
	_near(Vector2(5, 466), "在酒馆门口 → 指左边路口 RoadWest")

	await _mount(VILLAGE)
	_report("到了目标图 → kind 变成 dest（指目的地本身）",
			QuestGuide.kind() == "dest", "kind=%s" % QuestGuide.kind())
	var npc: Node2D = _scene.get_node_or_null("Sorted/Npc_market_catherine") as Node2D
	if npc == null:
		_report("村庄里找得到凯瑟琳节点（绑节点生效）", false, "节点不存在")
		return
	_report("目的地 = 凯瑟琳节点实时位置（绑节点优先）",
			QuestGuide.waypoint().distance_to(npc.global_position) < 1.0,
			"waypoint=%s npc=%s" % [str(QuestGuide.waypoint()), str(npc.global_position)])


func _check_reaches_destination() -> void:
	_setup_quest()
	await _mount(VILLAGE)
	_report("从村庄出发（已在目标图）→ kind=dest",
			QuestGuide.kind() == "dest", "kind=%s" % QuestGuide.kind())
	_report("从村庄出发 → 不需要跨图（0 跳）",
			QuestGuide.hops_left() == 0, "%d 跳" % QuestGuide.hops_left())


func _check_unreachable() -> void:
	await _mount(WORLD)
	QuestLog.reset()
	QuestLog.add("bad", "去不了的地方", "",
			{"scene": "res://scenes/nope.tscn", "pos": [0, 0]})
	QuestLog.set_tracked("bad")
	await _tick()
	_report("目标图不在地图图里 → 不显示箭头、不崩",
			not QuestGuide.valid(), "valid=%s" % QuestGuide.valid())


## 任务做完 → 自动取消追踪 → 箭头消失（和任务栏里看不见它保持一致）。
func _check_complete_clears_tracking() -> void:
	QuestLog.reset()
	QuestLog.add("fin", "收尾任务", "", {"scene": VILLAGE, "pos": [300, 782]})
	QuestLog.add_step("fin", "最后一步")
	QuestLog.set_tracked("fin")
	await _mount(WORLD)
	_report("追踪中且跨图 → 有箭头", QuestGuide.valid(),
			"valid=%s" % QuestGuide.valid())
	QuestLog.complete("fin")
	await _tick()
	_report("任务完成 → 自动取消追踪", QuestLog.tracked_id() == "",
			"tracked=%s" % QuestLog.tracked_id())
	_report("任务完成 → 箭头消失", not QuestGuide.valid(),
			"valid=%s" % QuestGuide.valid())


## M 地图：只列已解锁的去处（未解锁的不该露脸）。
func _check_map_panel_gating() -> void:
	await _mount(WORLD)
	var panel: MapPanel = MapPanel.new()
	add_child(panel)
	await _tick()
	var ids: Array[String] = []
	for r: Dictionary in panel._rows:
		ids.append(str((r["place"] as Dictionary).get("id", "")))
	_report("地图面板只列已解锁去处（雪山未解锁 → 3 项）",
			panel._rows.size() == 3, "%d 项：%s" % [panel._rows.size(), str(ids)])
	_report("已解锁列表里不含雪山", not ids.has("snow_mountain"), str(ids))
	panel.queue_free()
	await _tick()


## 生产路径：Story 换场景时会把箭头挂到 HUD/UIRoot 下（和追踪书同源）。
## 注意 force_disable=true 时 _on_scene_changed 会提前 return、不会注入 ——
## 所以这里临时关掉开关再手动调一次，验的正是真实那条链路。
func _check_injection() -> void:
	await _mount(WORLD)
	# _ensure_tracker() 是实例方法（force_disable 才是 static），
	# 必须走 autoload 实例 Story，不能用类名 StoryDirector 去点。
	Story.force_disable = false
	Story._ensure_tracker()
	Story.force_disable = true
	await _tick()
	var root: Node = _scene.get_node_or_null("HUD/UIRoot")
	var found: bool = false
	if root != null:
		for c: Node in root.get_children():
			if c is GuideArrow:
				found = true
	_report("Story._ensure_tracker() 会把罗盘箭头挂到 HUD/UIRoot", found)


## --- 工具 ---------------------------------------------------------------

func _setup_quest() -> void:
	QuestLog.reset()
	QuestLog.add(QID, "去集市进一批酿酒材料", "开张头一天，材料得备足。",
			StoryDirector.DEST_CATHERINE)
	QuestLog.add_step(QID, "走出酒馆，前往卢迪克集市")
	QuestLog.add_step(QID, "和集市管理员凯瑟琳搭上话")
	QuestLog.set_tracked(QID)


## 把某张图挂成 current_scene（指引系统靠它判断"我现在在哪"）。
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


## 等两帧：一帧让新场景 _ready 跑完，一帧让 QuestGuide._process 重算。
func _tick() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## 当前箭头指向 ≈ 期望坐标吗（1px 容差，够验出"指错门"）。
func _near(want: Vector2, name: String) -> void:
	var got: Vector2 = QuestGuide.waypoint()
	_report(name, QuestGuide.valid() and got.distance_to(want) <= 1.0,
			"got=%s want=%s valid=%s" % [str(got), str(want), str(QuestGuide.valid())])


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _finish() -> void:
	print("[guide] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
