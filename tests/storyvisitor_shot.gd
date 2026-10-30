extends Node
## 支线访客【以顾客身份进店】观感截图 —— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/storyvisitor_shot.tscn --quit-after 9000
##
##   01_visitor_walking.png —— 刚进店，正从门口往座位走
##   02_visitor_seated.png  —— 坐定点酒（按 [E] 就是"交谈"，会播他的支线）
##
## 以前这些人是被 Story 静态塞在酒馆固定位置上的桩子，现在走和普通客人一样的入场流程。

const DIR := "res://tests/storyvisitor_shots/"

var scene: Node


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true   # 关掉自动补人，手动只放一位，画面干净
	StoryDirector.force_disable = false
	Engine.max_fps = 60
	await get_tree().process_frame

	scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	Story.stage = StoryDirector.Stage.OPEN
	Story.business_open = true
	# 支线系统直接推到"开张第 2 天"，访客才肯出来
	for i in 8:
		await get_tree().process_frame
	SideStory._story_day = 2

	var spawner: CustomerSpawner = scene.get_node_or_null("Customers") as CustomerSpawner
	if spawner == null:
		print("[visitor_shot] 找不到 CustomerSpawner")
		get_tree().quit(1)
		return
	# 手动调一次生成：优先放"身上还有没播支线"的角色
	var guest: Customer = spawner.spawn_random()
	print("[visitor_shot] guest=%s pending=%s" % [
		guest.npc_id if guest != null else "无",
		SideStory.has_pending(guest.npc_id) if guest != null else false])
	if guest == null:
		get_tree().quit(1)
		return

	# 走位途中截一张
	for i in 24:
		await get_tree().process_frame
	await _shot("01_visitor_walking.png")

	# 等他说完走位、真正坐下（走速 34px/s，从门口到座位要好几秒）
	for i in 1200:
		await get_tree().physics_frame
		if guest.state == Customer.State.SITTING or guest.state == Customer.State.QUEUED:
			break
	for i in 6:
		await get_tree().physics_frame
	await _shot("02_visitor_seated.png")
	print("[visitor_shot] 远处 mark=%s prompt=%s" % [
		guest._mark.visible if guest._mark != null else "无",
		guest._prompt.visible if guest._prompt != null else "无"])

	# 玩家走过去：进了 talk_range(46) → [E] 交谈出来，感叹号让位
	var player: Node2D = scene.get_node_or_null("Sorted/Player") as Node2D
	if player != null:
		player.global_position = guest.global_position + Vector2(0, 26)
	for i in 12:
		await get_tree().physics_frame
	await _shot("03_close_prompt.png")
	print("[visitor_shot] 靠近 mark=%s prompt=%s" % [
		guest._mark.visible if guest._mark != null else "无",
		guest._prompt.visible if guest._prompt != null else "无"])
	print("[visitor_shot] 诊断 state=%d leg=%d path=%d queue=%s gpos=%s in_range=%s nearest=%s" % [
		guest.state, guest._leg, guest._path.size(), str(guest._queue_pos),
		str(guest.global_position), guest._in_range(), guest._is_nearest()])
	print("[visitor_shot] done pos=%s" % str(guest.global_position))

	get_tree().quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
