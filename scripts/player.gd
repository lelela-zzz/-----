class_name Player
extends CharacterBody2D
## 四方向移动角色（当前用 3:1 占位色块代替美术）。
##
## 手感三要素：
## 1. 速度不直给，用 move_toward 逼近目标速度 —— 起步有加速、松手有减速；
## 2. 输入吸附到单一轴向 —— 横竖同按时不产生斜向位移，严格四方向；
## 3. 位移交给 move_and_slide —— 贴墙自动滑行，不会撞停。
##
## 本节点不关心光照：环境光由 LightingDirector 写在父节点 Dynamic 的
## modulate 上，炉火由 PointLight2D 叠加（本场景 Body 的 light_mask = 2）。

signal facing_changed(facing: Vector2i)

@export_group("Movement")
## 最大速度（像素/秒）。
@export var move_speed: float = 110.0
## 加速率（像素/秒²），越大起步越"跟手"。
@export var acceleration: float = 900.0
## 减速率（像素/秒²），比加速大一些更有"停稳"的手感。
@export var friction: float = 1400.0
## true = 严格四方向；false = 允许八方向（保留给后续需求）。
@export var four_direction: bool = true

## 当前朝向，仅取四方向单位向量。
## 做成 @export：一次性剧情空间（如灰空间）里玩家全程被面板冻结、没法转向，
## 初始朝向就只能在场景里写死。其余场景不写，取默认朝下。
@export var facing: Vector2i = Vector2i.DOWN

var _input_dir: Vector2 = Vector2.ZERO
## 视觉子节点（四方向行走角色）。若场景没挂/没实现 update_anim 则动画层静默跳过。
var _visual: Node = null
## 被 UI 冻结时不再读输入、不再移动（开面板、进对话都走这一条）。
var _frozen: bool = false


func _ready() -> void:
	add_to_group("player")
	_visual = get_node_or_null("Body")
	# 先按初始朝向摆一次：冻结状态下 _physics_process 不跑，
	# 不在这里刷一帧，玩家就永远顶着默认的朝下姿势。
	if _visual != null and _visual.has_method("update_anim"):
		_visual.update_anim(facing, false)


## UI 面板打开/关闭时调用。冻结时顺便把动作摆回待机，
## 否则会停在一个迈步中途的姿势上。
func set_frozen(value: bool) -> void:
	if _frozen == value:
		return
	_frozen = value
	set_physics_process(not value)
	if value:
		velocity = Vector2.ZERO
		_input_dir = Vector2.ZERO
		if _visual != null and _visual.has_method("update_anim"):
			_visual.update_anim(facing, false)


func is_frozen() -> bool:
	return _frozen


## 读档落位用：直接指定朝向并立刻刷一帧待机姿势（不走输入，也不会被冻结挡住）。
func face(dir: Vector2i) -> void:
	facing = dir if dir != Vector2i.ZERO else Vector2i.DOWN
	if _visual != null and _visual.has_method("update_anim"):
		_visual.update_anim(facing, false)
	facing_changed.emit(facing)


## 读档落位用：瞬移到脚底坐标 + 让相机立刻对齐（不经过物理插值）。
func teleport_to(pos: Vector2) -> void:
	global_position = pos.round()
	velocity = Vector2.ZERO
	_input_dir = Vector2.ZERO
	var cam: Node = get_node_or_null("Camera")
	if cam != null and cam.has_method("snap_now"):
		cam.call("snap_now")


func _physics_process(delta: float) -> void:
	_input_dir = _read_input()
	var target_velocity: Vector2 = _input_dir * move_speed
	var rate: float = acceleration if _input_dir != Vector2.ZERO else friction
	velocity = velocity.move_toward(target_velocity, rate * delta)
	move_and_slide()
	_update_facing()
	if _visual != null and _visual.has_method("update_anim"):
		_visual.update_anim(facing, is_moving())


## 供动画/音效层查询，避免它们自己再读一次输入。
func is_moving() -> bool:
	return _input_dir != Vector2.ZERO


func _read_input() -> Vector2:
	var raw: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if raw == Vector2.ZERO:
		return Vector2.ZERO
	if not four_direction:
		return raw.normalized()
	# 吸附到主轴向：横竖同时按住时，以偏移更大的那一轴为准
	if absf(raw.x) >= absf(raw.y):
		return Vector2(signf(raw.x), 0.0)
	return Vector2(0.0, signf(raw.y))


func _update_facing() -> void:
	if _input_dir == Vector2.ZERO:
		return
	var next: Vector2i = Vector2i(int(signf(_input_dir.x)), int(signf(_input_dir.y)))
	if next != facing:
		facing = next
		facing_changed.emit(facing)
