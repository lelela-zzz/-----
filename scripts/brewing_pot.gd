class_name BrewingPot
extends Node2D
## 场景里的那口锅：跟背景一起换四时段贴图，并按锅里的状态在「空锅 / 有料」之间切图。
##
## 为什么不用 props.json：那套是"一件家具一套固定贴图"，没有状态概念。
## 锅需要一个额外的维度（空 / 有料），所以自己管两张精灵：
##   Base —— 当前时段的底板
##   Fade —— 下一个时段的浮层，alpha = 过渡权重
## 这和 PropLayer 的做法完全一致，所以换时段时锅和地板是一起渗过去的，不会跳。
##
## 状态只读 BrewingService：任一槽不是空的，锅就是"有料"。锅自己不存任何进度。

const POT_EMPTY: Array[String] = [
	"res://assets/items/pot/pot_empty_dawn.png",
	"res://assets/items/pot/pot_empty.png",
	"res://assets/items/pot/pot_empty_dusk.png",
	"res://assets/items/pot/pot_empty_night.png",
]
const POT_FULL: Array[String] = [
	"res://assets/items/pot/pot_full_dawn.png",
	"res://assets/items/pot/pot_full.png",
	"res://assets/items/pot/pot_full_dusk.png",
	"res://assets/items/pot/pot_full_night.png",
]

## 精灵相对节点原点的偏移：节点原点在锅底（= sort_y），贴图要往上抬。
@export var sprite_offset: Vector2 = Vector2(0, -80)

@export var lighting_path: NodePath = ^"../Lighting"

var _base: Sprite2D = null
var _fade: Sprite2D = null
var _lighting: LightingDirector = null
var _with_content: bool = false
var _from_phase: int = LightingDirector.PHASE_DAY
var _to_phase: int = LightingDirector.PHASE_DAY
var _weight: float = 0.0
var _tex_cache: Dictionary = {}


func _ready() -> void:
	_base = get_node_or_null("Base") as Sprite2D
	_fade = get_node_or_null("Fade") as Sprite2D
	if _base == null or _fade == null:
		push_error("BrewingPot：缺 Base / Fade 精灵")
		return
	_base.position = Vector2.ZERO
	_fade.position = Vector2.ZERO
	_base.offset = sprite_offset
	_fade.offset = sprite_offset
	_fade.modulate = Color(1, 1, 1, 0)

	_with_content = _has_content()
	_apply_visual()

	_lighting = get_node_or_null(lighting_path) as LightingDirector
	if _lighting == null:
		push_warning("BrewingPot：没找到 LightingDirector，锅将固定用白天贴图")
		return
	_lighting.transition_changed.connect(_on_transition)
	_sync_initial.call_deferred()


func _process(_delta: float) -> void:
	var content: bool = _has_content()
	if content != _with_content:
		_with_content = content
		_apply_visual()


func _has_content() -> bool:
	for slot: Dictionary in BrewingService.slots:
		if int(slot["state"]) != BrewingService.State.EMPTY:
			return true
	return false


func _sync_initial() -> void:
	if _lighting != null:
		_on_transition(_lighting.from_phase, _lighting.to_phase, _lighting.last_weight)


func _on_transition(from_phase: int, to_phase: int, weight: float) -> void:
	if from_phase == _from_phase and to_phase == _to_phase and is_equal_approx(weight, _weight):
		return
	_from_phase = from_phase
	_to_phase = to_phase
	_weight = weight
	_apply_visual()


func _apply_visual() -> void:
	var paths: Array[String] = POT_FULL if _with_content else POT_EMPTY
	_base.texture = _texture(paths[clampi(_from_phase, 0, 3)])
	_fade.texture = _texture(paths[clampi(_to_phase, 0, 3)])
	_fade.modulate = Color(1, 1, 1, clampf(_weight, 0.0, 1.0))


func _texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) as Texture2D
	return _tex_cache[path] as Texture2D
