extends Node
## 支线验收：
##   1) data/side_stories.json 结构完整（8 段、各有 npc_id 与 entries）
##   2) 序章没到 OPEN 时，任何 NPC 都不该触发支线
##   3) Story.stage = OPEN 后：支线角色**以顾客身份进店**（2026-10-30 起不再是
##      静态摆桩）：顾客生成器优先放"身上有未播支线"的人，交谈即播、播完记档
##   4) 哈特菲利亚线：发"黑松山脉·雪山"任务、解锁地图占位条目
## 运行： "<godot.exe>" --headless --path . res://tests/verify_sidestory.tscn --quit-after 6000

var scene: Node2D
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	# **必须关掉顾客自动补人**：哈特菲利亚开局就是名册常客，放着不管她会自己
	# 走进店里；_finish_story 推 E 关面板时泄漏的按键若恰好被她吃到，
	# 她的支线就被提前播掉记档，后面的正式断言全乱（排查半天的 flaky 根因）。
	CustomerSpawner.force_disable = true
	await get_tree().process_frame
	_check_data()
	await _run()
	print("[sidestory] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 数据 -------------------------------------------------------------

func _check_data() -> void:
	var arcs: Array = SideStory.arcs()
	var ok: bool = arcs.size() == 8
	var bad: String = ""
	var ids: Array[String] = []
	for a: Variant in arcs:
		var arc: Dictionary = a as Dictionary
		var id: String = str(arc.get("id", ""))
		var npc_id: String = str(arc.get("npc_id", ""))
		var entries: Array = arc.get("entries", []) as Array
		if id == "" or npc_id == "" or entries.is_empty():
			bad += "%s(缺字段) " % id
		if ids.has(id):
			bad += "%s(重复) " % id
		# 每条支线都得写"第几天才放"，且不能早于第 2 天
		if int(arc.get("min_day", 0)) < SideStory.FIRST_STORY_DAY:
			bad += "%s(min_day=%s) " % [id, arc.get("min_day", "缺")]
		ids.append(id)
	_report("支线数据 8 段、字段齐全、id 不重复、都有 min_day", ok and bad == "",
			"arcs=%d / %s" % [arcs.size(), bad])


# ---- 2/3/4. 跑一遍 -------------------------------------------------------

func _run() -> void:
	# 先验证"序章没完成不触发"：stage 默认 NONE，随便找个人都不该有支线
	_report("序章未完成时支线系统关闭（active=false、无待播）",
			not SideStory.active() and not SideStory.has_pending("broker_chiss"),
			"active=%s" % SideStory.active())

	# 把世界挂上并设成 current_scene，Story 的场景感知才会认
	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	Story.stage = StoryDirector.Stage.OPEN

	# 章节 gate 验证（激活前）：被 snow_logistics gate 的支线不应 pending
	_report("章节未激活时，被 gate 的支线（奇斯）不待播",
			SideStory.pending_for("broker_chiss").is_empty()
			and not SideStory.is_chapter_active("snow_logistics"),
			"chiss_pending=%s active=%s" % [SideStory.pending_for("broker_chiss").is_empty(),
			SideStory.is_chapter_active("snow_logistics")])

	# 激活雪山后勤章节（对应"玩家已接取委托"的状态），gate 打开
	SideStory.activate_chapter("snow_logistics")

	for i in 20:
		await get_tree().process_frame

	_report("OPEN 后 SideStory 激活", SideStory.active(), "stage=%d" % Story.stage)

	# 但**开张当天（第 1 天）**不出剧情：章节 gate 开了也没有待播、也没人进店
	_report("第 1 天（开张当天）不出剧情访客",
			SideStory.day() == 1 and not SideStory.unlocked()
			and not SideStory.has_pending("broker_chiss")
			and _npc_by_id("broker_chiss") == null,
			"day=%d unlocked=%s pending=%s chiss=%s" % [SideStory.day(),
			SideStory.unlocked(), SideStory.has_pending("broker_chiss"),
			_npc_by_id("broker_chiss") != null])

	# 跨天（第 2 天）→ 支线开闸，第一位访客登场。走真实信号，顺带验时钟接线。
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock != null:
		clock.day_changed.emit(clock.day + 1)
	for i in 20:
		await get_tree().process_frame

	_report("跨到第 2 天 → 支线开闸", SideStory.day() == 2 and SideStory.unlocked(),
			"day=%d unlocked=%s" % [SideStory.day(), SideStory.unlocked()])

	# 2026-10-30 改法：支线访客**不再静态摆桩**，改以顾客身份走正常入场流程
	_report("酒馆里没有静态摆桩的支线访客（改由顾客进店）",
			_npc_by_id("broker_chiss") == null and _npc_by_id("thief_eris") == null,
			"chiss=%s eris=%s" % [_npc_by_id("broker_chiss") != null,
			_npc_by_id("thief_eris") != null])

	# 让顾客生成器放人：身上还有没播支线的角色应当被优先请进来
	# （CustomerSpawner 不是 autoload，是酒馆场景里的 "Customers" 节点）
	var spawner: CustomerSpawner = scene.get_node_or_null("Customers") as CustomerSpawner
	_report("酒馆场景里有顾客生成器", spawner != null, "spawner=%s" % (spawner != null))
	# **别用 spawn_random**：哈特菲利亚也在候选访客里（章节已激活、她的引子 pending），
	# 随机挑到她就把引子提前播掉了，后面「哈特菲利亚线」的正式断言必然失败
	# —— 这个跟了很久的 flaky，真凶就是它。这里确定性地挑一位非 lucy 的访客。
	var pick: String = ""
	if spawner != null:
		for id: String in spawner._story_visitors():
			if id != "explorer_lucy":
				pick = id
				break
	var guest: Customer = spawner.spawn(pick) if pick != "" else null
	var guest_id: String = guest.npc_id if guest != null else ""
	_report("第一位进店的客人是剧情访客（身上有未播支线）",
			guest != null and SideStory.has_pending(guest_id),
			"guest=%s pending=%s" % [guest_id, SideStory.has_pending(guest_id)])

	# 头顶感叹号的三态：**远处亮着 → 靠近让位给 [E] → 播完熄灭**。
	# 测试玩家出生点可能正好在访客旁边，先把他挪远再验"远处亮着"。
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var saved_ppos: Vector2 = player.global_position if player != null else Vector2.ZERO
	if player != null:
		player.global_position = guest.global_position + Vector2(0, 120)
	for i in 4:
		await get_tree().physics_frame
	var mark_on: bool = guest != null and guest._mark != null and guest._mark.visible
	_report("远处看：访客头顶亮起感叹号", mark_on,
			"mark=%s" % (str(guest._mark.visible) if guest != null and guest._mark != null else "无"))

	# 走近（进 talk_range=46）→ [E] 交谈冒出来，感叹号让位，别俩提示叠一起
	if player != null:
		player.global_position = guest.global_position + Vector2(0, 26)
	for i in 6:
		await get_tree().physics_frame
	_report("玩家靠近 → [E] 交谈出现、感叹号让位",
			guest != null and guest._prompt != null and guest._prompt.visible
			and guest._mark != null and not guest._mark.visible,
			"prompt=%s mark=%s" % [
			str(guest._prompt.visible) if guest != null and guest._prompt != null else "无",
			str(guest._mark.visible) if guest != null and guest._mark != null else "无"])

	# 挪回远处：感叹号该重新亮起（他还有话没说完）
	if player != null:
		player.global_position = guest.global_position + Vector2(0, 120)
	for i in 6:
		await get_tree().physics_frame
	_report("退远后感叹号重新亮起（话还没说完）",
			guest != null and guest._mark != null and guest._mark.visible,
			"mark=%s" % (str(guest._mark.visible) if guest != null and guest._mark != null else "无"))
	# 还原玩家位置，别影响后面的用例
	if player != null:
		player.global_position = saved_ppos
	for i in 2:
		await get_tree().physics_frame

	# 跟他交谈 → 播支线（顾客对话里 SideStory.try_play 接管）
	var arc_id: String = str(SideStory.pending_for(guest_id).get("id", ""))
	if guest != null:
		SideStory.try_play(guest_id, guest)
	for i in 4:
		await get_tree().process_frame
	_report("与访客交谈弹出多说话人剧情面板",
			_story_panel() != null, "panel=%s" % (_story_panel() != null))
	_report("剧情面板拿到了付款人（卖酒才能收钱）",
			_story_panel() != null and _story_panel().get("trade_payer") == guest,
			"payer=%s" % (_story_panel().get("trade_payer") if _story_panel() != null else "无面板"))
	await _finish_story(arc_id)

	# 这段播完 → 他不再是"剧情访客"，以后按普通客人来（也可能压根不再来）
	for i in 4:
		await get_tree().process_frame
	_report("访客支线播完 → 不再算剧情访客",
			not SideStory.has_pending(guest_id), "guest=%s" % guest_id)

	# 聊完这段 → 感叹号熄灭（"第一次相遇"就提醒这一回）
	for i in 4:
		await get_tree().physics_frame
	_report("支线聊完 → 感叹号熄灭",
			guest != null and guest._mark != null and not guest._mark.visible,
			"mark=%s" % (str(guest._mark.visible) if guest != null and guest._mark != null else "无"))

	# 聊完这段 → ①登记认识（准备清单「跟 XX 对话」从此能打勾）
	#           ②直接离场，别留在吧台维持买酒状态（2026-10-30 用户要求）
	# 俄莉斯这类 NOT_CUSTOMER 不登记认识（不当酒客），不该因此判失败。
	_report("聊完支线 → 登记认识（不当酒客的角色除外）",
			Regulars.is_known(guest_id) or not Regulars.allows_customer(guest_id),
			"known=%s customer_ok=%s" % [Regulars.is_known(guest_id),
			Regulars.allows_customer(guest_id)])
	_report("聊完支线 → 直接离场、不留在吧台排队",
			not is_instance_valid(guest) or guest.state == Customer.State.LEAVING,
			"state=%s" % (str(guest.state) if is_instance_valid(guest) else "已退场"))

	# ---- 登场顺序闸（2026-10-30）：奇斯先演完，俄莉斯才轮得到 ----
	# guest 是随机挑的（奇斯或绯村都可能），所以走到这里奇斯那段可能已演、也可能还没有
	# —— 两种都合法，断言写成"没演完就必须被挡住"。
	var chiss_done: bool = SideStory.has_played("chiss_brewing_machine")
	_report("顺序闸：奇斯没演完前，俄莉斯不许出现",
			chiss_done or SideStory.pending_for("thief_eris").is_empty(),
			"chiss_done=%s eris_pending=%s" % [chiss_done,
			not SideStory.pending_for("thief_eris").is_empty()])
	if not chiss_done:
		# 直接把奇斯那段演掉（绕过随机性，确定性地推闸门）
		SideStory.try_play("broker_chiss", null)
		for i in 4:
			await get_tree().process_frame
		await _finish_story("chiss_brewing_machine")
	_report("奇斯演完 → 顺序闸放行俄莉斯",
			not SideStory.pending_for("thief_eris").is_empty(),
			"eris_pending=%s" % not SideStory.pending_for("thief_eris").is_empty())

	# 与哈特菲利亚（顾客）交谈：这里直接以 null 节点触发，验证任务+解锁。
	# 先等上一段的模态面板**彻底退场**（modal_ui 清空、call_deferred 跑完），
	# 光等固定帧数偶发弹不出面板。
	await _wait_modals_clear()
	SideStory.try_play("explorer_lucy", null)
	for i in 4:
		await get_tree().process_frame
	_report("哈特菲利亚线弹出剧情面板", _story_panel() != null,
			"panel=%s" % (_story_panel() != null))
	await _finish_story("hartfilia_snow_intro")

	_report("哈特菲利亚线播完 → 发「黑松山脉·雪山」任务",
			QuestLog.has("side_snow_intro"),
			"has_q=%s" % QuestLog.has("side_snow_intro"))
	_report("哈特菲利亚线播完 → 解锁雪山地图 flag",
			SideStory.is_unlocked("snow_mountain"),
			"unlocked=%s" % SideStory.is_unlocked("snow_mountain"))

	# 地图面板应多出"黑松山脉·雪山"一行（基础 3 + 1）
	var map_ps: PackedScene = load("res://scenes/ui/map_panel.tscn") as PackedScene
	if map_ps != null:
		var panel: UiPanel = map_ps.instantiate() as UiPanel
		scene.get_node("HUD").add_child(panel)
		for i in 4:
			await get_tree().process_frame
		var rows: Array = panel.get("_rows") as Array
		_report("M 地图出现「黑松山脉·雪山」占位行",
				rows.size() == 4, "rows=%d" % rows.size())
		panel.close()
		for i in 4:
			await get_tree().process_frame

	# 同一段支线不会重复播
	_report("支线只播一次（已播后不再 pending）",
			SideStory.has_played(arc_id) and not SideStory.has_pending(guest_id)
					and not SideStory.has_pending("explorer_lucy"),
			"played=%s guest_pending=%s lucy_pending=%s" % [
			SideStory.has_played(arc_id), SideStory.has_pending(guest_id),
			SideStory.has_pending("explorer_lucy")])


# ---- 工具 ---------------------------------------------------------------

func _story_panel() -> UiPanel:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if n is UiPanel:
			var e: Variant = (n as UiPanel).get("entries")
			if e is Array and (e as Array).size() > 0:
				return n as UiPanel
	return null


func _finish_story(arc_id: String) -> void:
	for i in 80:
		if _story_panel() == null:
			break
		_push_key(KEY_E)
		await get_tree().process_frame
		await get_tree().process_frame
	for i in 4:
		await get_tree().process_frame
	_report("支线 %s 播完且记档" % arc_id, SideStory.has_played(arc_id),
			"played=%s" % SideStory.has_played(arc_id))


## 等模态面板全部退场（关闭动画 + call_deferred 链跑完）。
## 连播两段剧情之间必须隔这一下，不然下一段偶发弹不出来（时序抖动的根源）。
func _wait_modals_clear(max_frames: int = 40) -> void:
	for i in max_frames:
		if get_tree().get_nodes_in_group("modal_ui").is_empty():
			break
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _npc_by_id(id: String) -> Npc:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = n as Npc
		if npc != null and npc.npc_id == id:
			return npc
	return null


func _push_key(keycode: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_viewport().push_input(down)
	var up: InputEventKey = InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_viewport().push_input(up)


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
