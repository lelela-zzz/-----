extends Node
## 酒馆 ↔ 地窖【同一张地图】验收：不再是两个场景，也不再有传送门。
##
## 现在的结构（2026-10-28 改）：
##   world.tscn 变成 640×782 的一张图，地窖底图贴在酒馆底图**上方**（offset -22,-398），
##   横向左移 22px 是为了让地窖那段楼梯的中线正对门洞中线；右缘因此补了 22px 暗边铺到 x=640，
##   两间房在酒馆左上角那扇门处打通 —— **门洞 = 底图上那扇门往外扩一圈**（41×55，alpha=0），
##   门楣以上的墙和扩圈以外的墙面一个像素都没动，底层透出来的是地窖那段**原有楼梯**，
##   人从店堂一直往北走就能走进地窖。玩家还在店堂里时，地窖整块压一层阴影（CellarShade）。
##
## 验收要点：
##   1) 通往 cellar.tscn 的 DoorArea 已经不存在，场景文件也已删除（没有传送这回事）；
##   2) 四张时段底图在门洞位置真的透明，门洞以外的墙体一个像素都没动；
##   3) 北墙碰撞在门洞处断开（人过得去），地窖四周有自己的墙；
##   4) **物理走位**：从店堂一直按向上，脚底线穿过 y=76 的墙位进到地窖地板上，
##      中途场景一次都没换；再按向下能原路走回店堂；
##   5) 锅在楼上的地窖里，找得到灯光；地窖有自己的灯。
##
## 运行： "<godot.exe>" --headless --path . res://tests/verify_passage.tscn --quit-after 9000

const WORLD := "res://scenes/world.tscn"
## 地窖底图在合并图里的偏移（地窖局部坐标 + offset = 世界坐标）。
## y = -398：让地窖地面南沿正好落在门洞底（82）。
## x = -22：让那段楼梯的中心对上门的中心（126）—— 楼梯原画 x112..185，中心 148.5。
const CELLAR_OFFSET_X := -22.0
const CELLAR_OFFSET_Y := -398.0
## 门洞（逻辑坐标）：以底图上那扇门（110,42)-(143,83) 为基准，左右各外扩 4、上边外扩 14。
## 门楣上沿以上的墙（y<28）和扩圈以外的左右墙面都留着 —— 用户要求"虚化只包含木门"，
## 但又要把门放大到人走过去不别扭。两个数在 tools/punch_cellar_passage.py 里改。
const HOLE := Rect2(106, 28, 41, 55)
## 门洞中线 x —— 走位测试就沿这条线直着走。
const LANE_X := 126.0

