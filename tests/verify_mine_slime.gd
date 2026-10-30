extends Node
## 矿井史莱姆【行为验收】：缩小、整只不埋进岩壁、不重叠、有推挤。
##   "<godot.exe>" --headless --path . res://tests/verify_mine_slime.tscn --quit-after 9000
##
## 和观感截图（mine_slime_shot）分工不同：那个出图给人看，这个只用数字把关：
##   1) 摆出来的 7 只都在岩壁碰撞箱之外的空地上（否则一出生就卡死）；
##   2) 精灵缩放已缩小（WORLD_SCALE 0.07 → 存活态高约 57px）；
##   3) 让它们朝玩家/爱德华走 10 秒，**每一帧**检查：
##        · 脚下小圆没压进 collision_rect（物理，圆-矩形）；
##        · **整只精灵框**也没压进 collision_rect（观感：身子不许埋进岩壁）；
##        · 任意两只的中心距都 ≥ 2×BODY_RADIUS（真的没叠在一起）；
##   4) 确实动过（有位移），且整体在靠近目标，落位后围成一圈并且散得开；
##   5) 触发"姜酒杀死"之后全部变成尸体。
##
## 第 3 条的后半句是这次加的重点：只测脚下小圆时，"脚踩在地上、半个身子插在
## 石头里"是查不出来的 —— 那才是看着"卡进墙内"的真正原因。

const MINE: String = "res://scenes/mine.tscn"
const PROPS: String = "res://assets/mine/v1/objects/props.json"
## 与 scripts/slime.gd 的 BODY_RADIUS 一致（脚底小圆，管物理）。
const BODY_RADIUS: float = 13.0
## 与 scripts/chapter_story.gd 的 SLIME_HALF_W / SLIME_HEIGHT 一致（精灵框，管观感）。
const SLIME_HALF_W: float = 28.0
const SLIME_HEIGHT: float = 58.0
## 相交容差：移动是"先判后移"，理论上不该有侵入，留 0.5px 给浮点。
const TOL: float = 0.5
## 采样帧数（60fps ≈ 10 秒）。
const FRAMES: int = 600

