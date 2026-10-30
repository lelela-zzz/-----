extends Node
## 对话框 / 面板的画布适配验收。
##   "<godot.exe>" --headless --path . res://tests/verify_dialogue_layout.tscn --quit-after 9000
##
## 守三件事：
##   1) 面板的注入点是 HUD/UIRoot（640×384 逻辑坐标 + 整体放大），**不是** CanvasLayer；
##      挂错地方的话 640 坐标的老布局会缩在屏幕左上角、字号还是 1×。
##   2) 底部对话条贴底、左右各留 16、底边距 12，宽度铺满画布。
##   3) 兜底：把面板硬塞进一个尺寸不对的容器（比如 CanvasLayer 的 1280×768），
##      它会自己换算成等比铺满，既不留黑边也不越界。

const ENTRY := "res://scenes/world.tscn"

var scene: Node2D
var player: Node2D
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	scene = (load(ENTRY) as PackedScene).instantiate()
	# 挂在测试节点下（其它验收用例都是这么干的）：current_scene 仍是测试节点，
	# 正好顺便验到 UiStyle.ui_layer 的"全树找 UIRoot"兜底分支。
	add_child(scene)
	await _wait(4)

	player = scene.get_node("Sorted/Player") as Node2D
	_check_inject_point()
	await _check_dialogue_bar()
	_check_foreign_container()

	print("[dlg_layout] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 注入点 -------------------------------------------------------------

func _check_inject_point() -> void:
	var ui: Node = scene.get_node_or_null("HUD/UIRoot")
	_report("HUD 下有 UIRoot 画布容器", ui != null,
			"UIRoot=%s" % (ui != null))
	if ui == null:
		return
	var c: Control = ui as Control
	var want: Vector2 = WindowScale.render_scale()
	_report("UIRoot 是 640×384 且按 render_scale 整体放大",
			c.size.is_equal_approx(Vector2(640, 384)) and c.scale.is_equal_approx(want),
			"size=%s scale=%s 期望 scale=%s" % [c.size, c.scale, want])

	# UiStyle.ui_layer 必须给出 UIRoot，而不是 CanvasLayer
	var got: Node = UiStyle.ui_layer(self)
	_report("UI 注入点解析到 UIRoot（不是 CanvasLayer）",
			got != null and got.name == "UIRoot",
			"解析到 %s" % (got.name if got != null else "<null>"))


# ---- 2. 对话条矩形 ---------------------------------------------------------

func _check_dialogue_bar() -> void:
	# 把老板娘摆到玩家旁边，按 E 开单说话人对话框
	var npc: Npc = _place_cuige(Vector2(76, 100))
	if npc == null:
		_report("按 E 弹出对话框", false, "萃歌实例化失败")
		return
	player.global_position = Vector2(80, 106)
	await _wait(8)
	_push_interact()
	await _wait(6)

	var box: UiPanel = _panel()
	_report("按 E 弹出对话框", box != null, "box=%s" % (box != null))
	if box == null:
		return

	_report("对话框挂在 HUD/UIRoot 里（不是 CanvasLayer）",
			box.get_parent() != null and box.get_parent().name == "UIRoot",
			"父节点=%s" % (box.get_parent().name if box.get_parent() else "<null>"))
	_report("对话框自身锁成 640×384 画布、1× 缩放（由 UIRoot 放大）",
			box.size.is_equal_approx(Vector2(640, 384))
					and is_equal_approx(box.canvas_scale, 1.0),
			"size=%s canvas_scale=%.2f" % [box.size, box.canvas_scale])

	# 对话条：贴底、左右各 16、底边距 12
	var bar: Panel = _first_panel_child(box)
	_report("对话条贴底铺满（16, 264, 608, 108）",
			bar != null and bar.position.is_equal_approx(Vector2(16, 264))
					and bar.size.is_equal_approx(Vector2(608, 108)),
			"rect=%s size=%s" % [bar.position if bar != null else "<无>",
			bar.size if bar != null else "<无>"])
	_report("对话条底边距 = 12px（不贴到屏幕最底）",
			bar != null and is_equal_approx(bar.position.y + bar.size.y, 372.0),
			"底边 y=%s" % (bar.position.y + bar.size.y if bar != null else "<无>"))

	box.close()
	await _wait(4)


# ---- 3. 兜底：塞进尺寸不对的容器 -------------------------------------------

func _check_foreign_container() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var host: Node = scene.get_node("HUD")
	var ps: PackedScene = load("res://scenes/ui/dialogue_box.tscn") as PackedScene
	var box: UiPanel = ps.instantiate() as UiPanel
	box.set("speaker", "测试")
	box.set("role", "")
	box.set("lines", PackedStringArray(["兜底用例"]))
	host.add_child(box)

	var want_scale: float = minf(view.x / 640.0, view.y / 384.0)
	_report("塞进 CanvasLayer 时自动换算成等比铺满",
			is_equal_approx(box.canvas_scale, want_scale)
					and box.size.is_equal_approx(Vector2(640, 384)),
			"viewport=%s / canvas_scale=%.2f 期望=%.2f / size=%s"
					% [view, box.canvas_scale, want_scale, box.size])
	var drawn: Vector2 = box.size * box.canvas_scale
	_report("缩放后正好落在可用区域内（不越界、不贴角）",
			drawn.x <= view.x + 0.5 and drawn.y <= view.y + 0.5
					and box.position.x >= -0.5 and box.position.y >= -0.5,
			"画布=%s 位置=%s 区域=%s" % [drawn, box.position, view])
	box.close()


# ---- 工具 ------------------------------------------------------------------

func _panel() -> UiPanel:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if n is UiPanel and is_instance_valid(n):
			return n as UiPanel
	return null


func _first_panel_child(root: Node) -> Panel:
	for child: Node in root.get_children():
		if child is Panel:
			return child as Panel
	return null


func _place_cuige(at: Vector2) -> Npc:
	var f: FileAccess = FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return null
	var def: Dictionary = {}
	for d: Variant in ((data as Dictionary).get("npcs", []) as Array):
		if str((d as Dictionary).get("id", "")) == "tavern_cuige":
			def = d as Dictionary
			break
	if def.is_empty():
		return null
	var ps: PackedScene = load("res://scenes/npc.tscn") as PackedScene
	var npc: Npc = ps.instantiate() as Npc
	npc.name = "Npc_tavern_cuige"
	npc.configure(def, {"scene": "world", "pos": [at.x, at.y],
			"facing": "down", "wander": 0.0})
	scene.get_node("Sorted").add_child(npc)
	return npc


func _push_interact() -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	get_viewport().push_input(ev)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
