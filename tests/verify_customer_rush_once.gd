extends Node
## 验收：开场 rush 一生只放一次。
##   "<godot.exe>" --headless --path . res://tests/verify_customer_rush_once.tscn --quit-after 9000
##
## 复现路径：序章开张后进酒馆（应涌进 opening_rush_count 人）→ 出门 → 再进门。
## 旧实现里 CustomerSpawner 的 _running / _rush_remaining 是实例变量，换场景重建后
## 清零，于是每次进门都重新放人。现在用 static _opening_rush_done 兜住。

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	CustomerSpawner.force_disable = false
	StoryDirector.force_disable = false
	await get_tree().process_frame
	Story.stage = StoryDirector.Stage.OPEN
	# 招牌挂上才算营业（v2：顾客闸门 = 序章完成 且 招牌挂着）
	Story.open_business()

	# ---- 第一次进门：应当放 rush ----
	var w1: Node2D = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(w1)
	get_tree().current_scene = w1
	for i in 300:
		await get_tree().physics_frame
	var s1: CustomerSpawner = w1.get_node("Customers") as CustomerSpawner
	_report("首次开张：开场 rush 放人（≥%d）" % s1.opening_rush_count,
			s1.active_count() >= s1.opening_rush_count,
			"active=%d / rush_count=%d / rush_day=%d" % [s1.active_count(),
			s1.opening_rush_count, CustomerSpawner._rush_day])

	# ---- 出门 → 再进门（等价于换场景重建 spawner）----
	var w2: Node2D = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(w2)
	get_tree().current_scene = w2
	w1.queue_free()
	for i in 3:
		await get_tree().process_frame
	# 等约 4 秒：若 rush 会重播，这 3 人早该进来了（first_delay=6s 不含 rush）
	for i in 240:
		await get_tree().physics_frame
	var s2: CustomerSpawner = w2.get_node("Customers") as CustomerSpawner
	_report("再次进门：开场 rush 不重播（客流仍为 0）", s2.active_count() == 0,
			"active=%d" % s2.active_count())
	_report("rush 标记已置位（static，每天一次）", CustomerSpawner._rush_day > 0,
			"rush_day=%d" % CustomerSpawner._rush_day)

	print("[rush_once] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
