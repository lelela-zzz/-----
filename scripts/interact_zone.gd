class_name InteractZone
extends Area2D
## 「走近 → 浮出提示 → 按 E → 开面板」的通用触发区。
##
## 锅和集市摊位共用这一份：它们只差三件事（提示文案、面板场景、范围大小），
## 所以别再各写一遍。
##
## 四条容易踩的坑，都在这儿处理掉了：
##  1. **玩家是轮询输入**（Input.get_axis），不是事件驱动 —— 光"吃掉事件"不能
##     阻止他继续走，必须真的把 physics_process 关掉，所以面板那边调 set_frozen。
##  2. 开面板的那次 E 还在派发中，直接 add_child 会让新面板收到同一次按键 ——
##     用 call_deferred 推后一帧。
##  3. 面板是"自己关自己"的，所以靠 closed 信号回收引用，而不是等 tree_exited。
##  4. **同一个 E 键现在不止一个主人**（锅、集市摊位、NPC 对话都在抢）。
##     这里用 _input 抢在 NPC 的 _unhandled_input 之前，先做一次仲裁：
##     只要有更近的 NPC 在说话范围里，就把这次按键让出去；
##     否则才自己吃掉。提示同理，同一时刻屏幕上只留一个 [E]。

@export var prompt_text: String = "互动"
@export var panel_scene: PackedScene = null
## 提示相对触发区的偏移（默认浮在范围上方）
@export var prompt_offset: Vector2 = Vector2(0, -52)
## 面板挂到哪个 CanvasLayer；留空则去找当前场景里名为 HUD 的节点
@export var ui_layer_path: NodePath = ^""
## 仲裁参考点：默认用节点自己（锅底）的位置算距离。
@export var arbitrate_from_parent: bool = true

var _prompt: Label = null
var _panel: Node = null
var _inside: bool = false
var _player: Node2D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = UiStyle.outlined_label("[E] %s" % prompt_text)
	_prompt.size = Vector2(180, 16)
	_prompt.position = prompt_offset - Vector2(90, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.z_index = 200
	_prompt.visible = false
	add_child(_prompt)


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_update_prompt()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not _inside or _panel != null:
		return
	if _modal_open():
		return
	if _npc_has_priority():
		return
	get_viewport().set_input_as_handled()
	_open.call_deferred()


func _open() -> void:
	if panel_scene == null or _panel != null:
		return
	var layer: Node = _resolve_ui_layer()
	if layer == null:
		push_error("InteractZone：找不到 UI 层，面板无处安放")
		return
	_panel = panel_scene.instantiate()
	layer.add_child(_panel)
	_panel.closed.connect(_on_panel_closed)
	_update_prompt()


func _on_panel_closed() -> void:
	_panel = null
	_update_prompt()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_inside = true
	_player = body
	_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_inside = false
	_update_prompt()


func _update_prompt() -> void:
	if _prompt == null:
		return
	_prompt.visible = _inside and _panel == null and not _modal_open() and not _npc_has_priority()


## 已经有一层模态面板（对话框、酿造面板、集市）开着时，不再响应。
func _modal_open() -> bool:
	return not get_tree().get_nodes_in_group("modal_ui").is_empty()


## 有 NPC 比这口锅更近、且在说话范围内时，E 归 NPC。
## 用父节点（锅底 / 摊位中心）当参考点 —— 触发区本身是偏上的一块矩形，
## 拿它的中心算距离会平白多给锅 20 来像素的优势。
func _npc_has_priority() -> bool:
	if _player == null:
		return false
	var origin: Node2D = (get_parent() as Node2D) if arbitrate_from_parent and get_parent() is Node2D else self
	var my_dist: float = origin.global_position.distance_to(_player.global_position)
	for node: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Node2D = node as Node2D
		if npc == null:
			continue
		if npc.get("talk_range") == null:
			continue
		var npc_dist: float = npc.global_position.distance_to(_player.global_position)
		if npc_dist <= float(npc.get("talk_range")) and npc_dist < my_dist:
			return true
	return false


func _resolve_ui_layer() -> Node:
	if not ui_layer_path.is_empty():
		var node: Node = get_node_or_null(ui_layer_path)
		if node != null:
			return node
	return UiStyle.ui_layer(self)
