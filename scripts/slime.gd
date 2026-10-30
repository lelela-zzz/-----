class_name Slime
extends Node2D
## 矿井史莱姆：存活态（圆顶弹跳）→ 被姜酒杀死 → 崩解成地面粘液尸体。
##
## 由 ChapterStory 在第一章矿井幕（ch1_mine_edward）里实例化与驱动：
##   · 进场时以存活态摆在中央洞穴（_spawn_mine_slimes）；
##   · 玩家与爱德华开始对话后朝二人靠近（start_approach）；
##   · 台词推进到「姜酒杀死史莱姆」时逐个 die()，崩解成尸体留在原地。
##
## 碰撞（三层，全部在脚底那一圈上算）：
##   · 世界碰撞箱来自矿井 props.json 的 collision_rect（ChapterStory 传入
##     configure_collision）。移动按 X / Y 两轴分别试探，撞到就撤、另一轴照走
##     → 撞墙会停住并沿墙滑动，绝不穿过箱体；
##   · 路点：从洞穴上来先走「洞口」，避免直线奔目标时怼在岩壁拐角里出不来；
##   · 史莱姆之间做分离，靠得太近互相推开，不会叠成一坨。
##
## 原点 = 脚底（与 Player / Npc 一致），放进 y 排序的 Sorted 容器后遮挡关系正确。

const ALIVE_TEX_PATH: String = "res://assets/creatures/red_slime/slime_alive.png"
const DEAD_TEX_PATH: String = "res://assets/creatures/red_slime/slime_dead.png"

## 世界缩放：源图按 1024 基准绘制，0.07 → 存活圆顶约 55×57 px、尸体约 59×36 px。
const WORLD_SCALE: float = 0.07
## 靠近目标时停在多远处（像素），避免整只压在玩家身上。
const STOP_DISTANCE: float = 46.0
## 靠近速度（像素/秒），比玩家慢，不抢镜。
const WALK_SPEED: float = 30.0
## 移动判定用的**精灵框**（脚底 = 原点、身子往上是正的）。
## 必须和 ChapterStory 摆放时用的 SLIME_HALF_W / SLIME_HEIGHT 一致：
##  · 只测脚下小圆 → 会出现"脚踩在地上、半个身子插进岩壁"；
##  · 而且小圆往下多探 13px，贴着矮石块时就过不去，会卡在半路到不了站位。
const MOVE_HALF_W: float = 28.0
const MOVE_HEIGHT: float = 58.0
## 连续多少帧"想动却动不了"就放弃这个站位（0.75s @60fps），免得贴墙原地抖。
const STALL_LIMIT: int = 45
## 史莱姆之间的最小间距（像素）：小于它就互相推开，避免重叠。
## 取 48：大于身子直径（26），也大于视觉上"看着还分得开"的宽度，
## 这样围成一圈时是一颗颗独立的胶团，不是一坨。
const MIN_SEPARATION: float = 48.0
## 分离推挤的最大速度（像素/秒）。给得比较硬：靠近速度只有 30，
## 只有分离力明显大于它，挤在一起时才推得开（软绵绵的力等于没推开）。
const SEPARATION_SPEED: float = 300.0
## 走到路点多近算到达（像素）。
const WAYPOINT_REACH: float = 10.0
## 走到"站位"多近算到位（像素）。
const GOAL_ARRIVE: float = 2.0

enum State { ALIVE, DYING, DEAD }

var state: int = State.ALIVE

var _alive_tex: Texture2D = null
var _dead_tex: Texture2D = null
var _sprite: Sprite2D = null
var _approach: bool = false
var _target: Node2D = null
var _bob_phase: float = 0.0
var _dying_tween: Tween = null
## 世界碰撞矩形（props.json 的 collision_rect）与可行走边界。
var _rects: Array = []
var _bounds: Rect2 = Rect2()
var _has_bounds: bool = false
## 先走完的路点（走到一个 pop 一个），清空后才直奔 _target。
var _waypoints: Array[Vector2] = []
## 固定站位：包围时每只分一个环形点，设了就一直朝那儿走、到了就停。
var _goal: Vector2 = Vector2.ZERO
var _has_goal: bool = false
## 连续推不动的帧数（见 STALL_LIMIT）。
var _stall: int = 0


func _ready() -> void:
	add_to_group("slime")
	_alive_tex = load(ALIVE_TEX_PATH) as Texture2D
	_dead_tex = load(DEAD_TEX_PATH) as Texture2D
	_sprite = get_node_or_null("Sprite") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		add_child(_sprite)
	_bob_phase = randf() * TAU
	_apply_alive()


## 由 ChapterStory 摆进场后调用：交给它该场景的碰撞箱与可行走边界。
func configure_collision(rects: Array, bounds: Rect2) -> void:
	_rects = rects
	_bounds = bounds
	_has_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0


## 切到存活贴图并让底边压在节点原点（脚底）。
func _apply_alive() -> void:
	if _sprite == null or _alive_tex == null:
		return
	_sprite.texture = _alive_tex
	_sprite.centered = true
	_sprite.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	_sprite.position = Vector2(0.0, -_alive_tex.get_height() * WORLD_SCALE * 0.5)


## 切到尸体（粘液）贴图，同样底边贴地。
func _apply_dead() -> void:
	if _sprite == null or _dead_tex == null:
		return
	_sprite.texture = _dead_tex
	_sprite.centered = true
	_sprite.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	_sprite.position = Vector2(0.0, -_dead_tex.get_height() * WORLD_SCALE * 0.5)


