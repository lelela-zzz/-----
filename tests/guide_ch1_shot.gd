extends Node
## 第一章指引【观感截图】—— 用 data/story_chapter1.json 里**真实的目的地数据**，
## 看箭头在三种典型情形下指得对不对（窗口模式才出图）：
##   "<godot.exe>" --path . res://tests/guide_ch1_shot.tscn --quit-after 9000
##
##   01_brew_pot.png    人在酒馆、本幕要酿酒      → 同图，箭头指向魔法酿酒机（锅）
##   02_hartfilia.png   人在集市、本幕要回门口找人 → 跨图，箭头指向第一跳那扇门
##   03_to_mine.png     人在集市、本幕要进矿道     → 跨图，箭头指向矿道入口那扇门
##
## 跨图的两张故意挂"玩家出发的那张图"，好看出箭头是在指**下一跳的门**；
## 同图那张才摆人物、看箭头是不是落在目标身上。

const DIR := "res://tests/guide_ch1_shots/"
const QID := "ch1_frost"

const WORLD := "res://scenes/world.tscn"
const VILLAGE := "res://scenes/village.tscn"

var scene: Node


func _ready() -> void:
	TestView.logic_resolution()
	DirAccess.make_dir_recursive_absolute(DIR)
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	Engine.max_fps = 60
	await get_tree().process_frame

	QuestLog.reset()
	QuestLog.add(QID, "第一章 · 雾凇无虞", "雪山科考队的委托：备好抗寒的酒，随队进山。")

	# 跨图：指门（先跑，避开连续切场景的残留干扰）
	await _beat_shot("ch1_tavern_hartfilia", VILLAGE, "02_hartfilia.png")
	# 同图：指物
	await _beat_shot("ch1_brew_antifreeze", WORLD, "01_brew_pot.png")
	# 跨图：指门
	await _beat_shot("ch1_to_mine", VILLAGE, "03_to_mine.png")

	print("[guide_ch1_shot] done")
	get_tree().quit()


## 挂 here 这张图、把任务目的地设成本幕的 dest，然后出图 + 打数值。
func _beat_shot(beat_id: String, here: String, file_name: String) -> void:
	var beat: Dictionary = _beat(beat_id)
	if beat.is_empty():
		print("[guide_ch1_shot] 找不到幕 %s" % beat_id)
		return
	var dest: Dictionary = beat.get("dest", {}) as Dictionary
	# 顺序要紧：**先切到玩家所在的图**，再设目的地。
	# 反过来的话 QuestGuide 会拿上一张图去算路线（跳数少一跳、指向旧图的门）。
	await _mount(here)
	QuestLog.set_dest(QID, dest)
	# set_tracked 是"切换"语义：再传同一个 id 会取消追踪。
	# 所以只在还没追踪时才设，否则第二幕起就没追踪目标、箭头自然不显示。
	if not QuestLog.is_tracked(QID):
		QuestLog.set_tracked(QID)

	# 已经在目标图里了才摆人（跨图时人还没登场，箭头本来就只指门）
	if here == str(dest.get("scene", "")):
		ChapterStory._spawn_beat_npc(beat)
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot(file_name)
	_debug(beat_id, dest)


func _beat(beat_id: String) -> Dictionary:
	for b: Variant in ChapterStory._beats:
		var d: Dictionary = b as Dictionary
		if str(d.get("id", "")) == beat_id:
			return d
	return {}


## 打印：目的地节点 / 箭头种类 / 目标世界坐标 —— 用数值确认指对了，
## 光看小图容易看错方向。
func _debug(beat_id: String, dest: Dictionary) -> void:
	var wp: Vector2 = QuestGuide.waypoint()
	var node_name: String = "-"
	if not str(dest.get("node", "")).is_empty() and scene != null:
		var n: Node = scene.get_node_or_null(str(dest.get("node", "")))
		node_name = str(dest.get("node", "")) if n != null else "%s(不在场)" % dest.get("node", "")
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	print("[guide_ch1_shot] %-22s kind=%-4s 目标=%s 节点=%s 剩余跳数=%d 玩家=%s 距目标=%.1f" % [
		beat_id, QuestGuide.kind(), str(wp), node_name, QuestGuide.hops_left(),
		str(player.global_position) if player != null else "无",
		player.global_position.distance_to(wp) if player != null else -1.0])


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


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var step: int = maxi(1, int(round(float(img.get_width()) / 640.0)))
	if step > 1:
		img.resize(img.get_width() / step, img.get_height() / step, Image.INTERPOLATE_NEAREST)
	img.save_png(DIR + file_name)