var passed: int = 0
var failed: int = 0
var _rects: Array = []


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	ChapterStory.wait_for_talk = false
	QuestLog.reset()
	await get_tree().process_frame

	_rects = _load_rects()
	_report("矿井碰撞箱读得到", _rects.size() > 200, "rects=%d" % _rects.size())

	var scene: Node = (load(MINE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	for i: int in 8:
		await get_tree().process_frame

	# 玩家进屋后站到洞穴里（和真实流程一致：这一幕两人并肩站在洞穴中央）
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		player.global_position = ChapterStory.MINE_STAGE_PLAYER
	ChapterStory._place_npc("dwarf_war_edward",
			ChapterStory.MINE_STAGE_EDWARD, "down", {})
	ChapterStory._spawn_mine_slimes()
	for i: int in 4:
		await get_tree().process_frame

	var slimes: Array = ChapterStory._slime_nodes
	_report("摆出 7 只史莱姆", slimes.size() == 7, "n=%d" % slimes.size())
	if slimes.size() < 7:
		_finish()

	# ---- 1. 出生点整只都在空地上 ----
	var bad_box: String = ""
	for s: Node in slimes:
		var n2: Node2D = s as Node2D
		if _box_blocked(n2.global_position):
			bad_box += "%s@%s " % [n2.name, n2.global_position.round()]
	_report("出生时整只都在地面上（身子没埋进岩壁）", bad_box == "", bad_box)
	_report("出生时不重叠", _min_pair_distance(slimes) >= BODY_RADIUS * 2.0,
			"min=%.1f (需≥%.1f)" % [_min_pair_distance(slimes), BODY_RADIUS * 2.0])

	# ---- 2. 尺寸确实缩小了 ----
	var spr: Sprite2D = slimes[0].get_node_or_null("Sprite") as Sprite2D
	var sc: float = spr.scale.x if spr != null else 0.0
	var visual_h: float = spr.texture.get_height() * sc if spr != null and spr.texture != null else 0.0
	_report("精灵已缩小到 0.07", is_equal_approx(sc, 0.07), "scale=%.3f" % sc)
	_report("存活态视觉高度约 57px", visual_h > 50.0 and visual_h < 62.0, "h=%.1f" % visual_h)

	# ---- 3. 靠近途中逐帧检查穿墙 / 重叠 ----
	var start_pos: Array[Vector2] = []
	for s: Node in slimes:
		start_pos.append((s as Node2D).global_position)

	ChapterStory._start_slimes_approach()
	for i: int in 3:
		await get_tree().process_frame

	# 记下每只被分到的站位点，最后验它有没有真的走到
	var goals: Array[Vector2] = []
	for s: Node in slimes:
		goals.append(s.call("goal_point") as Vector2)
	_report("每只都分到了站位", goals.size() == 7, "n=%d" % goals.size())

	# ---- 3b. 两人是并肩站着的（不是一上一下隔着半个竖井）----
	var edward: Node2D = null
	if get_tree().current_scene != null:
		edward = get_tree().current_scene.get_node_or_null(
				"Sorted/Npc_beat_dwarf_war_edward") as Node2D
	_report("爱德华确实摆进了矿井", edward != null, "")
	var gap: float = 9999.0
	if edward != null and player != null:
		gap = edward.global_position.distance_to(player.global_position)
	_report("主角与爱德华并肩站在一起", edward != null and gap <= 70.0,
			"间距 %.0fpx（需≤70）" % gap)

	var worst_min_dist: float = 9999.0
	var overlap_frames: int = 0
	var wall_frames: int = 0
	var wall_worst: String = ""
	for f: int in FRAMES:
		await get_tree().process_frame
		var frame_wall: bool = false
		for s: Node in slimes:
			if not is_instance_valid(s):
				continue
			var n2: Node2D = s as Node2D
			if _box_blocked(n2.global_position):
				frame_wall = true
				wall_worst = "%s@%s" % [n2.name, n2.global_position.round()]
		if frame_wall:
			wall_frames += 1
		var md: float = _min_pair_distance(slimes)
		if md < worst_min_dist:
			worst_min_dist = md
		if md < BODY_RADIUS * 2.0 - TOL:
			overlap_frames += 1

	_report("全程整只都没埋进岩壁", wall_frames == 0,
			"越界帧 %d/%.0f %s" % [wall_frames, FRAMES, wall_worst])
	_report("全程没有互相重叠", overlap_frames == 0,
			"最近中心距 %.1fpx / 需≥%.1f / 越界帧 %d" % [worst_min_dist, BODY_RADIUS * 2.0, overlap_frames])

	# ---- 4. 真的动了、而且都站到了自己那个位置 ----
	var moved: int = 0
	var total_move: float = 0.0
	var off_goal: String = ""
	var worst_off: float = 0.0
	for i: int in slimes.size():
		var n2: Node2D = slimes[i] as Node2D
		if not is_instance_valid(n2):
			continue
		var d: float = n2.global_position.distance_to(start_pos[i])
		total_move += d
		if d > 15.0:
			moved += 1
		var off: float = n2.global_position.distance_to(goals[i])
		worst_off = maxf(worst_off, off)
		if off > 8.0:
			off_goal += "%s偏%.0fpx " % [n2.name, off]
	_report("史莱姆确实走向自己的站位", moved >= 5,
			"位移>15px 的 %d/7 只，总位移 %.0fpx" % [moved, total_move])
	_report("每只都走到了自己的站位", off_goal == "", "最大偏差 %.1fpx %s" % [worst_off, off_goal])

	# ---- 4b. 包围散开了没有（这是本次改动的重点）----
	# 落位之后每只到"两人中点"的距离应该在包围圈半径上下，
	# 而且相邻两只之间留得开（原来的问题是全挤在同一个点上）。
	var center: Vector2 = (ChapterStory.MINE_STAGE_PLAYER \
			+ ChapterStory.MINE_STAGE_EDWARD) * 0.5
	var rmin: float = 9999.0
	var rmax: float = 0.0
	for s: Node in slimes:
		if is_instance_valid(s):
			var rr: float = (s as Node2D).global_position.distance_to(center)
			rmin = minf(rmin, rr)
			rmax = maxf(rmax, rr)
	_report("围成一圈（到圈心距离都差不多）", rmin > 45.0 and rmax < 120.0,
			"半径 %.0f~%.0f px" % [rmin, rmax])
	var settled_min: float = _min_pair_distance(slimes)
	_report("包围时彼此散得开", settled_min >= 55.0,
			"落位后最近中心距 %.1fpx（需≥55）" % settled_min)
	var settled_box: String = ""
	for s: Node in slimes:
		if is_instance_valid(s) and _box_blocked((s as Node2D).global_position):
			settled_box += "%s " % str(s.name)
	_report("落位后整只都站在地面上", settled_box == "", settled_box)

	# 推挤的可见证据：挤在一起时最近的这一对也被顶到 36px 开外
	# （身子直径才 26，36 已经能看出是两颗独立的胶团，而不是糊成一坨）
	_report("贴得近时会互相推开", worst_min_dist >= 36.0,
			"最近 %.1fpx vs 直径 %.1fpx" % [worst_min_dist, BODY_RADIUS * 2.0])

	# ---- 5. 全部死透 ----
	ChapterStory._force_kill_slimes()
	for i: int in 40:
		await get_tree().process_frame
	var dead: int = 0
	for s: Node in slimes:
		if is_instance_valid(s) and bool(s.call("is_dead")):
			dead += 1
	_report("姜酒后全部变成尸体", dead == slimes.size(), "dead=%d/%d" % [dead, slimes.size()])

	_finish()


func _finish() -> void:
	QuestLog.reset()
	print("[mine_slime] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _load_rects() -> Array:
	var out: Array = []
	var f: FileAccess = FileAccess.open(PROPS, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for entry: Variant in (parsed as Dictionary).get("props", []):
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry as Dictionary
		if bool(d.get("no_collision", false)):
			continue
		var cr: Variant = d.get("collision_rect", null)
		if cr is Array and (cr as Array).size() >= 4:
			var a: Array = cr as Array
			out.append(Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])))
	return out


## 整只精灵框（脚底为原点、身子往上长）是否压到任何碰撞矩形。
func _box_blocked(p: Vector2) -> bool:
	var box: Rect2 = Rect2(p.x - SLIME_HALF_W, p.y - SLIME_HEIGHT,
			SLIME_HALF_W * 2.0, SLIME_HEIGHT)
	for entry: Variant in _rects:
		if box.intersects(entry as Rect2):
			return true
	return false


func _min_pair_distance(slimes: Array) -> float:
	var best: float = 9999.0
	for i: int in slimes.size():
		if not is_instance_valid(slimes[i]):
			continue
		var a: Node2D = slimes[i] as Node2D
		for j: int in range(i + 1, slimes.size()):
			if not is_instance_valid(slimes[j]):
				continue
			var b: Node2D = slimes[j] as Node2D
			best = minf(best, a.global_position.distance_to(b.global_position))
	return best
