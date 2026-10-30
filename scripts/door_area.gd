class_name DoorArea
extends Area2D
## 传送门：玩家踩进触发框 → 切场景，并把出生点交给目标场景。
##
## 跨场景出生点用「脚本静态变量」传递：DoorArea.pending_position 在切场景
## 时不随节点销毁（脚本类驻留），目标场景的 SceneBootstrap 在 _ready 里
## 取走并清位。只传一个 Vector2，不引入 Autoload，也不做多余抽象。
##
## 场景里放法：DoorArea + CollisionShape2D(RectangleShape2D)，
## 触发框盖住"门口最后一步"，比障碍碰撞多探出 1-2px 即可。

## 待应用的出生点（世界坐标，脚底）。
static var pending_position: Vector2 = Vector2.ZERO
## 是否有待应用的出生点。
static var has_pending: bool = false
## 待延续的游戏时间（-1 = 无；与出生点同一套静态变量机制，保证昼夜连续）。
static var pending_hour: int = -1
static var pending_minute: int = 0
## 这次要去的场景。给"跨场景要延续状态"的系统用（比如顾客要知道
## "玩家只是下楼进地窖"还是"出门走了"，前者店里得留着人）。
static var pending_target: String = ""

@export_group("Travel")
## 目标场景（切过去的 tscn）。
@export_file("*.tscn") var target_scene: String = ""
## 落在目标场景里的出生点（脚底坐标）。
@export var spawn_position: Vector2 = Vector2.ZERO
## 打开后描出触发框（橙）。
@export var show_debug: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player == false or target_scene.is_empty():
		return
	DoorArea.pending_position = spawn_position
	DoorArea.has_pending = true
	# 关掉再切场景：触发发生在物理回调里，切场景必须 defer 到空闲帧，
	# 否则被释放的 StaticBody2D 会报 "Removing a CollisionObject during physics callback"
	set_deferred("monitoring", false)
	_travel.call_deferred()


func _travel() -> void:
	# 出发前把当前时间带过去：场景各自的 Clock 是新实例，不带走就回到 8 点
	var clock: GameClock = get_tree().current_scene.get_node_or_null("Clock") as GameClock
	if clock != null:
		DoorArea.pending_hour = clock.hour
		DoorArea.pending_minute = clock.minute
	# 记下去哪儿：老场景 _exit_tree 里有人要据此判断"店里还算不算有人在"
	DoorArea.pending_target = target_scene
	get_tree().change_scene_to_file(target_scene)


static func consume_pending() -> Vector2:
	has_pending = false
	return pending_position


func _draw() -> void:
	if not show_debug:
		return
	for child: Node in get_children():
		var col: CollisionShape2D = child as CollisionShape2D
		if col == null or col.shape is RectangleShape2D == false:
			continue
		var rect: RectangleShape2D = col.shape as RectangleShape2D
		draw_rect(Rect2(col.position - rect.size * 0.5, rect.size),
				Color(1.0, 0.8, 0.2, 0.9), false, 1.0)
