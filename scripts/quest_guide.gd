extends Node
## 指引系统（autoload QuestGuide）—— 把「追踪的任务」翻译成「当前这张图该往哪走」。
##
## 三段职责，各不越界：
##  ① 重算时机：追踪变了（tracked_changed）、任务进度变了（changed）、换图了 → 重算；
##  ② 路线：交给 MapGraph.route()，算出「要经过哪些图、走哪扇门」的跳序列；
##  ③ 对外只说一件事：当前图里下一步该去的**世界坐标**。
##
## 判定规则（用户 2026-10-27 拍板）：
##  · 当前图 ≠ 目标图 → 指向**下一跳那扇门**（kind="door"）；玩家踩门换图后，
##    这里自动改指新图的下一跳 —— 一路"跑图"到目的地；
##  · 当前图 = 目标图 → 指向目的地本身（kind="dest"）；
##  · 没追踪 / 没 dest / 目标图不可达 / 已走到跟前（≤ARRIVE_DIST）→ 箭头不显示。
##
## 目的地**优先绑节点**：dest 写了 node 就取该节点实时位置（NPC 会游荡、
## 以后挪位指引也不漂）；节点不在了才退回 pos 坐标兜底。

signal waypoint_changed

## 走到离目标多近算"到了"（收起箭头）：略大于门的触发框，别刚踩上就闪。
const ARRIVE_DIST: float = 26.0

var _route: Array[Dictionary] = []
var _key: String = ""
var _point: Vector2 = Vector2.INF
var _kind: String = ""
var _valid: bool = false
var _was_valid: bool = false
var _was_kind: String = ""


func _ready() -> void:
	QuestLog.tracked_changed.connect(_refresh)
	QuestLog.changed.connect(_refresh)
	_refresh()


## 每帧刷一次：目的地可能绑在会动的节点上（游荡的 NPC），换图也顺带兜住 ——
## 比去钩 SceneBootstrap 的信号简单，5 个节点算一次几乎不花钱。
func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	var scene_path: String = scene.scene_file_path if scene != null else ""
	var player: Node2D = player_node()
	var dest: Dictionary = _dest()
	var dest_scene: String = str(dest.get("scene", ""))

	var point: Vector2 = Vector2.INF
	var kind: String = ""
	if player != null and scene != null and not dest_scene.is_empty():
		# 任务做完了就别指了（任务栏里也看不见它）
		var tq: Dictionary = QuestLog.tracked_quest()
		if tq.is_empty() or not bool(tq.get("done", false)):
			var key: String = scene_path + "|" + dest_scene
			if key != _key:
				_key = key
				_route = MapGraph.route(scene_path, dest_scene)
			if scene_path == dest_scene:
				point = _resolve_dest_point(scene, dest)
				kind = "dest"
			elif not _route.is_empty():
				var hop: Dictionary = _route[0] as Dictionary
				var door: Node2D = scene.get_node_or_null(str(hop.get("door", ""))) as Node2D
				if door != null:
					point = MapGraph.door_center(door)
					kind = "door"
			# 走到跟前 → 收起（门口本来就有 [E] 提示 / 直接传送）
			if point != Vector2.INF \
					and player.global_position.distance_to(point) <= ARRIVE_DIST:
				point = Vector2.INF
				kind = ""

	_point = point
	_kind = kind
	_valid = point != Vector2.INF
	if _valid != _was_valid or _kind != _was_kind:
		_was_valid = _valid
		_was_kind = _kind
		waypoint_changed.emit()


## --- 对外接口 -----------------------------------------------------------

## 有可指的目标吗（没追踪 / 没 dest / 不可达 / 已到跟前 → false）。
func valid() -> bool:
	return _valid


## 当前图里下一步该去的**世界坐标**（脚底同一套坐标系）。
func waypoint() -> Vector2:
	return _point if _valid else Vector2.ZERO


## "door" = 正在指下一跳的传送门；"dest" = 已经在目标图里、正指目的地。
func kind() -> String:
	return _kind


## 还剩几跳才到目标图（已经在目标图 = 0）。给调试 / 测试看。
func hops_left() -> int:
	return _route.size()


## 目标图的显示名（比如「卢迪克集市」），没有则返回空串。
func dest_name() -> String:
	var d: Dictionary = _dest()
	if d.is_empty():
		return ""
	return MapGraph.label_of(MapGraph.id_of_scene(str(d.get("scene", ""))))


## 当前场景里的玩家 —— 和 UiPanel._freeze_player 同一个来源（"player" 组），
## 别去硬连节点路径，换场景 / 测试挂载都靠得住。
func player_node() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


## --- 内部 ---------------------------------------------------------------

func _dest() -> Dictionary:
	var q: Dictionary = QuestLog.tracked_quest()
	if q.is_empty():
		return {}
	return q.get("dest", {}) as Dictionary


## 目的地坐标：**绑节点优先**（取实时位置），节点没了退回 pos，都没有 → INF。
func _resolve_dest_point(scene: Node, dest: Dictionary) -> Vector2:
	var node_path: String = str(dest.get("node", ""))
	if not node_path.is_empty():
		var n: Node2D = scene.get_node_or_null(node_path) as Node2D
		if n != null:
			return n.global_position
	var pos: Variant = dest.get("pos", null)
	if pos != null:
		return _vec(pos)
	return Vector2.INF


static func _vec(v: Variant) -> Vector2:
	if v is Array:
		var a: Array = v as Array
		if a.size() >= 2:
			return Vector2(float(a[0]), float(a[1]))
	elif v is Vector2:
		return v as Vector2
	return Vector2.ZERO


## 世界坐标 → 画布（viewport）坐标。
## 不猜 canvas_transform 的方向：拿玩家（一定在世界里）的两套变换反推出画布变换，
## 再用它变换目标点 —— 数学上精确，缩放 / 相机限位都不会算歪。
static func world_to_canvas(ref: Node2D, world_pos: Vector2) -> Vector2:
	if ref == null:
		return Vector2.ZERO
	var xform: Transform2D = ref.get_global_transform_with_canvas() \
			* ref.global_transform.affine_inverse()
	return xform * world_pos
