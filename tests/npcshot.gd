extends Node
## NPC 观感截图：白天排布 / 对话框 / 夜晚环境色。
##   "<godot.exe>" res://tests/npcshot.tscn     （窗口模式，headless 下 frame_post_draw 不触发）

const ENTRY := "res://scenes/world.tscn"
const DIR := "res://tests/shots/"

var scene: Node2D
var player: Player


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	scene = (load(ENTRY) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	player = scene.get_node("Sorted/Player") as Player
	Engine.max_fps = 60
	await _wait(10)
	await _shot("npc_01_tavern_day.png")

	# 走到林格跟前，摆出对话
	var npc: Npc = null
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if (n as Npc).npc_id == "knight_ringe":
			npc = n as Npc
	if npc != null:
		player.global_position = npc.global_position + Vector2(-6, 30)
		await _wait(10)
		await _shot("npc_02_prompt.png")
		var ev: InputEventAction = InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		get_viewport().push_input(ev)
		await _wait(14)
		await _shot("npc_03_dialogue.png")
		var key: InputEventKey = InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		get_viewport().push_input(key)
		await _wait(6)

	# 夜晚：看 NPC 有没有跟着暗下去、炉火边有没有被照亮
	var lighting: LightingDirector = scene.get_node("Lighting") as LightingDirector
	lighting.follow_clock = false
	lighting.set_phase_instant(LightingDirector.PHASE_NIGHT)
	await _wait(8)
	await _shot("npc_04_night.png")

	print("[npcshot] done")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	(get_viewport().get_texture().get_image()).save_png(DIR + name)
