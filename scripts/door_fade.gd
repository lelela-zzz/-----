class_name DoorFade
extends Sprite2D
## 门的虚化：酒馆左上角那扇门，远看是关着的，走近才渐渐虚掉、露出后面地窖的楼梯。
##
## 为什么要拆成两层：
##   酒馆和地窖现在是同一张图（地窖底图贴在酒馆上方），人要从这扇门走过去。
##   可是门是**画死在底图里的**，不抠开就永远是一堵墙。所以：
##     1) `tools/punch_cellar_passage.py` 把底图上门那一块抠成透明（洞）；
##     2) 这个节点把**抠掉的那块像素原样贴回来**盖在洞上（`tools/make_door_panel.py`
##        裁的四张裁片，没有新画任何东西）。
##   于是：远 = 不透明 = 和原图一模一样的那扇门；近 = 淡出 = 门虚化，楼梯露出来。
##
## 四张裁片跟着 LightingDirector 的时段换，否则夜里会盖一块白天的门。
## 本节点 z_index 与底图相同、树序排在底图之后，因此**画在底图之上、昼夜过渡层之下** ——
## 黄昏的暖光照样染到门板上。

@export_group("Door")
## 门的锚点（逻辑坐标）= 门洞底边中点。距离按玩家脚底到这里算。
@export var door_anchor: Vector2 = Vector2(126.0, 82.0)
## 多远开始虚化（世界像素）。
@export var open_radius: float = 70.0
## 贴到门前这么近就完全虚化（留一段死区，踩到门口时已经是"洞"了，不会有半透明的半吊子状态）。
@export var full_radius: float = 22.0
## 每秒 alpha 变化量（3.6 ≈ 0.28 秒开到底）。
@export var open_speed: float = 3.6

@export_group("Phase Textures")
## 四张门板裁片，顺序必须是 黎明/白天/黄昏/夜晚（与 LightingDirector 的 PHASE_* 一致）。
@export var phase_textures: PackedStringArray = []

var _player: Node2D = null


func _ready() -> void:
	add_to_group("door_fade")
	modulate.a = 1.0
	# LightingDirector 在树里排在本节点后面，它的 _ready 还没跑（也没进 lighting 组），
	# 所以推迟一帧再绑，否则拿到的是 null。
	_bind_lighting.call_deferred()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
		modulate.a = _target_alpha()
		return
	modulate.a = move_toward(modulate.a, _target_alpha(), open_speed * delta)


## 0 = 离得远（门关着），1 = 贴着门（完全虚化，露出楼梯）。供验收/调试读。
func openness() -> float:
	return clampf(1.0 - modulate.a, 0.0, 1.0)


## 0 = 离得远，1 = 贴着门。
func nearness() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var d: float = door_anchor.distance_to(_player.global_position)
	if d <= full_radius:
		return 1.0
	if d >= open_radius:
		return 0.0
	return 1.0 - (d - full_radius) / (open_radius - full_radius)


func _target_alpha() -> float:
	return 1.0 - nearness()


# ---- 跟昼夜换裁片 --------------------------------------------------------

func _bind_lighting() -> void:
	var dir: Node = get_tree().get_first_node_in_group("lighting")
	if dir == null:
		return
	if dir.has_signal("phase_changed"):
		dir.phase_changed.connect(_on_phase_changed)
	if dir.has_signal("transition_changed"):
		dir.transition_changed.connect(_on_transition)
	_apply_phase(int(dir.get("to_phase")))


func _on_phase_changed(new_phase: int, _label: String) -> void:
	_apply_phase(new_phase)


func _on_transition(from_phase: int, to_phase: int, weight: float) -> void:
	_apply_phase(to_phase if weight > 0.5 else from_phase)


func _apply_phase(index: int) -> void:
	if index < 0 or index >= phase_textures.size():
		return
	var tex: Texture2D = load(phase_textures[index]) as Texture2D
	if tex != null and texture != tex:
		texture = tex