var failures: int = 0


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	await get_tree().process_frame

	var world: Node = (load(WORLD) as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _wait(12)

	_check_no_teleport(world)
	_check_textures()
	_check_door_layer(world)
	_check_cellar_background(world)
	_check_camera(world)
	_check_walls(world)
	_check_cellar_light(world)
	_check_pot(world)
	await _check_cellar_shade(world)
	await _check_tavern_shade(world)
	await _check_door_fade(world)
	await _check_walk_up(world)
	await _check_walk_down(world)

	print("[verify_passage] done FAIL=", failures)
	get_tree().quit()


# ---- 结构 ----------------------------------------------------------------

func _check_no_teleport(world: Node) -> void:
	_report("酒馆里没有通往地窖的传送门（Doors/Cellar 已删除）",
			world.get_node_or_null("Doors/Cellar") == null,
			"节点=%s" % str(world.get_node_or_null("Doors/Cellar")))

	var gone: bool = not ResourceLoader.exists("res://scenes/cellar.tscn")
	_report("cellar.tscn 已经从工程里删掉（地窖不再是独立场景）", gone,
			"exists=%s" % ResourceLoader.exists("res://scenes/cellar.tscn"))

	var door: Node = world.get_node_or_null("Doors/ExitSouth")
	_report("只留下街面那道门（ExitSouth）", door != null,
			"ExitSouth=%s" % str(door))


func _check_textures() -> void:
	# 四张时段底图的**门扇**都要抠开，否则切到夜里门又补上了
	var phases: Array[String] = ["dawn", "day", "dusk", "night"]
	var all_open: bool = true
	var outside_solid: bool = true
	var lintel_solid: bool = true
	var detail: String = ""
	var detail2: String = ""
	for p: String in phases:
		var path: String = "res://assets/house/v4/scene_%s_v16_2x.png" % p
		var img: Image = Image.load_from_file(path)
		if img == null:
			all_open = false
			detail += "%s=读不到 " % p
			continue
		# 底图是 2× 源，逻辑坐标要乘 2
		var mid: Vector2i = Vector2i(126 * 2, 60 * 2)                  # 门洞正中
		var mid_lo: Vector2i = Vector2i(126 * 2, 78 * 2)               # 门洞靠下
		var solid: Vector2i = Vector2i(80 * 2, 60 * 2)                 # 门左边的墙
		var lintel: Vector2i = Vector2i(126 * 2, 16 * 2)               # 门**上方**的墙（门楣）
		var a1: float = img.get_pixelv(mid).a
		var a2: float = img.get_pixelv(mid_lo).a
		var a3: float = img.get_pixelv(solid).a
		var a4: float = img.get_pixelv(lintel).a
		if a1 > 0.01 or a2 > 0.01:
			all_open = false
			detail += "%s(门扇不透明 a=%.2f/%.2f) " % [p, a1, a2]
		if a3 < 0.99:
			outside_solid = false
			detail += "%s(门左侧被抠了 a=%.2f) " % [p, a3]
		if a4 < 0.99:
			lintel_solid = false
			detail2 += "%s(门楣被抠了 a=%.2f) " % [p, a4]
	_report("四张时段底图在门洞位置都透明（夜里也不会被补上）", all_open,
			detail if detail != "" else "dawn/day/dusk/night 全部 a=0")
	_report("门以外的墙一个像素都没动（左侧 x=80）", outside_solid,
			detail if detail != "" else "x=80 处 a=1")
	_report("门**上方**的墙（门楣 y=16）还立着，没跟着门一起消失", lintel_solid,
			detail2 if detail2 != "" else "y=16 处 a=1")


func _check_cellar_background(world: Node) -> void:
	var bg: Sprite2D = world.get_node_or_null("CellarBackground") as Sprite2D
	var ok: bool = bg != null and bg.texture != null \
			and bg.texture.get_size() == Vector2(640 - CELLAR_OFFSET_X, 512) \
			and bg.offset == Vector2(CELLAR_OFFSET_X, CELLAR_OFFSET_Y)
	_report("地窖底图贴在酒馆上方（右侧补 22px，%d×512，offset %d,%d）"
			% [int(640 - CELLAR_OFFSET_X), int(CELLAR_OFFSET_X), int(CELLAR_OFFSET_Y)], ok,
			"底图=%s offset=%s" % [
					"<无>" if bg == null or bg.texture == null else str(bg.texture.get_size()),
					"<无>" if bg == null else str(bg.offset)])

	# 底图左移 22px 之后，右缘必须补到 world x=640，否则地图右边留一条纯黑竖带
	var img: Image = null
	if bg != null and bg.texture != null:
		img = bg.texture.get_image()
	var edge_ok: bool = false
	var edge_detail: String = "<无底图>"
	if img != null:
		var last: int = img.get_width() - 1
		var c: Color = img.get_pixel(last, img.get_height() >> 1)
		var reaches: bool = bg.offset.x + img.get_width() == 640.0
		edge_ok = reaches and (c.r + c.g + c.b) > 0.05
		edge_detail = "右缘止于 x=%.0f 末列色=(%.2f,%.2f,%.2f)" % [
				bg.offset.x + img.get_width(), c.r, c.g, c.b]
	_report("地窖底图右缘铺到地图右边界、不留纯黑缝", edge_ok, edge_detail)

	# 地窖底图必须画在酒馆底图**下面**（同 z，靠节点顺序压住），
	# 否则它会盖到酒馆墙上，门洞就白抠了。
	var tavern: Sprite2D = world.get_node_or_null("Background") as Sprite2D
	var order_ok: bool = bg != null and tavern != null \
			and bg.get_index() < tavern.get_index() and bg.z_index <= tavern.z_index
	_report("地窖底图先画、酒馆底图后画（门洞才透得出来）", order_ok,
			"index bg=%d tavern=%d" % [
					-1 if bg == null else bg.get_index(),
					-1 if tavern == null else tavern.get_index()])


func _check_camera(world: Node) -> void:
	var cam: PixelCamera = world.get_node_or_null("Sorted/Player/Camera") as PixelCamera
	var ok: bool = cam != null and cam.limit_top == int(CELLAR_OFFSET_Y) \
			and cam.limit_bottom == 384
	_report("相机限位覆盖上下两间房（y -398..384）", ok,
			"限位=[%d,%d]-[%d,%d]" % [cam.limit_left, cam.limit_top,
					cam.limit_right, cam.limit_bottom] if cam else "无相机")


func _check_walls(world: Node) -> void:
	# 北墙在门洞处必须断开，否则人走不过去
	var stat: StaticBody2D = world.get_node_or_null("Static") as StaticBody2D
	var blocked: bool = _solid_at(stat, Vector2(LANE_X, 44))
	_report("酒馆北墙在门洞处断开（人能走过去）", stat != null and not blocked,
			"门洞中线 (126,44) 命中墙=%s" % blocked)

	# 门洞两侧仍然是墙（没有把整面墙拆了）
	var left_blocked: bool = _solid_at(stat, Vector2(90, 44))
	var right_blocked: bool = _solid_at(stat, Vector2(170, 44))
	_report("门洞两侧的墙还在", left_blocked and right_blocked,
			"x=90 命中=%s / x=170 命中=%s" % [left_blocked, right_blocked])

	# 地窖四周要有自己的墙（不然从门洞进去就能走出图外）
	var cw: StaticBody2D = world.get_node_or_null("CellarWalls") as StaticBody2D
	var n_blocked: bool = _solid_at(cw, Vector2(320, -380))
	var w_blocked: bool = _solid_at(cw, Vector2(60, -150))
	var e_blocked: bool = _solid_at(cw, Vector2(580, -150))
	_report("地窖有自己的北墙/东西墙", cw != null and n_blocked and w_blocked and e_blocked,
			"北=%s 西=%s 东=%s" % [n_blocked, w_blocked, e_blocked])

	var cb: StaticBody2D = world.get_node_or_null("CellarBlockers") as StaticBody2D
	_report("地窖的木箱/酒桶碰撞还在", cb != null and cb.get_child_count() >= 7,
			"碰撞块=%d" % (0 if cb == null else cb.get_child_count()))


func _check_cellar_light(world: Node) -> void:
	var lamp: PointLight2D = world.get_node_or_null("Lighting/CellarLamp") as PointLight2D
	_report("地窖有自己那盏吊灯（只照角色 light_mask=2）",
			lamp != null and lamp.range_item_cull_mask == 2 and lamp.energy > 0.0,
			"灯=%s" % str(lamp))


func _check_pot(world: Node) -> void:
	var pot: Node2D = world.get_node_or_null("Sorted/BrewingPot") as Node2D
	var zone: Area2D = (pot.get_node_or_null("Zone") as Area2D) if pot != null else null
	_report("锅在楼上的地窖里 (278,-193)，带 [E] 酿造交互区",
			pot != null and pot.position.distance_to(Vector2(278, -193)) < 1.0
			and zone != null and zone.panel_scene != null,
			"位置=%s 交互区=%s" % [Vector2.INF if pot == null else pot.position, zone != null])

	var lit: Node = null
	if pot != null:
		var lp: NodePath = pot.get("lighting_path") as NodePath
		lit = pot.get_node_or_null(lp) if lp != null else null
	_report("锅找到了光照导演（夜里用夜景贴图）",
			lit != null and lit.get_script() != null
			and str((lit.get_script() as Script).resource_path).ends_with("lighting_director.gd"),
			"节点=%s" % str(lit))


## 门不是被删掉了：底图上的门被抠开，同时把抠掉的那块像素原样贴回一层盖着。
## 远看 = 原样的关着的门；走近 = 淡出 = 门虚化，露出地窖的楼梯。
func _check_door_layer(world: Node) -> void:
	var door: Sprite2D = world.get_node_or_null("CellarDoor") as Sprite2D
	var want_size: Vector2 = Vector2(HOLE.size.x * 2, HOLE.size.y * 2)
	var ok: bool = door != null and door.get_script() != null \
			and door.texture != null and door.texture.get_size() == want_size \
			and door.position == HOLE.position and door.scale == Vector2(0.5, 0.5)
	_report("门板虚化层正好盖住门洞（%d×%d 裁片，落在 %d,%d）"
			% [int(want_size.x), int(want_size.y), int(HOLE.position.x), int(HOLE.position.y)], ok,
			"节点=%s 尺寸=%s offset=%s scale=%s" % [
					str(door), "<无>" if door == null or door.texture == null
					else str(door.texture.get_size()),
					"<无>" if door == null else str(door.position),
					"<无>" if door == null else str(door.scale)])

	# 门板裁片必须是**不透明**的（是原底图那一块原样裁下来的，不是空的）
	var panel: Image = Image.load_from_file(
			"res://assets/house/v4/door_panel_day_v16.png")
	var cx: int = int(want_size.x) >> 1
	var cy: int = int(want_size.y) >> 1
	var opaque: bool = panel != null and panel.get_pixel(cx, cy).a > 0.99
	_report("门板裁片里有门（不是空白贴片）", opaque,
			"尺寸=%s 门板处 alpha=%.2f" % [
					"<无>" if panel == null else str(panel.get_size()),
					0.0 if panel == null else panel.get_pixel(cx, cy).a])

	# 裁片尺寸必须和抠洞矩形一致（两边共用 tools/punch_cellar_passage.py 的 HOLE）
	var want: Vector2i = Vector2i(int(want_size.x), int(want_size.y))
	var tight: bool = panel != null and panel.get_size() == want
	_report("裁片尺寸 = 门洞尺寸（裁小了盖不住、裁大了会盖墙）", tight,
			"裁片=%s 门洞=%s" % [
					"<无>" if panel == null else str(panel.get_size()), str(want)])

	# 四个时段都要有一张，且都盖在同一个位置
	var phases: Array[String] = ["dawn", "day", "dusk", "night"]
	var all_there: bool = true
	for p: String in phases:
		var path: String = "res://assets/house/v4/door_panel_%s_v16.png" % p
		if not ResourceLoader.exists(path):
			all_there = false
	_report("四个时段各有一张门板裁片（夜里不会盖白天的门）", all_there, "dawn/day/dusk/night")


## 地窖整体阴影：玩家在店堂里时上层那间地窖压一层暗色，人走上楼梯时收掉。
func _check_cellar_shade(world: Node) -> void:
	var shade: Polygon2D = world.get_node_or_null("CellarShade") as Polygon2D
	var poly: PackedVector2Array = shade.polygon if shade != null else PackedVector2Array()
	var covers: bool = not poly.is_empty()
	for p: Vector2 in poly:
		if p.y > 0.01:
			covers = false
	_report("地窖整块上盖着一层阴影（铺满 world y<=0）",
			shade != null and covers and shade.z_index > 0,
			"节点=%s 顶点=%d z=%s" % [str(shade), poly.size(),
					"<无>" if shade == null else str(shade.z_index)])

	var script_ok: bool = shade != null and shade.get_script() != null \
			and str((shade.get_script() as Script).resource_path).ends_with("cellar_shade.gd")
	_report("阴影由 cellar_shade.gd 按玩家位置收放", script_ok,
			"脚本=%s" % ("<无>" if shade == null else str(shade.get_script())))

	# 玩家站在店堂中间 → 阴影拉满
	_place(Vector2(320, 270))
	await _wait(50)
	var at_tavern: float = shade.color.a if shade != null else 0.0
	# 玩家上到地窖中间 → 阴影收干（否则会把人一起压黑）
	_place(Vector2(340, -120))
	await _wait(170)
	var at_cellar: float = shade.color.a if shade != null else 1.0
	_report("玩家在店堂里的时候地窖是暗的", at_tavern > 0.35, "alpha=%.2f" % at_tavern)
	_report("玩家走进地窖后阴影收掉", at_cellar < 0.05, "alpha=%.2f" % at_cellar)

	_place(Vector2(320, 270))
	await _wait(20)


## 反向阴影：玩家走进地窖后，下面的店堂整块压一层暗色（和 CellarShade 对称）。
func _check_tavern_shade(world: Node) -> void:
	var shade: Polygon2D = world.get_node_or_null("TavernShade") as Polygon2D
	var poly: PackedVector2Array = shade.polygon if shade != null else PackedVector2Array()
	var covers: bool = not poly.is_empty()
	for p: Vector2 in poly:
		if p.y < -0.01:
			covers = false   # 店堂阴影只该盖 world y>=0 那块，别往下伸到地窖里
	_report("店堂整块上盖着一层反向阴影（铺满 world y>=0）",
			shade != null and covers and shade.z_index > 0,
			"节点=%s 顶点=%d z=%s invert=%s" % [str(shade), poly.size(),
					"<无>" if shade == null else str(shade.z_index),
					"<无>" if shade == null else str(shade.get("invert"))])

	var script_ok: bool = shade != null and shade.get_script() != null \
			and str((shade.get_script() as Script).resource_path).ends_with("cellar_shade.gd")
	_report("反向阴影用同一个 cellar_shade.gd（invert=true）", script_ok and (shade.get("invert") == true),
			"脚本=%s invert=%s" % ["<无>" if shade == null else str(shade.get_script()),
					"<无>" if shade == null else str(shade.get("invert"))])

	# 玩家在店堂里 → 店堂这层不压暗（暗的是上面的地窖）
	# 注意：上一步刚把人放在地窖里（alpha=0.5），这里要多等几帧让淡出收干
	_place(Vector2(320, 270))
	await _wait(120)
	var at_tavern: float = shade.color.a if shade != null else 1.0
	# 玩家走进地窖中间 → 店堂这层拉满
	_place(Vector2(340, -120))
	await _wait(170)
	var at_cellar: float = shade.color.a if shade != null else 0.0
	_report("玩家在店堂里时店堂不压暗（暗的是地窖）", at_tavern < 0.05, "alpha=%.2f" % at_tavern)
	_report("玩家走进地窖后店堂压暗", at_cellar > 0.35, "alpha=%.2f" % at_cellar)

	_place(Vector2(320, 270))
	await _wait(20)


## 距离驱动：远处门关着，走到门前门虚掉。
func _check_door_fade(world: Node) -> void:
	var door: Sprite2D = world.get_node_or_null("CellarDoor") as Sprite2D
	if door == null:
		return
	_place(Vector2(320, 270))
	await _wait(70)
	var far: float = float(door.call("openness"))
	_place(Vector2(126, 96))
	await _wait(70)
	var near: float = float(door.call("openness"))
	_report("站远处门是关着的；走到门前门虚掉露出楼梯",
			far < 0.05 and near > 0.95,
			"远处 openness=%.2f / 门前 openness=%.2f" % [far, near])
	_report("站在门前门没被踩响（门板只是画，不带碰撞）",
			_scene_name() == "World", "场景=%s" % _scene_name())


# ---- 真的走一遍 ----------------------------------------------------------

## 从店堂一直按向上：穿过那扇门，脚下变成地窖的地板，全程不换场景。
func _check_walk_up(world: Node) -> void:
	_place(Vector2(LANE_X, 96))
	await _wait(4)
	var start: Vector2 = _player().global_position
	var reached: bool = await _hold("move_up", func(p: Player) -> bool:
		return p.global_position.y < -150.0, 480)
	var p: Player = _player()
	_report("从店堂一路往北走，穿门进了地窖（不切场景）",
			reached and p != null and get_tree().current_scene == world,
			"起点=%s 终点=%s 场景=%s" % [start,
					Vector2.INF if p == null else p.global_position,
					_scene_name()])

	var pos: Vector2 = p.global_position if p != null else Vector2.INF
	_report("地窖地板在楼上门洞正上方（x 没跑偏）", absf(pos.x - LANE_X) < 6.0,
			"落点 x=%.1f" % pos.x)

	var stat: StaticBody2D = world.get_node_or_null("Static") as StaticBody2D
	_report("人已经越过了酒馆北墙那条线（y<76）", pos.y < 60.0,
			"y=%.1f 墙线=76" % pos.y)
	_report("上楼之后仍算「自家屋檐下」（in_tavern）", Story.in_tavern(),
			"in_tavern=%s" % Story.in_tavern())


## 再一路按向下：原路走回店堂。
func _check_walk_down(world: Node) -> void:
	var back: bool = await _hold("move_down", func(p: Player) -> bool:
		return p.global_position.y > 96.0, 480)
	var p: Player = _player()
	_report("从地窖原路往南走，回到店堂地板（不切场景）",
			back and p != null and get_tree().current_scene == world,
			"终点=%s 场景=%s" % [Vector2.INF if p == null else p.global_position,
					_scene_name()])
	_report("走回来还是同一个 world 场景（全程零次 change_scene）",
			get_tree().current_scene == world, "场景=%s" % _scene_name())


# ---- helpers -------------------------------------------------------------

## 按住某个方向动作，直到 pred 成立或帧数用尽。返回 pred 是否成立。
func _hold(action: String, pred: Callable, max_frames: int) -> bool:
	Input.action_press(action)
	var hit: bool = false
	for i: int in max_frames:
		await get_tree().physics_frame
		var p: Player = _player()
		if p != null and pred.call(p):
			hit = true
			break
	Input.action_release(action)
	await get_tree().physics_frame
	return hit


## 某个世界坐标点是否落在 body 的任意矩形碰撞里。
func _solid_at(body: StaticBody2D, point: Vector2) -> bool:
	if body == null:
		return false
	for child: Node in body.get_children():
		var col: CollisionShape2D = child as CollisionShape2D
		if col == null or col.shape is RectangleShape2D == false:
			continue
		var size: Vector2 = (col.shape as RectangleShape2D).size
		var rect: Rect2 = Rect2(col.global_position - size * 0.5, size)
		if rect.has_point(point):
			return true
	return false


func _player() -> Player:
	var s: Node = get_tree().current_scene
	return (s.get_node_or_null("Sorted/Player") as Player) if s != null else null


func _scene_name() -> String:
	var s: Node = get_tree().current_scene
	return s.name if s != null else "<null>"


func _place(pos: Vector2) -> void:
	var p: Player = _player()
	if p == null:
		return
	p.velocity = Vector2.ZERO
	p.global_position = pos
	var cam: PixelCamera = p.get_node_or_null("Camera") as PixelCamera
	if cam != null:
		cam.snap_now()


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _report(check_name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", check_name, detail])
