class_name Npc
extends Node2D
## 可交互 NPC：一张 4 列 x 4 行行走图集 → 站在场景里、会转身、能对话。
##
## 定位
## ----
## 玩家用的是 scenes/player.tscn（带输入与移动），NPC 不需要那些：它只需要
## 「视觉 + 朝向 + 触发对话」。所以这里是 Node2D 而不是 CharacterBody2D ——
## 碰撞交给子节点 Body（StaticBody2D），玩家撞上来会停，NPC 自己不受力。
##
## 为什么朝向/待机逻辑自己写而不是复用 Player：
## Player 的朝向来自输入，NPC 的朝向来自「站桩方向 / 游荡方向 / 看向玩家」，
## 数据源不同。共用的只有脚底对齐与 CharacterAnimator 的切帧规则。
##
## 脚底对齐
## --------
## 图集单格 60x120，角色脚底压在格底（y≈120），水平居中 x=30。
## 所以视觉节点的 position = -foot * scale，节点原点即脚底 —— 与 Player 一致，
## 放进 y_sort 的 Sorted 容器后，遮挡关系按脚底那一行排序，天然正确。

signal dialogue_opened(npc_id: String)
signal dialogue_closed(npc_id: String)

## 对话面板场景（留空 = 用默认路径）。
const DIALOGUE_SCENE: String = "res://scenes/ui/dialogue_box.tscn"

## 数据 id（data/npcs.json 里的键），由 NPC 生成器写入。
@export var npc_id: String = ""
## 显示名（对话框标题）。
@export var display_name: String = ""
## 身份/职业（对话框副标题）。
@export var title: String = ""

@export_group("Visual")
## 行走图集（4 列 x 4 行）。
@export var sheet: Texture2D
@export var cell_size: Vector2i = Vector2i(60, 120)
## 视觉缩放。0.5 = 60x120 的格子显示成 30x60，与玩家同一尺度。
@export var sprite_scale: float = 0.5
## 脚底在格子内的坐标（水平中心, 底边）。用来把视觉顶点对齐到节点原点。
@export var foot_in_cell: Vector2 = Vector2(30, 120)

@export_group("Behaviour")
## 初始朝向（up / down / left / right）。
@export var facing: String = "down"
## 游荡半径，0 = 站桩。>0 时会在原点周围随机走走停停。
@export var wander_radius: float = 0.0
## 矩形游荡区（世界坐标 x, y, w, h）。设了它就用矩形内随机点，忽略 wander_radius。
## 想让某人在指定区域（比如吧台后面）踱步、而不是绕原点乱走时用它。
@export var wander_rect: Rect2 = Rect2()
## 幽灵模式：关掉脚底碰撞，玩家/顾客可以从身上走过。
## 用于"在店里游荡但绝不能挡路"的角色（老板娘）。
@export var ghost: bool = false
## 固定巡逻路线（世界坐标点列表，按顺序循环走）。设了它就沿这条路线踱步，
## 优先于 wander_rect / wander_radius。点应轴对齐（相邻两点 x 或 y 相同），
## 因为移动是四方向的 —— 轴对齐的腿才能走得直、不斜穿家具。点数 <2 忽略。
@export var patrol_route: PackedVector2Array = PackedVector2Array()
## 可对话距离（像素，按脚底算）。
@export var talk_range: float = 46.0
## 不可交互：纯展示位（墙边酣睡的粉发少女等）。不出 [E] 提示、按 E 无反应，
## 也不参与「最近的人抢 E」判定——免得她站在玩家附近时压住别人的提示。
@export var no_interact: bool = false
## 排队顾客在「最近的人抢 E」里的让位优势（等效像素）。见 _is_nearest()。
const CUSTOMER_E_BIAS: float = 30.0
## 游荡速度（像素/秒），比玩家慢，NPC 不该抢镜。
@export var walk_speed: float = 26.0

@export_group("Dialogue")
## 对话内容，一条一句，按 E 推进。
@export var lines: PackedStringArray = []

@export_group("Wiring")
## LightingDirector 路径，用来跟昼夜环境色同步（找不到就退回读玩家 modulate）。
@export var lighting_path: NodePath = ^"../../Lighting"

