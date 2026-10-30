extends Node
## 章节解锁【双条件】验收（2026-10-30）。
##
## 改动背景：以前只看累计营业额，玩家钱够了就进剧情，结果剧情里一堆没见过的人。
## 现在要**两个条件同时满足**：
##   ① 累计营业额达标（第一章 150 → 300）
##   ② Regulars 名单上该认识的人都认识了（Regulars.CHAPTER_REQUIRED）
## 而且这两件事都写进**任务栏的准备清单**（以前只在打烊结算卡上露一眼）。
##
## 本用例盯四件事：
##   1) 序章开张后清单真的建出来，步骤 = 营业额 + 每位待认识的人；
##   2) 只营业额达标（人没认全）→ 不算达标；
##   3) 把认识补齐 → 当天达标；
##   4) 反向：认识齐了但钱不够（阈值确实提到 300，不是旧 150）。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_chapter_gate.tscn

const CH: String = "snow_logistics"
const QID: String = "prep_snow"

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	CustomerSpawner.force_disable = true
	# 让 Story 的逻辑真的跑起来（_on_regulars_changed 会看 force_disable）。
	# 但直接把 stage 推到 OPEN，跳过序章流程；不挂场景，_on_scene_changed 不会乱动。
	StoryDirector.force_disable = false
	Story.stage = StoryDirector.Stage.OPEN
	QuestLog.reset()
	Regulars.reset()
	Revenue.total = 0.0
	Story._snow_revenue_day = 0
	Story.snow_offered = false
	Story.snow_started = false
	await get_tree().process_frame

	_check_threshold()
	_check_prep_created()
	_check_revenue_only()
	await _check_known_completes()
	_check_reverse_order()
	await _check_menu_removed()

	# 收尾：别把状态留给后续用例
	StoryDirector.force_disable = true
	Story.snow_offered = false
	Story.snow_started = false
	Story._snow_revenue_day = 0
	Revenue.total = 0.0
	QuestLog.reset()
	Regulars.reset()
	print("[ch_gate] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 门槛值 -----------------------------------------------------------

func _check_threshold() -> void:
	_report("第一章营业额门槛已提到 300（原 150）",
			is_equal_approx(Revenue.REVENUE_THRESHOLD_SNOW, 300.0),
			"%s" % Revenue.REVENUE_THRESHOLD_SNOW)
	var req: Array[String] = Regulars.required_for(CH)
	var expect: Array[String] = ["broker_chiss", "ronin_himura"]
	_report("第一章待认识名单 = 奇斯/绯村（俄莉斯 2026-10-30 起不当酒客，已移出名单）",
			req == expect, "%s" % str(req))
	_report("名单不含当顾客也不算的老板娘",
			not req.has("tavern_cuige"), "%s" % str(req))
	_report("名单不含开局就熟的首发四人",
			not (req.has("explorer_lucy") or req.has("miner_simon")
				or req.has("dwarf_war_edward") or req.has("market_catherine")),
			"%s" % str(req))


# ---- 2. 准备清单 ---------------------------------------------------------

func _check_prep_created() -> void:
	Story._ensure_prep(CH)
	_report("开张后任务栏出现准备清单", QuestLog.has(QID), "has=%s" % QuestLog.has(QID))

	var steps: Array = _steps(QID)
	# 1 条营业额 + 2 条对话（俄莉斯已移出名单）
	_report("清单步骤数 = 1(营业额) + 2(对话)", steps.size() == 3,
			"steps=%d" % steps.size())
	if not steps.is_empty():
		var first: Dictionary = steps[0] as Dictionary
		_report("第 0 步是累计营业额，目标 300",
				str(first["text"]) == "累计营业额" and int(first["need"]) == 300,
				"text=%s need=%d" % [first["text"], first["need"]])
	_report("清单里列出要对话的两个名字",
			_has_step("跟 奇斯 对话") and _has_step("跟 绯村 对话")
			and not _has_step("俄莉斯"),
			"%s" % _step_texts(QID))


# ---- 3. 只营业额达标（人没认全）----------------------------------------

func _check_revenue_only() -> void:
	Revenue.total = 300.0
	Story._snow_revenue_day = 0
	Story._on_revenue(300.0)
	_report("营业额 300 但人没认全 → 不算达标（不记达标日）",
			Story._snow_revenue_day == 0,
			"day_mark=%d" % Story._snow_revenue_day)
	_report("清单里营业额那步已打勾", _step_done(QID, 0), "%s" % _step_texts(QID))
	_report("但对话那几步还没勾",
			not _step_done(QID, 1) and not _step_done(QID, 2),
			"%s" % _step_texts(QID))


# ---- 4. 补齐认识 → 当天达标 ---------------------------------------------

func _check_known_completes() -> void:
	# 直接登记（模拟玩家在酒馆里跟他们搭上话）—— mark_known 会发 changed，
	# Story 接着重算，最后一块拼图补上就该当天达标。
	for id: String in Regulars.required_for(CH):
		Regulars.mark_known(id)
	await get_tree().process_frame
	_report("三人补齐后 → 记下达标日", Story._snow_revenue_day > 0,
			"day_mark=%d" % Story._snow_revenue_day)
	_report("清单所有步骤都打勾（这条任务算完成，会被窗口挤走）",
			_all_steps_done(QID), "%s" % _step_texts(QID))


# ---- 5. 反向：认识齐但钱不够 -------------------------------------------

func _check_reverse_order() -> void:
	# 认识此时已齐（上一用例留下的），把营业额压回 200：旧阈值 150 会过，新 300 不该过
	Revenue.total = 200.0
	Story._snow_revenue_day = 0
	Story._on_revenue(200.0)
	_report("200 铜不够（阈值确已从 150 提到 300）",
			Story._snow_revenue_day == 0,
			"day_mark=%d" % Story._snow_revenue_day)
	_report("水位线：认识齐 ≠ 达标，钱也必须到位",
			Regulars.all_known_for(CH), "all_known=%s" % Regulars.all_known_for(CH))


# ---- 6. 经营页不该再显示解锁进度 ---------------------------------------

func _check_menu_removed() -> void:
	var ps: PackedScene = load("res://scenes/ui/day_report_panel.tscn") as PackedScene
	_report("打烊结算卡场景能加载", ps != null, "")
	if ps == null:
		return
	var panel: Node = ps.instantiate()
	panel.set("report", {"day": 3, "revenue": 80, "wines": 4, "best": 80, "hours": 3})
	add_child(panel)
	await get_tree().process_frame
	var texts: Array[String] = []
	_collect_texts(panel, texts)
	_report("结算卡不再显示『雪山委托(累计)』进度行",
			not _any_contains(texts, "雪山委托"), "%s" % str(texts))
	_report("结算卡仍然显示今日进账", _any_contains(texts, "今日进账"), "%s" % str(texts))
	panel.queue_free()


# ---- 工具 ---------------------------------------------------------------

func _steps(qid: String) -> Array:
	var q: Dictionary = QuestLog.quest(qid)
	return q.get("steps", [])


func _step_done(qid: String, i: int) -> bool:
	var steps: Array = _steps(qid)
	if i < 0 or i >= steps.size():
		return false
	return bool((steps[i] as Dictionary)["done"])


func _all_steps_done(qid: String) -> bool:
	var steps: Array = _steps(qid)
	if steps.is_empty():
		return false
	for s: Variant in steps:
		if not bool((s as Dictionary)["done"]):
			return false
	return true


func _has_step(needle: String) -> bool:
	return _step_texts(QID).contains(needle)


func _step_texts(qid: String) -> String:
	var out: String = ""
	for s: Variant in _steps(qid):
		var d: Dictionary = s as Dictionary
		out += "%s%s | " % [str(d["text"]), "(✓)" if bool(d["done"]) else ""]
	return out


func _collect_texts(node: Node, out: Array[String]) -> void:
	var l: Label = node as Label
	if l != null:
		out.append(l.text)
	for c: Node in node.get_children():
		_collect_texts(c, out)


func _any_contains(texts: Array[String], needle: String) -> bool:
	for t: String in texts:
		if t.contains(needle):
			return true
	return false


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
