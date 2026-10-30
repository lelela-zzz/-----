extends Node
## 矿井史莱姆演出【观感截图】—— 窗口模式才能出图。
##   "<godot.exe>" --path . res://tests/mine_slime_shot.tscn --quit-after 12000
##
## 出三张：刚进洞（史莱姆在外圈）→ 包围圈合拢（两人并肩站在圈心）→ 姜酒杀死后只剩尸体。

const DIR: String = "res://tests/mine_slime_shots/"


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	await get_tree().process_frame

	QuestLog.reset()
	var scene: Node = (load("res://scenes/mine.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	for i: int in 8:
		await get_tree().process_frame

	# 和真实流程一致：爱德华先站进洞穴，主角站到他旁边，然后摆一地方史莱姆
	ChapterStory._place_npc("dwarf_war_edward",
			ChapterStory.MINE_STAGE_EDWARD, "down", {})
	ChapterStory._spawn_mine_slimes()
	ChapterStory._snap_mine_cast()
	for i: int in 6:
		await get_tree().process_frame
	await _shot("01_alive_far.png")

	# 围上来：每只认一个环形站位，最后围成一圈
	ChapterStory._start_slimes_approach()
	for i: int in 240:
		await get_tree().process_frame
	await _shot("02_surround.png")

	# 姜酒杀死 → 逐只崩解成尸体
	ChapterStory._force_kill_slimes()
	for i: int in 45:
		await get_tree().process_frame
	await _shot("03_dead.png")

	print("[mine_slime_shot] done")
	get_tree().quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
