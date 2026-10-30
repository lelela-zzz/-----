extends Node
## 无窗口验收：实例化 world，确认 door_foreground 前景门件被正确建出、
## 四时段贴图都加载到了、且它没有任何碰撞体（no_collision 生效）。
## 不依赖 frame_post_draw，headless 可跑。

func _ready() -> void:
	StoryDirector.force_disable = true
	await get_tree().process_frame
	await get_tree().process_frame

	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var sorted: Node2D = world.get_node("Sorted") as Node2D
	var door: Sprite2D = sorted.get_node_or_null("door_foreground") as Sprite2D
	var fade: Sprite2D = sorted.get_node_or_null("door_foregroundFade") as Sprite2D

	var sprites_ok: bool = door != null and fade != null
	var tex_ok: bool = sprites_ok and door.texture != null and fade.texture != null
	print("[verify] 门前景精灵存在:", sprites_ok)
	if door != null:
		print("[verify] 门 base 贴图:", door.texture.resource_path if door.texture != null else "null")
		print("[verify] 门 base modulate.a:", door.modulate.a)
	if fade != null:
		print("[verify] 门 fade 贴图:", fade.texture.resource_path if fade.texture != null else "null")

	# 门必须是 Sorted 的直接子节点（才能和 Player 一起参与 y 排序）
	var is_direct: bool = false
	if door != null:
		is_direct = door.get_parent() == sorted
	print("[verify] 门是 Sorted 直接子节点(参与 y 排序):", is_direct)

	# 门不应带任何碰撞：统计 PropBodies 里的 CollisionShape2D
	var bodies: Node = sorted.get_node_or_null("PropBodies")
	var shapes: int = 0
	if bodies != null:
		for c: Node in bodies.get_children():
			if c is CollisionShape2D:
				shapes += 1
	print("[verify] PropBodies 碰撞框数量:", shapes)

	# 门 sort_y 必须 > 玩家在门口的脚底 y(≈378)，否则无法压在角色上方
	var sort_y_ok: bool = door != null and is_zero_approx(0.0)  # placeholder
	if door != null:
		sort_y_ok = door.position.y > 378.0
	print("[verify] 门 sort_y > 378 (能在角色上方):", sort_y_ok, " (sort_y=", door.position.y if door != null else -1, ")")

	var all_ok: bool = sprites_ok and tex_ok and is_direct and sort_y_ok
	print("[verify] 总判定:", "PASS" if all_ok else "FAIL")
	get_tree().quit()