var _anim: CharacterAnimator = null
var _prompt: Label = null
var _player: Node2D = null
var _home: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _idle_left: float = 0.0
var _moving: bool = false
var _talking: bool = false
var _dir: Vector2i = Vector2i.DOWN
## 巡逻路线当前要去的路点下标（仅 patrol_route 非空时用）。
var _patrol_i: int = 0
## hold / hold_at 之前记住的游荡配置，resume_wander() 时还原（见下方方法）。
var _stored_wander: Dictionary = {}


func configure(def: Dictionary, place: Dictionary) -> void:
	## 由 NpcSpawner 在 add_child 之前调用：先把数据和资源塞进来，
	## 这样 CharacterAnimator 的 _ready 里就能直接拿到 sheet 建帧。
	npc_id = str(def.get("id", ""))
	display_name = str(def.get("name", ""))
	title = str(def.get("title", ""))
	var cell: Array = def.get("cell", [60, 120])
	cell_size = Vector2i(int(cell[0]), int(cell[1]))
	var foot: Array = def.get("foot", [30, 120])
	foot_in_cell = Vector2(float(foot[0]), float(foot[1]))
	sprite_scale = float(def.get("scale", 0.5))
	var loaded: Texture2D = load(str(def.get("sheet", ""))) as Texture2D
	if loaded != null:
		sheet = loaded
	# 台词：位置专用优先。同一个角色在不同场景说不同的话（凯瑟琳在集市是摊主口吻、
	# 在酒馆是顾客口吻），就把 lines 写在 placement 里；没写才退回顶层默认台词。
	var own_lines: Array = place.get("lines", []) as Array
	lines = PackedStringArray(own_lines if not own_lines.is_empty()
			else (def.get("lines", []) as Array))

	facing = str(place.get("facing", "down"))
	wander_radius = float(place.get("wander", 0.0))
	no_interact = bool(place.get("no_interact", false))
	ghost = bool(place.get("ghost", false))
	var wr: Variant = place.get("wander_rect", null)
	if wr is Array and (wr as Array).size() >= 4:
		var a: Array = wr as Array
		wander_rect = Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	var pr: Variant = place.get("patrol_route", null)
	if pr is Array:
		var route: PackedVector2Array = PackedVector2Array()
		for pt: Variant in pr as Array:
			if pt is Array and (pt as Array).size() >= 2:
				var q: Array = pt as Array
				route.append(Vector2(float(q[0]), float(q[1])))
		if route.size() >= 2:
			patrol_route = route
	var pos: Array = place.get("pos", [0, 0])
	position = Vector2(float(pos[0]), float(pos[1]))


func _ready() -> void:
	add_to_group("npc")
	# 幽灵模式：脚底碰撞挪到"哪层都不在" → 玩家/顾客穿身而过，绝不挡路。
	if ghost:
		var body: Node = get_node_or_null("Body")
		if body is CollisionObject2D:
			(body as CollisionObject2D).collision_layer = 0
			(body as CollisionObject2D).collision_mask = 0
	_home = position
	_target = position
	_dir = _dir_from_name(facing)
	# 出生点若正好在路线首点，直接盯第二点，别在原地空等一程。
	if patrol_route.size() >= 2 and position.distance_to(patrol_route[0]) < 3.0:
		_patrol_i = 1

	_anim = get_node_or_null("Anim") as CharacterAnimator
	if _anim == null:
		push_error("Npc %s：缺 Anim 节点" % npc_id)
		return
	_anim.sheet = sheet
	# 图集可能是 4 行（240x480，纯行走）或 5 行（240x600，含坐姿行）。
	# npc.tscn 的 Anim 未显式设 rows（CharacterAnimator 默认 4）。若图集是 5 行却仍按
	# 4 行切，单格会算成 600/4=150px 高 —— 角色整体错位、还会把下一行（左向帧）的头顶
	# 掠进脚下一截（凯瑟琳在集市站桩时就是这个症状）。这里按「图集尺寸 ÷ 声明的格子」
	# 反推行列，由数据驱动：4 行/5 行、以及将来更多行的图集都能正确切格。
	if sheet != null and cell_size.x > 0 and cell_size.y > 0:
		_anim.columns = maxi(1, int(round(float(sheet.get_width()) / float(cell_size.x))))
		_anim.rows = maxi(1, int(round(float(sheet.get_height()) / float(cell_size.y))))
	_anim.scale = Vector2(sprite_scale, sprite_scale)
	_anim.position = -foot_in_cell * sprite_scale
	_anim.update_anim(_dir, false)

	_build_prompt()
	_sync_ambient()
	_connect_lighting()


