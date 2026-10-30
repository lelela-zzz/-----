extends Node
## 漆黑空间验收（厄里斯戏的覆盖层，已迁至 dark_room.tscn）：
##   1) scenes/dark_room.tscn 是 layer=5 的 CanvasLayer，含全黑底、中心光(ADD)、两名角色；
##   2) StoryDialogue 遇到 dark_space:"on" 会挂上黑幕，遇 "off" 会撤下并淡出释放；
##   3) 对话关闭时黑幕一并清理。
## 运行： "<godot>" --headless --path . res://tests/verify_dark_space.tscn --quit-after 9000

var _pass := 0
var _fail := 0


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	await get_tree().process_frame

	await _part_scene()
	await _part_dialogue()

	print("[dark] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _part_scene() -> void:
	var ds: Node = (load("res://scenes/dark_room.tscn") as PackedScene).instantiate()
	add_child(ds)
	await _frames(3)

	_report("dark_space 为 CanvasLayer 且 layer=5",
			ds is CanvasLayer and int((ds as CanvasLayer).layer) == 5,
			"is_canvas=%s layer=%s" % [ds is CanvasLayer,
			(ds as CanvasLayer).layer if ds is CanvasLayer else -1])

	var ctrl: Node = ds.get_child(0) if ds.get_child_count() > 0 else null
	var rects: int = 0
	var glow: Sprite2D = null
	var actors: int = 0
	var actor_xs: Array[float] = []
	if ctrl != null:
		for n: Node in ctrl.get_children():
			if n is ColorRect:
				rects += 1
			elif n is Sprite2D:
				var sp: Sprite2D = n as Sprite2D
				if sp.texture is AtlasTexture:
					actors += 1
					actor_xs.append(sp.position.x)
				elif sp.material is CanvasItemMaterial \
						and (sp.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD:
					glow = sp
	_report("含全黑底", rects >= 1, "rects=%d" % rects)
	_report("含中心柔光（ADD 光斑）", glow != null,
			"glow=%s" % (glow != null))
	_report("两名角色（AtlasTexture）≥2", actors >= 2, "actors=%d" % actors)

	# 左右对称 + 光源居中
	if glow != null and actor_xs.size() >= 2:
		var mid: float = (actor_xs[0] + actor_xs[1]) * 0.5
		_report("光源中心 = 两人间隔中点",
				absf(glow.position.x - mid) <= 1.0,
				"glow.x=%.1f mid=%.1f" % [glow.position.x, mid])
		_report("左右对称（两人到中点等距）",
				absf(absf(actor_xs[0] - mid) - absf(actor_xs[1] - mid)) <= 1.0,
				"x0=%.1f x1=%.1f" % [actor_xs[0], actor_xs[1]])
	else:
		_report("光源中心 = 两人间隔中点", false, "缺光源或角色")
		_report("左右对称（两人到中点等距）", false, "缺光源或角色")

	ds.queue_free()
	await _frames(2)


func _part_dialogue() -> void:
	var scene: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _frames(2)

	var hud: Node = scene.get_node("HUD/UIRoot")
	var ps: PackedScene = load("res://scenes/ui/story_dialogue.tscn") as PackedScene
	var dlg: UiPanel = ps.instantiate() as UiPanel
	dlg.set("entries", [
		{"speaker": "", "role": "", "text": "（前）"},
		{"speaker": "", "role": "", "text": "（恍惚间，你进入了一个漆黑的房间。）", "dark_space": "on"},
		{"speaker": "拜登", "role": "老板", "text": "这里漆黑一片……"},
		{"speaker": "", "role": "", "text": "（你突然离开了那个漆黑的房间。）", "dark_space": "off"},
	])
	hud.add_child(dlg)
	await _frames(3)

	_report("起始没有黑幕", dlg.get("_dark") == null, "")

	dlg.call("_show_entry", 1)
	await _frames(3)
	var dark: Node = dlg.get("_dark")
	_report("dark_space:on → 挂上黑幕（CanvasLayer layer=5）",
			dark != null and is_instance_valid(dark) and dark is CanvasLayer
			and int((dark as CanvasLayer).layer) == 5,
			"dark=%s" % (dark != null))

	dlg.call("_show_entry", 3)
	await _frames(2)
	_report("dark_space:off → _dark 置空", dlg.get("_dark") == null, "")
	await get_tree().create_timer(0.8).timeout   # 等 0.35s 淡出（按真实时间）+ 释放
	_report("淡出后黑幕已释放", not is_instance_valid(dark), "valid=%s" % is_instance_valid(dark))

	# 关对话时（哪怕没走 off）也要清黑幕
	dlg.call("_show_entry", 1)
	await _frames(3)
	var dark2: Node = dlg.get("_dark")
	dlg.close()
	var cleared: bool = dlg.get("_dark") == null   # close 同帧即把 _dark 置空
	await get_tree().create_timer(0.8).timeout
	_report("关对话即撤黑幕", cleared and not is_instance_valid(dark2),
			"cleared=%s freed=%s" % [cleared, not is_instance_valid(dark2)])


# ---- 工具 ---------------------------------------------------------------

func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("[check] PASS  %s" % name)
	else:
		_fail += 1
		print("[check] FAIL  %s  (%s)" % [name, detail])
