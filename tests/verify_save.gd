extends Node
## 存档系统验收：
##   "<godot.exe>" --headless --path . res://tests/verify_save.tscn --quit-after 9000
##
## 覆盖：
##   1) 左上角存档提示条（任务书下面那条）存在、文案与坐标对
##   2) F5 打开存档面板，E 存进 1 号槽；meta（天/时/钱/场景）写对了
##   3) 「继续游戏」指针指向刚存的槽
##   4) 把状态改花后读档，铜币 / 物品 / 任务 / 营业额 / 时钟 / 站位 全部回来
##   5) 覆盖已有存档要按两次 E（第一次只上膛）
##   6) 标题界面：有档时默认停在「继续游戏」；「读取存档」弹出的是 load 模式面板
##
## ⚠ 这个用例会**清空** user://save_*.cfg（开跑前清、跑完再清），免得旧档影响断言。

const WORLD: String = "res://scenes/world.tscn"
const TITLE: String = "res://scenes/title.tscn"

var _pass: int = 0
var _fail: int = 0

var _saved_pos: Vector2 = Vector2.ZERO
var _saved_copper: int = 0
var _saved_total: float = 0.0


func _ready() -> void:
	_clear_saves()
	CustomerSpawner.force_disable = true      # 不掺顾客
	StoryDirector.force_disable = false       # 要 HUD 注入，所以关掉总闸不行
	Story.stage = StoryDirector.Stage.OPEN    # 直接当已开张：不放序章、不弹卡
	await get_tree().process_frame

	# ---- 1) 进酒馆，看提示条 ----
	var scene: Node = (load(WORLD) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(8)

	var hud: Node = scene.get_node_or_null("HUD/UIRoot")
	var hint: Control = _find_hint(hud)
	_report("HUD 左上角有存档提示条", hint != null, "hud=%s" % hud)
	if hint != null:
		_report("提示条写着「[F5] 存档」", _labels_text(hint).contains("[F5] 存档"),
				_labels_text(hint))
		_report("提示条贴在任务书下面（8,62）", hint.position == Vector2(8, 62),
				str(hint.position))

	# ---- 1b) 设置提示条：在存档条下面，点一下要能开设置面板 ----
	var shint: Control = _find_settings_hint(hud)
	_report("HUD 有设置提示条", shint != null, "hint=%s" % shint)
	if shint != null:
		_report("设置条写着「[F6] 设置」", _labels_text(shint).contains("[F6] 设置"),
				_labels_text(shint))
		_report("设置条在存档条正下方", shint.position.y > hint.position.y
				and absf(shint.position.x - hint.position.x) < 0.5,
				"%s vs %s" % [shint.position, hint.position])
		var cev: InputEventMouseButton = InputEventMouseButton.new()
		cev.button_index = MOUSE_BUTTON_LEFT
		cev.pressed = true
		cev.position = shint.size * 0.5
		shint._gui_input(cev)
		await _wait(4)
		_report("点设置条打开设置面板", _modal(UiPanel) != null, "modal=%s" % _modal(UiPanel))
		_push_key(KEY_ESCAPE)
		await _wait(4)
		_report("Esc 关掉设置面板", _modal(UiPanel) == null, "")

	# ---- 2) 造一份"一眼能认出来"的状态 ----
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	clock.day = 3
	clock.set_time(14, 20)
	Inventory.earn(120)                       # 营业额跟着涨（Revenue 监听铜币）
	Inventory.add("ginger", 4)
	QuestLog.add("test_q", "测试任务", "", {})
	var player: Player = _player()
	_saved_pos = Vector2(240, 200)
	player.global_position = _saved_pos
	# 等物理帧把人物摆稳：碰撞体可能把它挤开一两像素，存档记的是"稳住之后"的坐标
	await _wait(10)
	_saved_pos = player.global_position
	await _wait(2)
	_saved_copper = Inventory.copper
	_saved_total = Revenue.total

	_report("能存（合法场景）", SaveGame.block_reason() == "", SaveGame.block_reason())

	# ---- 3) F5 → 面板 → E 存档 ----
	_push_key(KEY_F5)
	await _wait(4)
	var panel: SavePanel = _modal(SavePanel) as SavePanel
	_report("F5 打开存档面板", panel != null, "panel=%s" % panel)
	_report("面板默认 save 模式", panel != null and panel.mode == "save",
			panel.mode if panel != null else "n/a")
	if panel != null:
		_push_key(KEY_E)
		# 面板存完会停 0.45s 让人看清那行摘要变了再收摊 —— 按真实时间等
		await get_tree().create_timer(0.8).timeout
		await _wait(3)
	_report("存完面板自己关上", _modal(SavePanel) == null, "modal=%s" % _modal(SavePanel))

	_report("1 号槽写进去了", SaveGame.has_slot(1), "")
	var meta: Dictionary = SaveGame.meta_of(1)
	_report("meta 记住第 3 天 14:20",
			int(meta.get("day", 0)) == 3 and int(meta.get("hour", 0)) == 14
			and int(meta.get("minute", 0)) == 20, str(meta))
	_report("meta 记住铜币", int(meta.get("money", -1)) == _saved_copper,
			"%s vs %d" % [meta.get("money"), _saved_copper])
	_report("meta 记住场景", str(meta.get("scene", "")).ends_with("world.tscn"),
			str(meta.get("scene", "")))
	_report("「继续游戏」指针指向 1 号槽", SaveGame.last_slot() == 1,
			str(SaveGame.last_slot()))
	_report("2 号槽还是空的", not SaveGame.has_slot(2), "")

	# ---- 4) 把状态改花 → 读档 → 应该整份回来 ----
	Inventory.spend(Inventory.copper)
	Inventory.remove("ginger", 4)
	QuestLog.reset()
	clock.day = 9
	clock.set_time(3, 0)
	_player().global_position = Vector2(100, 100)
	await _wait(2)
	_report("改过之后状态确实变了",
			Inventory.copper == 0 and clock.day == 9 and not QuestLog.has("test_q"),
			"copper=%d day=%d" % [Inventory.copper, clock.day])

	var ok: bool = SaveGame.load_slot(1)
	_report("load_slot 返回成功", ok, "")
	await _wait(30)                           # 切场景 + SceneBootstrap 落位

	clock = get_tree().get_first_node_in_group("game_clock") as GameClock
	player = _player()
	_report("读档回到第 3 天 14:20",
			clock != null and clock.day == 3 and clock.hour == 14 and clock.minute == 20,
			"day=%s %02d:%02d" % [clock.day if clock != null else "n/a",
					clock.hour if clock != null else 0,
					clock.minute if clock != null else 0])
	_report("读档恢复铜币", Inventory.copper == _saved_copper,
			"%d vs %d" % [Inventory.copper, _saved_copper])
	_report("读档恢复物品", Inventory.count("ginger") == 4,
			str(Inventory.count("ginger")))
	_report("读档恢复任务", QuestLog.has("test_q"), "")
	_report("读档恢复营业额", is_equal_approx(Revenue.total, _saved_total),
			"%.0f vs %.0f" % [Revenue.total, _saved_total])
	_report("读档落回原地", player != null
			and player.global_position.distance_to(_saved_pos) <= 2.0,
			"%s vs %s" % [player.global_position if player != null else "n/a",
					_saved_pos])
	_report("读档后不带序章（stage=OPEN）", Story.stage == StoryDirector.Stage.OPEN,
			str(Story.stage))

	# ---- 5) 覆盖要按两次 ----
	Inventory.earn(77)                        # 让"新旧两份"明显不同
	var total_now: float = Revenue.total
	_push_key(KEY_F5)
	await _wait(4)
	_push_key(KEY_E)                          # 第一次：只上膛
	await _wait(5)
	_report("第一次 E 不覆盖（等确认）",
			not is_equal_approx(float(SaveGame.meta_of(1).get("revenue", 0.0)), total_now),
			"meta=%.0f now=%.0f" % [float(SaveGame.meta_of(1).get("revenue", 0.0)),
					total_now])
	_push_key(KEY_E)                          # 第二次：真写
	await get_tree().create_timer(0.8).timeout
	await _wait(3)
	_report("第二次 E 才覆盖",
			is_equal_approx(float(SaveGame.meta_of(1).get("revenue", 0.0)), total_now),
			"meta=%.0f now=%.0f" % [float(SaveGame.meta_of(1).get("revenue", 0.0)),
					total_now])

	# ---- 6) 标题界面 ----
	get_tree().change_scene_to_file(TITLE)
	await _wait(70)                           # 淡入 0.85s
	var title: Node = get_tree().current_scene
	_report("切到开始界面", title != null
			and title.scene_file_path.ends_with("title.tscn"),
			title.scene_file_path if title != null else "n/a")
	_report("有存档 → 默认停在「继续游戏」", int(title.get("_index")) == 0,
			"index=%s" % title.get("_index"))
	var items: Array = title.get("_items") as Array
	_report("「继续游戏」已点亮", items.size() > 0 and bool(items[0].get("enabled")),
			"")

	_push_key(KEY_S)                          # 继续游戏 → 读取存档
	await get_tree().process_frame
	_push_key(KEY_E)
	await _wait(5)
	var load_panel: SavePanel = _modal(SavePanel) as SavePanel
	_report("「读取存档」打开的是 load 模式面板",
			load_panel != null and load_panel.mode == "load",
			load_panel.mode if load_panel != null else "n/a")
	if load_panel != null:
		_push_key(KEY_S)                      # 2 号槽（空）
		await get_tree().process_frame
		_push_key(KEY_E)                      # 空槽：只提示，不读
		await _wait(3)
		_report("空档位不给读（面板还开着）", _modal(SavePanel) != null, "")
		_push_key(KEY_ESCAPE)
		await _wait(3)
		_report("Esc 关掉读取面板", _modal(SavePanel) == null, "")

	# ---- 7) 「继续游戏」端到端：真能进游戏，钱对得上 ----
	_push_key(KEY_W)                          # 读取存档 → 继续游戏
	await get_tree().process_frame
	_report("回到「继续游戏」", int(title.get("_index")) == 0,
			"index=%s" % title.get("_index"))
	var money_before: int = int(SaveGame.meta_of(1).get("money", -1))
	_push_key(KEY_E)
	await get_tree().create_timer(1.2).timeout     # 淡出 0.55s + 切场景
	await _wait(20)
	var now_scene: Node = get_tree().current_scene
	_report("继续游戏真的进了酒馆",
			now_scene != null and now_scene.scene_file_path.ends_with("world.tscn"),
			now_scene.scene_file_path if now_scene != null else "n/a")
	_report("继续游戏后铜币与存档一致", Inventory.copper == money_before,
			"%d vs %d" % [Inventory.copper, money_before])

	# ---- 8) 删档：同样要按两次；删完「继续游戏」指针要清掉 ----
	_push_key(KEY_F5)
	await _wait(5)
	_report("回到游戏里还能开存档面板", _modal(SavePanel) != null, "")
	_push_key(KEY_X)                          # 第一次：上膛
	await _wait(4)
	_report("第一次 X 不删（等确认）", SaveGame.has_slot(1), "")
	_push_key(KEY_X)                          # 第二次：真删
	await _wait(6)
	_report("第二次 X 删掉了 1 号槽", not SaveGame.has_slot(1), "")
	_report("删档后 meta 为空", SaveGame.meta_of(1).is_empty(), str(SaveGame.meta_of(1)))
	_report("删档后「继续游戏」指针清空", SaveGame.last_slot() == 0,
			str(SaveGame.last_slot()))
	_report("删档后没有任何档可读", not SaveGame.any_slot(), "")
	_push_key(KEY_X)                          # 空档位再按：不动作、不报错
	await _wait(3)
	_report("空档位按 X 不会出事", not SaveGame.has_slot(1), "")
	_push_key(KEY_ESCAPE)
	await _wait(3)

	# ---- 9) 删光档位后，标题界面的两行立刻变灰 ----
	get_tree().change_scene_to_file(TITLE)
	await _wait(70)
	var title2: Node = get_tree().current_scene
	var items2: Array = title2.get("_items") as Array
	_report("没档了 → 「继续游戏」置灰", items2.size() > 0
			and not bool(items2[0].get("enabled")), "")
	_report("没档了 → 默认落回「开始游戏」", int(title2.get("_index")) == 2,
			"index=%s" % title2.get("_index"))

	_clear_saves()
	_finish()


# ---- 工具 ------------------------------------------------------------------

func _clear_saves() -> void:
	SaveGame.clear_all_slots()


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _find_hint(root: Node) -> Control:
	if root == null:
		return null
	for n: Node in root.get_children():
		if n is SaveHint:
			return n as Control
	return null


func _find_settings_hint(root: Node) -> Control:
	if root == null:
		return null
	for n: Node in root.get_children():
		if n is SettingsHint:
			return n as Control
	return null


func _labels_text(root: Node) -> String:
	var out: String = ""
	if root is Label:
		out += (root as Label).text
	for c: Node in root.get_children():
		out += _labels_text(c)
	return out


func _modal(type: Variant) -> UiPanel:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and is_instance_of(n, type):
			return n as UiPanel
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


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s | %s" % [name, detail])
	else:
		_fail += 1
		print("[check] FAIL  %s | %s" % [name, detail])


func _finish() -> void:
	print("[verify_save] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
