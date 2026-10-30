extends Node
## 雪山后勤触发验收：
##   1) 营业额阈值 = 300（2026-10-30 从 150 提到 300）
##   2) 章节 gate：snow_logistics 未激活时，**仍绑章节的**哈特菲利亚支线不 pending，
##      激活后放行；奇斯/俄莉斯已解绑章节门槛（序章就能进店），单独断言。
##   3) 触发链（**双条件**）：序章开张后，营业额累计 >= 阈值 **且** 该认识的人都认识，
##      才记"达标日"；次日（GameClock 跨过 00:00）凯瑟琳主动弹出委托提示。
##      —— 只达标一项都不算，这正是 2026-10-30 改动的核心。
##   4) 接取：在凯瑟琳菜单选"接取任务"（index 1）→ 激活章节 + 发「雪山科考队的委托」
##      任务 + 播放委托台词。
## 运行： "<godot.exe>" --headless --path . res://tests/verify_snow_logistics.tscn --quit-after 9000

var _pass := 0
var _fail := 0


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = false
	await get_tree().process_frame

	# 1) 阈值（2026-10-30 提到 300：光靠营业额会让玩家没跟人混熟就进剧情）
	_report("营业额阈值 = 300", Revenue.REVENUE_THRESHOLD_SNOW == 300.0,
			"threshold=%s" % Revenue.REVENUE_THRESHOLD_SNOW)

	# 挂世界场景并设成 OPEN（序章已走完的状态）
	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	Story.stage = StoryDirector.Stage.OPEN
	# 让 Story 认领本场景时钟并连线 day_changed（_on_scene_changed 里做）
	for i in 8:
		await get_tree().process_frame

	# 2) 章节 gate（激活前）。奇斯/俄莉斯已解绑，只剩哈特菲利亚仍绑章节。
	_report("章节未激活：仍绑章节的哈特菲利亚支线不 pending",
			SideStory.pending_for("explorer_lucy").is_empty()
			and not SideStory.is_chapter_active("snow_logistics"),
			"lucy=%s active=%s" % [
			SideStory.pending_for("explorer_lucy").is_empty(),
			SideStory.is_chapter_active("snow_logistics")])
	_report("奇斯/俄莉斯支线已解绑章节（开张后自然进店）",
			_arc_chapter("chiss_brewing_machine") == ""
			and _arc_chapter("eris_artifact_runes") == "",
			"chiss=%s eris=%s" % [_arc_chapter("chiss_brewing_machine"),
					_arc_chapter("eris_artifact_runes")])

	# 3) 触发链：制造营业额（Inventory.earn → Revenue 正增量 → Story._on_revenue 记达标日）
	#    少 1 铜时不该达标，正好达阈值才达标 —— 顺便钉住"不是靠运气过线"
	var need: int = int(Revenue.REVENUE_THRESHOLD_SNOW)
	Inventory.earn(need - 1)
	await get_tree().process_frame
	_report("营业额差 1 铜时未达标", Revenue.total < Revenue.REVENUE_THRESHOLD_SNOW,
			"total=%s / threshold=%s" % [Revenue.total, Revenue.REVENUE_THRESHOLD_SNOW])
	Inventory.earn(1)
	await get_tree().process_frame
	_report("营业额累计 >= 阈值", Revenue.total >= Revenue.REVENUE_THRESHOLD_SNOW,
			"total=%s" % Revenue.total)

	# 3.5) **双条件**：钱够了但人没认全 → 仍不算达标（2026-10-30 新增）
	Story._snow_revenue_day = 0
	Story._on_revenue(Revenue.total)
	await get_tree().process_frame
	_report("只营业额达标、人没认全 → 不记达标日", Story._snow_revenue_day == 0,
			"day_mark=%d" % Story._snow_revenue_day)

	# 补齐名单上的人（模拟在酒馆里跟他们搭过话 → mark_known 发 changed → Story 重算）
	for id: String in Regulars.required_for("snow_logistics"):
		Regulars.mark_known(id)
	await get_tree().process_frame
	_report("补齐三人认识 → 记下达标日", Story._snow_revenue_day > 0,
			"day_mark=%d" % Story._snow_revenue_day)

	# 次日跨天：直接驱动场景时钟跨过 00:00（day 1 → 2）
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock != null:
		clock.advance(60.0 * 24.0)   # 足够跨过一整天（seconds_per_hour=30）
	await get_tree().process_frame
	await get_tree().process_frame
	_report("跨天后凯瑟琳弹出委托提示（snow_offered=true）",
			Story.snow_offered, "snow_offered=%s" % Story.snow_offered)

	# 4) 接取：模拟在凯瑟琳菜单选第 2 项（"接取任务"）
	Story._on_catherine_choice(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_report("接取后章节激活", SideStory.is_chapter_active("snow_logistics"),
			"active=%s" % SideStory.is_chapter_active("snow_logistics"))
	_report("接取后 snow_started=true", Story.snow_started,
			"started=%s" % Story.snow_started)
	# 接取这一下同时把第一章导演拉起来（Story._start_snow_logistics 末尾调 begin）
	_report("接取后第一章导演启动（ChapterStory.is_active）", ChapterStory.is_active(),
			"active=%s" % ChapterStory.is_active())
	_report("接取后发第一章任务（ch1_frost，取代旧的 side_snow_logistics）",
			QuestLog.has("ch1_frost") and not QuestLog.has("side_snow_logistics"),
			"has_ch1=%s has_old=%s" % [QuestLog.has("ch1_frost"),
					QuestLog.has("side_snow_logistics")])

	# 章节激活后，3 条雪山支线应放行（取哈特菲利亚验证）
	_report("章节激活后雪山支线放行（哈特菲利亚 pending）",
			not SideStory.pending_for("explorer_lucy").is_empty(),
			"lucy_pending=%s" % (not SideStory.pending_for("explorer_lucy").is_empty()))

	_finish()


## 某条支线绑的章节（空串 = 没有章节门槛，随时可播）。
func _arc_chapter(arc_id: String) -> String:
	for a: Variant in SideStory.arcs():
		var d: Dictionary = a as Dictionary
		if str(d.get("id", "")) == arc_id:
			return str(d.get("chapter", ""))
	return "@missing"


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s" % name)
	else:
		_fail += 1
		print("[check] FAIL  %s  (%s)" % [name, detail])


func _finish() -> void:
	print("PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
