extends Node
## 开始界面验收：
##   "<godot.exe>" --headless --path . res://tests/verify_title.tscn --quit-after 9000
##
## 覆盖：
##   1) 底图按 1280×768 原生尺寸铺满（这一屏不跟 640 逻辑网格走）
##   2) 三项菜单 + 版式文案都在
##   3) 键盘上下选择（含首尾环绕）
##   4) 设置项能打开游戏内那块设置面板，Esc 能关掉
##   5) 「开始游戏」真的切到 world.tscn
##
## 注意：这一屏是 1280 原生排版，**不要**调 TestView.logic_resolution()，
## 否则 content_scale 会被压回 640×384，版面只显示左上四分之一。

var _pass := 0
var _fail := 0
var _scene: Node = null


func _ready() -> void:
	StoryDirector.force_disable = true     # 切进世界后别放序章，专心测这一屏
	# 这一屏的断言全按"没有任何存档"来写（两行存档位置灰），
	# 所以先清档 —— 否则跑过 verify_save / save_shot 之后这里会红一片。
	SaveGame.clear_all_slots()
	await get_tree().process_frame

	_scene = (load("res://scenes/title.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	for i: int in 4:
		await get_tree().process_frame

	# ---- 1) 底图 ----
	var bg: Sprite2D = _scene.get_node_or_null("Background") as Sprite2D
	var tex_size: Vector2 = Vector2.ZERO
	if bg != null and bg.texture != null:
		tex_size = bg.texture.get_size()
	_report("底图是 1280×768 原生尺寸",
			tex_size == Vector2(1280, 768), "size=%s" % tex_size)
	_report("底图不缩放铺满画布",
			bg != null and bg.scale == Vector2.ONE and not bg.centered,
			"scale=%s centered=%s" % [bg.scale if bg != null else "n/a",
					bg.centered if bg != null else "n/a"])

	# ---- 2) 文案 ----
	var texts: Array[String] = _labels(_scene)
	_report("标题写着 龙与粗麦酒", _any_contains(texts, "龙与粗麦酒"), "labels=%s" % [texts])
	for want: String in ["继续游戏", "读取存档", "开始游戏", "设置", "退出游戏"]:
		_report("菜单项「%s」在" % want, _any_contains(texts, want),
				"labels=%s" % [texts])
	_report("底部有键位提示", _any_contains(texts, "W / S 选择"),
			"labels=%s" % [texts])
	_report("五项菜单（给存档留的位子也在）", _items().size() == 5,
			"size=%d" % _items().size())

	# ---- 3) 存档位：没有存档时置灰，并有说明 ----
	_report("「继续游戏」无存档 → 置灰", not _enabled(0),
			"enabled=%s" % _enabled(0))
	_report("「读取存档」无存档 → 置灰", not _enabled(1),
			"enabled=%s" % _enabled(1))
	_report("「开始游戏」始终可用", _enabled(2), "enabled=%s" % _enabled(2))
	var notes: int = 0
	for t: String in texts:
		if t == "暂无存档":
			notes += 1
	_report("灰行右侧标注「暂无存档」", notes == 2, "count=%d" % notes)

	# ---- 4) 选择 ----
	_report("无存档时默认停在「开始游戏」（index=2）", _index() == 2,
			"index=%d" % _index())
	_push_key(KEY_S)
	await get_tree().process_frame
	_report("按 S 下移到「设置」", _index() == 3, "index=%d" % _index())
	_push_key(KEY_W)
	await get_tree().process_frame
	_report("按 W 回到「开始游戏」", _index() == 2, "index=%d" % _index())
	_push_key(KEY_W)
	_push_key(KEY_W)
	await get_tree().process_frame
	_report("再上移两次到「继续游戏」", _index() == 0, "index=%d" % _index())
	_push_key(KEY_W)
	await get_tree().process_frame
	_report("首项再按 W 绕到末项（退出游戏）", _index() == 4, "index=%d" % _index())

	# ---- 5) 灰行按下去不动作 ----
	await _goto(0)                      # 绕回「继续游戏」
	_push_key(KEY_E)
	await _wait(12)
	var stay: bool = false
	if get_tree().current_scene != null:
		stay = get_tree().current_scene.scene_file_path.ends_with("title.tscn")
	_report("灰行「继续游戏」按 E 不切场景", stay, "index=%d" % _index())
	_report("灰行按 E 也不弹面板", _modal(UiPanel) == null, "modal=%s" % _modal(UiPanel))

	# ---- 6) 设置面板 ----
	await _goto(3)
	_push_key(KEY_E)
	await _wait(3)
	var panel: UiPanel = _modal(UiPanel)
	_report("「设置」打开游戏内设置面板", panel != null, "panel=%s" % panel)
	_report("设置面板盖住整屏（canvas_scale=2）",
			panel != null and is_equal_approx(panel.canvas_scale, 2.0),
			"scale=%s" % (panel.canvas_scale if panel != null else "n/a"))
	if panel != null:
		_push_key(KEY_ESCAPE)
		await _wait(3)
	_report("Esc 关掉设置面板", _modal(UiPanel) == null, "modal=%s" % _modal(UiPanel))

	# ---- 7) 开始游戏 ----
	await _goto(2)
	_push_key(KEY_E)
	# 淡出 0.55s + 切场景，多等一会儿
	await _wait(90)
	var id: String = ""
	if get_tree().current_scene != null:
		id = get_tree().current_scene.scene_file_path
	_report("「开始游戏」切到酒馆场景", id.ends_with("world.tscn"), "scene=%s" % id)

	_finish()


## 用 S 往下走到第 i 项。最多按 8 次就放弃 —— 验收脚本里不许出现无限循环。
func _goto(i: int) -> void:
	for n: int in 8:
		if _index() == i:
			return
		_push_key(KEY_S)
		await get_tree().process_frame
	await get_tree().process_frame


func _items() -> Array:
	if _scene == null or not is_instance_valid(_scene):
		return []
	return _scene.get("_items") as Array


func _enabled(i: int) -> bool:
	var list: Array = _items()
	if i < 0 or i >= list.size():
		return false
	return bool(list[i].get("enabled"))


func _index() -> int:
	if _scene == null or not is_instance_valid(_scene):
		return -1
	return int(_scene.get("_index"))


func _modal(type: Variant) -> UiPanel:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and is_instance_of(n, type):
			return n as UiPanel
	return null


func _labels(root: Node) -> Array[String]:
	var out: Array[String] = []
	if root is Label:
		out.append((root as Label).text)
	for c: Node in root.get_children():
		out.append_array(_labels(c))
	return out


func _any_contains(texts: Array[String], needle: String) -> bool:
	for t: String in texts:
		if t.find(needle) >= 0:
			return true
	return false


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
	print("[verify_title] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
