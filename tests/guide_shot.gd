extends Node
## 指引【罗盘箭头】观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/guide_shot.tscn --quit-after 9000
##
## 验两件事：
##   01_arrow_tavern.png —— 在酒馆里追踪「去集市」→ 屏幕下缘应出现黄色箭头，
##                          指向南门 ExitSouth（下一跳）；
##   02_arrow_village.png —— 人在集市里 → 箭头改为指向目的地（凯瑟琳摊位）。
##
## 注：force_disable=true 时 Story 不会注入 UI，所以这里手动挂一次，
## 挂法和 _ensure_tracker() 完全一致。

const DIR := "res://tests/guide_shots/"

var scene: Node


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	await get_tree().process_frame

	QuestLog.reset()
	QuestLog.add("guide_shot", "去集市进一批酿酒材料", "开张头一天，材料得备足。",
			StoryDirector.DEST_CATHERINE)
	QuestLog.add_step("guide_shot", "走出酒馆，前往卢迪克集市")
	QuestLog.add_step("guide_shot", "和集市管理员凯瑟琳搭上话")
	QuestLog.set_tracked("guide_shot")

	await _mount("res://scenes/world.tscn")
	await _shot("01_arrow_tavern.png")

	await _mount("res://scenes/village.tscn")
	await _shot("02_arrow_village.png")

	# 03：把玩家挪到村子另一头，让凯瑟琳跑出屏幕 → 应切成"贴边罗盘"形态
	var player: Node2D = scene.get_node_or_null("Sorted/Player") as Node2D
	if player != null:
		player.global_position = Vector2(770, 110)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("03_arrow_compass.png")
	_debug_arrow(player)

	print("[guide_shot] done")
	get_tree().quit()


func _mount(path: String) -> Node:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		scene = null
		await get_tree().process_frame
	scene = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	var hud: Node = scene.get_node_or_null("HUD/UIRoot")
	if hud != null:
		hud.add_child(GuideArrow.new())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return scene


## 打一行数值：屏幕上的玩家位置 / 目标位置 / 方向 / 期望旋转 / 实际旋转。
## 用来确认"贴边罗盘"真的朝目标转（光看小图容易看错）。
func _debug_arrow(player: Node2D) -> void:
	var arrow: GuideArrow = null
	var hud: Node = scene.get_node_or_null("HUD/UIRoot")
	if hud != null:
		for c: Node in hud.get_children():
			if c is GuideArrow:
				arrow = c
	if player == null or arrow == null:
		print("[guide_shot] 没有玩家或箭头")
		return
	var rs: float = WindowScale.render_scale().x
	if rs <= 0.0:
		rs = 1.0
	var o: Vector2 = player.get_global_transform_with_canvas().origin / rs
	var t: Vector2 = QuestGuide.world_to_canvas(player, QuestGuide.waypoint()) / rs
	var d: Vector2 = t - o
	print("[guide_shot] origin=%s target=%s d=%s 期望rot=%.1f° 实际rot=%.1f°" % [
		str(o), str(t), str(d), rad_to_deg(d.angle() + PI * 0.5),
		rad_to_deg(arrow._sprite.rotation)])


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
