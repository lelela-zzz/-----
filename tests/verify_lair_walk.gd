extends Node
## 龙巢「走进圈心」通行性探针：从传送门按住上 2 秒，看能不能穿过盘龙下缘
## 走到圈心（y < 512）并停在人物脚边。改盘龙碰撞框后跑一次，防止把入口堵死。

const LAIR := "res://scenes/dragon_lair.tscn"

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	TestView.logic_resolution()
	Chapter3Story.reset()
	Chapter3Story.wait_for_talk = true
	await get_tree().process_frame
	var scene: Node = (load(LAIR) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _tick()

	var player: Player = scene.get_node("Sorted/Player") as Player
	player.global_position = Vector2(480, 700)
	player.velocity = Vector2.ZERO
	await _tick()

	Input.action_press("move_up")
	var frames: int = 0
	while frames < 180 and player.global_position.y > 540:
		await get_tree().physics_frame
		frames += 1
	Input.action_release("move_up")
	await _tick()

	_report("从传送门按上能走进盘龙圈心（y≤540）",
			player.global_position.y <= 540,
			"y=%.1f（用了 %d 物理帧）" % [player.global_position.y, frames])
	_report("没有穿出圈心（x 仍在 384~544 内）",
			player.global_position.x >= 384.0 and player.global_position.x <= 544.0,
			"x=%.1f" % player.global_position.x)

	# 圈心内必须站得住：再按上 1 秒，不得穿到盘龙上半身以外（y 不应 < 405）
	Input.action_press("move_up")
	for i: int in 60:
		await get_tree().physics_frame
	Input.action_release("move_up")
	await _tick()
	_report("圈心北侧被龙身挡住（y 不越过 405）",
			player.global_position.y >= 405.0, "y=%.1f" % player.global_position.y)

	print("[lair_walk] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _tick() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
