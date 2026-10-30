extends Node
## 任务追踪「笔记本图标 → 点开任务清单」验收。
## 手动把 QuestTracker 挂到 world 的 HUD 下，按一下图标按钮，
## 断言：弹出 QuestPanel；模态开着时再按不重复开；图标贴图已加载。

const ENTRY_SCENE := "res://scenes/world.tscn"

var passed: int = 0
var failed: int = 0

var scene: Node = null


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	scene = (load(ENTRY_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame

	var hud: Node = scene.get_node_or_null("HUD")
	_report("world 有 HUD", hud != null, hud.get_path() if hud != null else "缺 HUD")
	if hud == null:
		_finish()
		return

	var tracker: QuestTracker = QuestTracker.new()
	hud.add_child(tracker)
	await get_tree().process_frame

	# 找图标按钮 + 其笔记本贴图
	var btn: Button = null
	for c: Node in tracker.get_children():
		if c is Button:
			btn = c as Button
	var icon: TextureRect = null
	if btn != null and btn.get_child_count() > 0:
		icon = btn.get_child(0) as TextureRect
	_report("追踪器头部有笔记本图标按钮", btn != null and icon != null,
			"btn=%s icon_tex=%s" % [btn != null,
			icon.texture != null if icon != null else false])
	_report("笔记本贴图已加载(64x64)",
			icon != null and icon.texture != null
					and icon.texture.get_width() == 64 and icon.texture.get_height() == 64,
			"%dx%d" % [icon.texture.get_width() if icon != null and icon.texture != null else -1,
			icon.texture.get_height() if icon != null and icon.texture != null else -1])

	if btn == null:
		_finish()
		return

	# 点一下 → 弹出任务清单面板
	var before: int = _panel_count(hud)
	btn.pressed.emit()
	await get_tree().process_frame
	var after: int = _panel_count(hud)
	_report("点笔记本图标弹出任务清单面板", after == before + 1,
			"面板数 %d → %d" % [before, after])

	# 模态开着时再点 → 不重复开
	btn.pressed.emit()
	await get_tree().process_frame
	var after2: int = _panel_count(hud)
	_report("模态开着时再点不重复开", after2 == after,
			"面板数 %d（应不变）" % after2)

	# 弹出的面板确实是 QuestPanel 且进了 modal_ui 组
	var panel: Node = _first_panel(hud)
	_report("弹出的是 QuestPanel 且进 modal_ui 组",
			panel is QuestPanel and panel.is_in_group("modal_ui"),
			panel.get_class() if panel != null else "无")

	# ---- 2026-10-26：常驻追踪卡已删，改为图标自带角标 ----
	QuestLog.reset()
	await get_tree().process_frame
	var idle_h: float = tracker.size.y
	_report("无任务时不长卡片（高度=图标底板）",
			is_equal_approx(idle_h, float(QuestTracker.HEIGHT)) and not tracker._badge.visible,
			"h=%s 角标=%s" % [idle_h, tracker._badge.visible])

	QuestLog.add("t1", "测试任务")
	QuestLog.add_step("t1", "第一步")
	await get_tree().process_frame
	_report("有任务时亮起角标并显示剩余段数",
			tracker._badge.visible and tracker._badge_text.text == "1",
			"角标=%s 文本=%s" % [tracker._badge.visible, tracker._badge_text.text])
	_report("有任务时高度不变（不再长出追踪卡）",
			is_equal_approx(tracker.size.y, idle_h), "h=%s → %s" % [idle_h, tracker.size.y])
	_report("有任务时描边亮起",
			tracker._rim.visible, "rim=%s" % tracker._rim.visible)

	QuestLog.complete("t1")
	await get_tree().process_frame
	_report("任务做完：角标与描边一起消失",
			not tracker._badge.visible and not tracker._rim.visible,
			"角标=%s 描边=%s" % [tracker._badge.visible, tracker._rim.visible])
	QuestLog.reset()

	_finish()


func _panel_count(hud: Node) -> int:
	var n: int = 0
	for c: Node in hud.get_children():
		if c is QuestPanel:
			n += 1
	return n


func _first_panel(hud: Node) -> Node:
	for c: Node in hud.get_children():
		if c is QuestPanel:
			return c
	return null


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _finish() -> void:
	print("[quest_icon] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