## 开始朝目标（玩家 / 爱德华）靠近。
func start_approach(target: Node2D) -> void:
	_target = target
	_approach = true


## 设置中途路点（按顺序走）。用来让洞穴里的史莱姆先爬出洞口再找人。
func set_waypoints(points: Array) -> void:
	_waypoints.clear()
	for p: Variant in points:
		if p is Vector2:
			_waypoints.append(p as Vector2)


## 分配一个固定站位（包围圈上的点）。比"直奔目标脚下"散得开：
## 每只各站一个角度，围成一圈而不是挤成一坨。
func set_goal(point: Vector2) -> void:
	_goal = point
	_has_goal = true
	_approach = true


func _process(delta: float) -> void:
	if state != State.ALIVE:
		return
	if _sprite != null and _alive_tex != null:
		# 轻微的胶质呼吸感（只上下浮动一两像素）
		_bob_phase += delta * 3.0
		var bob: float = sin(_bob_phase) * 1.5
		_sprite.position.y = -_alive_tex.get_height() * WORLD_SCALE * 0.5 + bob

	var vel: Vector2 = Vector2.ZERO
	if _approach:
		vel += _seek_velocity()
	vel += _separation_velocity()
	if vel != Vector2.ZERO:
		var before: Vector2 = global_position
		_try_move(vel * delta)
		if global_position.distance_squared_to(before) < 0.0001:
			_stall += 1
			if _stall > STALL_LIMIT:
				# 顶着石头推不动了：认命停在这儿，别在原地一直抖
				_stall = 0
				_has_goal = false
				_waypoints.clear()
		else:
			_stall = 0


## 朝「当前该去的地方」走：路点 → 站位 → 目标节点，谁在前面听谁的。
func _seek_velocity() -> Vector2:
	# 先把已经走到的路点弹掉（一帧最多弹一个，够用且省事）
	while not _waypoints.is_empty():
		if global_position.distance_to(_waypoints[0]) <= WAYPOINT_REACH:
			_waypoints.remove_at(0)
		else:
			break
	var goal: Vector2 = Vector2.ZERO
	var stop_at: float = STOP_DISTANCE
	var has_goal: bool = false
	if not _waypoints.is_empty():
		goal = _waypoints[0]
		stop_at = 2.0
		has_goal = true
	elif _has_goal:
		goal = _goal
		stop_at = GOAL_ARRIVE
		has_goal = true
	elif _target != null and is_instance_valid(_target):
		goal = _target.global_position
		has_goal = true
	if not has_goal:
		return Vector2.ZERO
	var to: Vector2 = goal - global_position
	if to.length() <= stop_at:
		return Vector2.ZERO
	return to.normalized() * WALK_SPEED


## 与其它存活史莱姆的分离推挤：越近推得越狠，离开 MIN_SEPARATION 时归零。
func _separation_velocity() -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for other: Node in get_tree().get_nodes_in_group("slime"):
		if other == self or not is_instance_valid(other):
			continue
		if int(other.get("state")) != State.ALIVE:
			continue
		var other2d: Node2D = other as Node2D
		if other2d == null:
			continue
		var d: Vector2 = global_position - other2d.global_position
		var dist: float = d.length()
		if dist >= MIN_SEPARATION:
			continue
		if dist < 0.01:
			# 完全重合时给一个固定方向，避免除零
			d = Vector2(1.0, 0.0)
			dist = 0.01
		var strength: float = (MIN_SEPARATION - dist) / MIN_SEPARATION
		push += (d / dist) * strength * SEPARATION_SPEED
	return push


## 逐轴移动：X 轴撞了就撤、Y 轴再试 → 撞墙停住并沿墙滑动，不会穿过碰撞箱。
func _try_move(step: Vector2) -> void:
	if step.x != 0.0:
		var nx: float = global_position.x + step.x
		if not _blocked(Vector2(nx, global_position.y)):
			global_position.x = nx
	if step.y != 0.0:
		var ny: float = global_position.y + step.y
		if not _blocked(Vector2(global_position.x, ny)):
			global_position.y = ny


## 该点放不放得下一只史莱姆：用整个**精灵框**去判，不是脚下的小圆。
func _blocked(p: Vector2) -> bool:
	var l: float = p.x - MOVE_HALF_W
	var r: float = p.x + MOVE_HALF_W
	var t: float = p.y - MOVE_HEIGHT
	var b: float = p.y
	if _has_bounds:
		if l < _bounds.position.x or r > _bounds.end.x \
				or t < _bounds.position.y or b > _bounds.end.y:
			return true
	for entry: Variant in _rects:
		var rr: Rect2 = entry as Rect2
		if l < rr.end.x and r > rr.position.x and t < rr.end.y and b > rr.position.y:
			return true
	return false


## 被姜酒杀死：先向下压扁（融化），再换成地上的粘液尸体。
func die() -> void:
	if state != State.ALIVE:
		return
	state = State.DYING
	if _sprite == null:
		_become_dead()
		return
	var base: Vector2 = Vector2(WORLD_SCALE, WORLD_SCALE)
	_dying_tween = create_tween()
	_dying_tween.tween_property(_sprite, "scale",
			Vector2(base.x * 1.25, base.y * 0.28), 0.18)
	_dying_tween.tween_callback(_become_dead)


func _become_dead() -> void:
	state = State.DEAD
	_apply_dead()


## 供测试/调试读：是否已死（尸体）。
func is_dead() -> bool:
	return state == State.DEAD


## 供测试/调试读：被分配的站位点 / 是否还在走向站位。
func goal_point() -> Vector2:
	return _goal


func has_goal() -> bool:
	return _has_goal
