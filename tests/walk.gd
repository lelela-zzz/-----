extends Node
## 步行验证：门洞外的底墙仍然阻挡。
## 门洞本身现在是通往村庄的传送触发框，行为级验收归 tests/vshot.tscn（酒馆→村传送）。
const ENTRY_SCENE := "res://scenes/world.tscn"

var scene: Node2D
var player: Player


func _ready() -> void:
	scene = (load(ENTRY_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	player = scene.get_node("Sorted/Player") as Player
	var clock: GameClock = scene.get_node("Clock") as GameClock
	Engine.max_fps = 60
	clock.running = false
	clock.set_time(12, 0)
	await _w(10)

	# 门洞外（x=200，两列长桌之间）向南：底墙应挡在 306
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(200.0, 280.0)
	await _w(8)
	Input.action_press("move_down")
	await _w(120)
	Input.action_release("move_down")
	await _w(20)
	var wall_y: float = player.global_position.y
	print("[walk] 门洞外南行停在 = ", player.global_position, "（期望 y≈306 底墙）")

	var ok: bool = absf(wall_y - 306.0) < 1.5
	print("[walk] 底墙阻挡 = ", ok, "（底墙 y=%.1f）" % wall_y)
	get_tree().quit()


func _w(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