func _build_prompt() -> void:
	_prompt = UiStyle.outlined_label("[E] 交谈")
	_prompt.size = Vector2(180, 16)
	_prompt.position = Vector2(-90, -foot_in_cell.y * sprite_scale - 22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.z_index = 200
	_prompt.visible = false
	add_child(_prompt)


# ---- 昼夜环境色 ---------------------------------------------------------
# LightingDirector 只往 Player 上写环境色，NPC 不在它的目标里。这里挂到同一条
# transition_changed 上自己取色：优先用它的公开取色接口，老版本没有就抄玩家的。

func _connect_lighting() -> void:
	var lighting: Node = get_node_or_null(lighting_path)
	if lighting == null:
		lighting = get_tree().get_first_node_in_group("lighting")
	if lighting != null and lighting.has_signal("transition_changed"):
		lighting.transition_changed.connect(_on_transition)
		_on_transition(lighting.from_phase, lighting.to_phase, lighting.last_weight)
	else:
		_follow_player_tint()


func _on_transition(_from: int, _to: int, _weight: float) -> void:
	_sync_ambient()


func _sync_ambient() -> void:
	if _anim == null:
		return
	var lighting: Node = get_node_or_null(lighting_path)
	if lighting != null and lighting.has_method("ambient_color"):
		_anim.modulate = lighting.ambient_color()
	else:
		_follow_player_tint()


func _follow_player_tint() -> void:
	if _anim == null:
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p is CanvasItem:
		_anim.modulate = (p as CanvasItem).modulate


# ---- 行为 ---------------------------------------------------------------

## 站定在指定位置并停止一切游荡（剧情对话时，把常驻的萃歌叫到旁边参与用）。
## 调用前会记住原来的游荡配置，之后可用 resume_wander() 恢复，避免"被叫来参与后
## 永久卡死在原地、再也不巡逻"。
func hold_at(pos: Vector2) -> void:
	_store_wander()
	global_position = pos
	_home = pos
	_target = pos
	_moving = false
	_idle_left = 0.0
	wander_radius = 0.0
	wander_rect = Rect2()
	patrol_route = PackedVector2Array()
	_patrol_i = 0


## 原地冻结游荡（不移动位置，仅停下游荡逻辑）。剧情幕开始时把在场的所有游荡角色
## 一起站定，免得老板娘之类的人自顾自走掉；幕结束再 resume_wander()。
func hold() -> void:
	_store_wander()
	_moving = false
	_idle_left = 0.0
	wander_radius = 0.0
	wander_rect = Rect2()
	patrol_route = PackedVector2Array()
	_patrol_i = 0


## 是否正在游荡（给了巡逻路线 / 半径 / 矩形区任一）。供剧情导演判断谁该被冻结。
func is_wandering() -> bool:
	return _wandering()


## 恢复 hold / hold_at 之前记住的游荡配置（巡逻路线 / 半径 / 矩形区）。
func resume_wander() -> void:
	if _stored_wander.is_empty():
		return
	wander_radius = _stored_wander.get("radius", 0.0)
	wander_rect = _stored_wander.get("rect", Rect2())
	patrol_route = _stored_wander.get("route", PackedVector2Array())
	_patrol_i = int(_stored_wander.get("i", 0))
	_stored_wander = {}


## 记住当前游荡配置（只记一次，防止重复 hold 把"已冻结的状态"误当成原始配置）。
func _store_wander() -> void:
	if not _stored_wander.is_empty():
		return
	_stored_wander = {
		"radius": wander_radius,
		"rect": wander_rect,
		"route": patrol_route,
		"i": _patrol_i,
	}


## 转向某个世界坐标（剧情对话时让在场人物都看向玩家/说话处，免得面朝外侧）。
func face_toward(pos: Vector2) -> void:
	var d: Vector2 = pos - global_position
	if absf(d.x) > absf(d.y):
		_dir = Vector2i.RIGHT if d.x > 0.0 else Vector2i.LEFT
	else:
		_dir = Vector2i.DOWN if d.y > 0.0 else Vector2i.UP
	if _anim != null:
		_anim.update_anim(_dir, false)


func _physics_process(delta: float) -> void:
	if _talking:
		_face_player()
		return

	if _wandering():
		_wander_step(delta)

	_update_prompt()
	# 只在站定时才转头看玩家。正在走的人如果被玩家"吸"过去转头，就会出现
	# 身体朝一边、位移朝另一边的朝向/移动不一致 —— 移动中保持行走朝向。
	if _player != null and _in_range() and not _moving:
		_face_player()


## 是否该游荡：给了巡逻路线 / 半径 / 矩形区任一即可。
func _wandering() -> bool:
	return patrol_route.size() >= 2 or wander_radius > 0.0 \
			or (wander_rect.size.x > 0.0 and wander_rect.size.y > 0.0)


func _wander_step(delta: float) -> void:
	if _idle_left > 0.0:
		# 到点后原地歇一会儿（一直走会像巡逻兵，酒馆里该是松松垮垮的）
		_idle_left -= delta
		return

	var patrolling: bool = patrol_route.size() >= 2
	if not _moving:
		# 开始走向新目标。⚠️ 这里**不能**同时设 _idle_left —— 老代码在这里既设了
		# idle 又把 _moving 置 true，结果下一帧就被上面的 idle 分支立刻取消，
		# 导致所有"游荡"的 NPC 其实从没挪过窝。休息只发生在到达之后。
		_target = patrol_route[_patrol_i] if patrolling else _random_target()
		_dir = _dir_toward(_target - position)
		_moving = true
		if _anim != null:
			_anim.update_anim(_dir, true)
		return

	var to: Vector2 = _target - position
	var arrive: float = 2.0 if patrolling else 1.0
	if to.length() <= arrive:
		_moving = false
		if patrolling:
			# 走到一站：换下一站（环形），停一小会儿再走
			_patrol_i = (_patrol_i + 1) % patrol_route.size()
			_idle_left = randf_range(0.6, 1.4)
		else:
			_idle_left = randf_range(1.0, 3.0)
		if _anim != null:
			_anim.update_anim(_dir, false)
		return
	_dir = _dir_toward(to)
	position += _dir_to_vec(_dir) * walk_speed * delta
	if _anim != null:
		_anim.update_anim(_dir, true)


func _pick_point() -> Vector2:
	# 矩形区优先：想让某人固定在某块地方踱步（比如吧台后面）时用它，
	# 这样不会绕原点乱跑、也不会窜到顾客/柜台的服务带上。
	if wander_rect.size.x > 0.0 and wander_rect.size.y > 0.0:
		return Vector2(
			randf_range(wander_rect.position.x, wander_rect.position.x + wander_rect.size.x),
			randf_range(wander_rect.position.y, wander_rect.position.y + wander_rect.size.y))
	var angle: float = randf() * TAU
	var r: float = sqrt(randf()) * wander_radius
	return _home + Vector2(cos(angle), sin(angle) * 0.6) * r


func _random_target() -> Vector2:
	var t: Vector2 = _pick_point()
	# 尽量别停在玩家身上：就算没开 ghost，游荡的人也不该正好站着挡路。
	if _player != null:
		for _i: int in 3:
			if t.distance_to(_player.global_position) >= 44.0:
				break
			t = _pick_point()
	return t


func _face_player() -> void:
	if _player == null:
		return
	var d: Vector2i = _dir_toward(_player.global_position - position)
	if d != _dir:
		_dir = d
		_anim.update_anim(_dir, false)


func _update_prompt() -> void:
	if _prompt == null:
		return
	_prompt.visible = not no_interact and not _talking \
			and _player != null and _in_range() and _is_nearest()


func _is_nearest() -> bool:
	## 两个 NPC 挨得近时只让最近的那个出提示，否则屏幕上一堆 [E]。
	##
	## 排队等卖酒的顾客额外让出一档（等效压近 30px）：玩家站在柜台后服务时，
	## 站在旁边的老板娘/路人**不该**把 E 抢走 —— 这是最初「老板娘挡交互」的病根，
	## 光靠挪位置治不干净（玩家沿吧台走，总会有站在两人中间的一瞬间）。
	## 但玩家走到老板娘身边（十几像素内）时她依然会赢，不影响正常搭话。
	var best: Node = null
	var best_d: float = INF
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = n as Npc
		if npc == null or npc._player == null or npc.no_interact:
			continue
		var d: float = npc.global_position.distance_squared_to(npc._player.global_position)
		if d > npc.talk_range * npc.talk_range:
			continue
		# 用 has_method 鸭子判定，别写 `as Customer` —— Customer extends Npc，
		# 反向引用会形成 class_name 循环依赖。
		if npc.has_method("wants_service") and npc.call("wants_service"):
			d -= CUSTOMER_E_BIAS * CUSTOMER_E_BIAS
		if d < best_d:
			best_d = d
			best = npc
	return best == self


func _in_range() -> bool:
	return global_position.distance_to(_player.global_position) <= talk_range


func _process(_delta: float) -> void:
	if _player == null:
		var p: Node = get_tree().get_first_node_in_group("player")
		_player = p as Node2D


func _unhandled_input(event: InputEvent) -> void:
	if _talking or no_interact or not event.is_action_pressed("interact"):
		return
	if _player == null or not _in_range() or not _is_nearest():
		return
	get_viewport().set_input_as_handled()
	_open_dialogue.call_deferred()


# ---- 对话 ---------------------------------------------------------------

func _open_dialogue() -> void:
	if _talking:
		return
	# 玩家主动搭话 = 第一次接触：登记为"已认识"，之后可作为酒客上门买酒。
	# 放在最前：无论后面走常规对话 / 支线 / 章节对话，都先记下这次接触。
	if Regulars != null:
		Regulars.mark_known(npc_id)
	# 序章之后：这位角色若还有没播的支线，先播剧情，再回到常驻对话。
	if SideStory != null and SideStory.try_play(npc_id, self):
		return
	# 章节进行中：若这名角色正是当前幕要交谈的对象，播本章多人对话并接管。
	# 这样流程就是「人物先在场，玩家走过去按 E，才开口」，而不是进场景自动播。
	if ChapterStory != null and ChapterStory.try_talk(npc_id, self):
		return
	# 第二章：同理，当前幕要交谈的对象由 Chapter2Story 接管。
	if Chapter2Story != null and Chapter2Story.try_talk(npc_id, self):
		return
	# 第三章（终章）：与第二章同构。
	if Chapter3Story != null and Chapter3Story.try_talk(npc_id, self):
		return
	var layer: Node = _ui_layer()
	if layer == null:
		push_error("Npc %s：找不到 HUD 层" % npc_id)
		return
	var scene: PackedScene = load(DIALOGUE_SCENE) as PackedScene
	var box: UiPanel = scene.instantiate() as UiPanel
	box.set("speaker", display_name)
	box.set("role", title)
	box.set("lines", lines)
	box.set("portrait", _portrait())
	layer.add_child(box)
	_talking = true
	_moving = false
	_idle_left = 0.0
	if _prompt != null:
		_prompt.visible = false
	if _anim != null:
		_anim.update_anim(_dir, false)
	box.closed.connect(_on_dialogue_closed)
	dialogue_opened.emit(npc_id)


func _on_dialogue_closed() -> void:
	_talking = false
	dialogue_closed.emit(npc_id)


## 让 NPC 主动开口：不检查距离，不等玩家按键。
## 序章的萃歌由 Story 驱动（开场/回店两段自动台词），玩家手点的对话仍走
## _unhandled_input 那条路 —— 两条路最后都汇进 _open_dialogue。
func talk() -> void:
	_open_dialogue()


## 对话框头像：正面（第 0 行第 0 列）那一帧，运行时切，不额外占资源。
func _portrait() -> Texture2D:
	if sheet == null:
		return null
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(0, 0, cell_size.x, cell_size.y)
	return at


## 对话框挂哪儿：HUD 下的 UIRoot（640×384 + 整体放大），不是 CanvasLayer 本身。
## 挂错地方的话，640 坐标的对话框会缩在屏幕左上角、字还是 1× —— 见 UiStyle.ui_layer。
func _ui_layer() -> Node:
	return UiStyle.ui_layer(self)


# ---- 小工具 -------------------------------------------------------------

func _dir_from_name(name: String) -> Vector2i:
	match name:
		"up":
			return Vector2i.UP
		"left":
			return Vector2i.LEFT
		"right":
			return Vector2i.RIGHT
		_:
			return Vector2i.DOWN


func _dir_toward(delta: Vector2) -> Vector2i:
	if absf(delta.x) >= absf(delta.y):
		return Vector2i.RIGHT if delta.x >= 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if delta.y >= 0.0 else Vector2i.UP


func _dir_to_vec(d: Vector2i) -> Vector2:
	return Vector2(float(d.x), float(d.y))
