class_name PixelCamera
extends Camera2D
## 像素 perfect 跟随镜头：限位 + 帧率无关的平滑 + 整数取整。
##
## 大地图三件事都收敛在这一个节点里：
##   1. limit_*：由 map_rect 推出四至，镜头永不滑出地图露底；
##   2. 平滑：手动 lerp（1 - exp(-k·dt)），不用内置 position_smoothing——
##      内置平滑在渲染侧插值，会出现亚像素，而像素游戏必须自己控制取整时机；
##   3. 取整：每帧把相机位置 round 到整数像素，配合 snap_2d_transforms_to_pixel，
##      NEAREST 采样才不会糊。
##
## 作为 Player 子节点使用，但 top_level = true：位置完全独立驱动，
## 不继承父节点的位移（否则"父节点移动 + 平滑滞后"会抖成两层）。

@export_group("Follow")
## 跟随目标（默认父节点，即 Player）。
@export var target_path: NodePath = ^".."
## 平滑系数（越大越跟手）；0 = 硬跟随。
@export_range(0.0, 30.0, 0.1) var smoothing: float = 8.0
## 目标点相对脚底的抬升（取身体中心，观感与室内 probe 一致）。
@export var target_lift: Vector2 = Vector2(0.0, -24.0)

@export_group("Map")
## 地图四至（世界坐标），决定 limit_* 与镜头可达范围。
@export var map_rect: Rect2 = Rect2(0.0, 0.0, 866.0, 866.0)

var _target: Node2D = null


func _ready() -> void:
	top_level = true
	_target = get_node_or_null(target_path) as Node2D
	# A 路线：viewport 是 640×384 逻辑的 2 倍渲染，相机按同样倍数放大，
	# 于是"看得见的世界范围"仍是 640×384 —— 位置、limit、平滑全不用改。
	zoom = WindowScale.render_scale()
	limit_left = int(map_rect.position.x)
	limit_top = int(map_rect.position.y)
	limit_right = int(map_rect.end.x)
	limit_bottom = int(map_rect.end.y)
	make_current()
	snap_now()


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var goal: Vector2 = _target.global_position + target_lift
	if smoothing <= 0.0:
		global_position = goal
	else:
		var t: float = 1.0 - exp(-smoothing * delta)
		global_position = global_position.lerp(goal, t)
	global_position = global_position.round()


## 立刻贴到目标点（传送落点、测试摆位后调用，避免平滑飞镜）。
func snap_now() -> void:
	if _target != null:
		global_position = (_target.global_position + target_lift).round()
