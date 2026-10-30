class_name LightingDirector
extends Node
## 昼夜光照导演（渐变版）—— 把离线烘焙的四帧美术变成一条连续曲线。
##
## 原来的写法是四档跳：phase 一变，背景整张换掉、环境色整块换掉，看着是"啪"一下。
## 现在改成按游戏时间插值，两件事分开做：
##
##  1) 背景帧交叉淡入：底板放 from 帧，上面盖一层 to 帧，alpha = 权重。
##     alpha 混合本身就是线性插值（out = from·(1-a) + to·a），所以过渡途中不会掉亮度、
##     不会出现"半透明叠亮"；权重到 1 时下一段自然把 to 变成底板，画面完全连续。
##  2) 动态层与炉火参数：环境色、火光色、光强都用 Color.lerp / lerpf 连续插值，
##     于是角色和点光的色温是滑过去的，而不是跳的。
##
## 时间轴见 TIMELINE：只有"日出/日落"两段是真的过渡，白天与深夜是稳定平台
## （真实光照也是这个脾气，正午不会一直变）。
##
## 手动：1/2/3/4 立刻切四档（会关掉跟随时钟），0 恢复跟随时钟。

signal phase_changed(new_phase: int, label: String)
## 过渡状态变化（给需要跟着换图/淡入的层，比如 PropLayer）。
## 每次时间推进都会发一次；weight 是 from → to 的插值权重。
signal transition_changed(from_phase: int, to_phase: int, weight: float)

## 时段常量，与下面 @export_enum 的顺序一一对应。
const PHASE_DAWN: int = 0
const PHASE_DAY: int = 1
const PHASE_DUSK: int = 2
const PHASE_NIGHT: int = 3

## 一天的分段：每段 [起始小时, 起始帧, 结束帧]。
## 相邻两段的起点就是上一段的终点；起始帧 == 结束帧 即"稳定平台"。
const SEGMENT_START: Array[float] = [0.0, 4.0, 6.0, 9.0, 16.0, 19.0, 22.0]
const SEGMENT_FROM: Array[int] = [
	PHASE_NIGHT, PHASE_NIGHT, PHASE_DAWN, PHASE_DAY, PHASE_DAY, PHASE_DUSK, PHASE_NIGHT
]
const SEGMENT_TO: Array[int] = [
	PHASE_NIGHT, PHASE_DAWN, PHASE_DAY, PHASE_DAY, PHASE_DUSK, PHASE_NIGHT, PHASE_NIGHT
]

@export_group("Scene Wiring")
@export var background_path: NodePath = ^"../Background"
@export var ambient_target_path: NodePath = ^"../Sorted/Player"
@export var hearth_light_path: NodePath = ^"HearthLight"

@export_group("Background Overrides")
## 覆盖四时段背景路径（黎明/白天/黄昏/夜晚）；留空 = 酒馆 v15 默认。
## 村庄等新地图在这里给 4 条路径即可复用整条昼夜管线。
@export var bg_overrides: PackedStringArray = []

@export_group("Time Of Day")
## 初始/当前时段（观察用；真正决定画面的是时钟或 set_phase_instant）。
@export_enum("黎明", "白天", "黄昏", "夜晚") var phase: int = PHASE_DAY
## 跟随 GameClock 连续插值；用 1~4 手动切档时会自动关掉。
@export var follow_clock: bool = true
## 允许用数字键 1~4 手动切档、0 恢复跟随时钟。
@export var debug_keys: bool = true

## 当前过渡状态：from_phase → to_phase 之间，权重 last_weight。只读，给调试和验收看。
var from_phase: int = PHASE_DAY
var to_phase: int = PHASE_DAY
var last_weight: float = 0.0

var _presets: Array[Dictionary] = []
var _tex_cache: Dictionary = {}
var _background: Sprite2D = null
var _fade_layer: Sprite2D = null
var _ambient_target: Node2D = null
var _hearth_light: PointLight2D = null
var _last_hours: float = 8.0


func _ready() -> void:
	add_to_group("lighting")
	_background = get_node_or_null(background_path) as Sprite2D
	_ambient_target = get_node_or_null(ambient_target_path) as Node2D
	_hearth_light = get_node_or_null(hearth_light_path) as PointLight2D
	_build_presets()
	_make_fade_layer()
	_apply_instant()


## 当前环境色（按 from→to 的权重插值）。
## 环境色本来只写在一个目标节点上（默认 Player）；NPC 这类后加的动态层
## 读这里就能跟昼夜同一根曲线，不用自己去猜四个档位的数值。
func ambient_color() -> Color:
	if _presets.is_empty():
		return Color.WHITE
	var from_c: Color = (_presets[from_phase] as Dictionary)["ambient"]
	var to_c: Color = (_presets[to_phase] as Dictionary)["ambient"]
	return from_c.lerp(to_c, last_weight)


func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_manual(PHASE_DAWN)
		KEY_2:
			_manual(PHASE_DAY)
		KEY_3:
			_manual(PHASE_DUSK)
		KEY_4:
			_manual(PHASE_NIGHT)
		KEY_0:
			follow_clock = true
			apply_time(_last_hours)


## 接到 GameClock.time_changed 上（world.tscn 里已连好）。
func set_clock_time(hour: int, minute: int) -> void:
	apply_time(float(hour) + float(minute) / 60.0)


## 按游戏时间（小时，可带小数）连续更新光照。整点、半点都走这一条。
func apply_time(hours: float) -> void:
	_last_hours = hours
	if not follow_clock or _presets.is_empty():
		return

	var h: float = fposmod(hours, 24.0)
	var seg: int = _segment_at(h)
	var from_idx: int = SEGMENT_FROM[seg]
	var to_idx: int = SEGMENT_TO[seg]
	from_phase = from_idx
	to_phase = to_idx
	last_weight = _segment_weight(seg, h)

	var from_p: Dictionary = _presets[from_idx]
	var to_p: Dictionary = _presets[to_idx]

	if _background != null:
		_set_texture(_background, from_p["bg"])
	if _fade_layer != null:
		_set_texture(_fade_layer, to_p["bg"])
		_fade_layer.modulate.a = last_weight
	if _ambient_target != null:
		_ambient_target.modulate = (from_p["ambient"] as Color).lerp(to_p["ambient"], last_weight)
	if _hearth_light != null:
		_hearth_light.color = (from_p["light"] as Color).lerp(to_p["light"], last_weight)
		_hearth_light.energy = lerpf(from_p["energy"], to_p["energy"], last_weight)

	transition_changed.emit(from_phase, to_phase, last_weight)

	var shown: int = to_idx if last_weight > 0.5 else from_idx
	if shown != phase:
		phase = shown
		phase_changed.emit(phase, (_presets[phase] as Dictionary)["label"])


## 立刻切到某一档（手动预览、测试用），不影响 follow_clock。
func set_phase_instant(new_phase: int) -> void:
	phase = new_phase
	from_phase = new_phase
	to_phase = new_phase
	last_weight = 0.0
	_apply_instant()
	transition_changed.emit(from_phase, to_phase, last_weight)


func _manual(new_phase: int) -> void:
	follow_clock = false
	set_phase_instant(new_phase)


func _apply_instant() -> void:
	if _presets.is_empty():
		return
	var preset: Dictionary = _presets[phase]
	if _background != null:
		_set_texture(_background, preset["bg"])
	if _fade_layer != null:
		_fade_layer.modulate.a = 0.0
	if _ambient_target != null:
		_ambient_target.modulate = preset["ambient"]
	if _hearth_light != null:
		_hearth_light.color = preset["light"]
		_hearth_light.energy = preset["energy"]
	phase_changed.emit(phase, preset["label"])
	transition_changed.emit(from_phase, to_phase, last_weight)


## 交叉淡入用的浮层：挂在 Background 下面，同尺寸、同 light_mask，
## z_index 相对父节点 +1，于是正好盖在底板之上、角色之下。
func _make_fade_layer() -> void:
	if _background == null or _fade_layer != null:
		return
	_fade_layer = Sprite2D.new()
	_fade_layer.name = "BackgroundFade"
	_fade_layer.centered = false
	# 注意：淡入层是 Background 的子节点，scale 自动继承（别在这里再乘一次，
	# 否则会变成 0.25 的缩小重影叠在底板上）
	_fade_layer.light_mask = _background.light_mask
	_fade_layer.z_index = 1
	_fade_layer.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_background.add_child(_fade_layer)


func _set_texture(sprite: Sprite2D, path: String) -> void:
	var tex: Texture2D = _texture(path)
	if tex != null and sprite.texture != tex:
		sprite.texture = tex


func _texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) as Texture2D
	return _tex_cache[path]


func _segment_at(hours: float) -> int:
	for i in SEGMENT_START.size():
		var end: float = SEGMENT_START[i + 1] if i + 1 < SEGMENT_START.size() else 24.0
		if hours < end:
			return i
	return SEGMENT_START.size() - 1


## 段内进度，做 smoothstep 让过渡起收都是缓的（线性会让"开始变"和"变完"很生硬）。
func _segment_weight(seg: int, hours: float) -> float:
	var from_idx: int = SEGMENT_FROM[seg]
	var to_idx: int = SEGMENT_TO[seg]
	if from_idx == to_idx:
		return 0.0
	var start: float = SEGMENT_START[seg]
	var end: float = SEGMENT_START[seg + 1] if seg + 1 < SEGMENT_START.size() else 24.0
	var t: float = clampf((hours - start) / maxf(end - start, 0.001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 四个时段的环境光参数，与 relight_v15.py 的 KEY 表同源。
func _build_presets() -> void:
	_presets = [
		{
			"label": "黎明",
			"bg": "res://assets/house/v4/scene_dawn_v16_2x.png",
			"ambient": Color(0.88, 0.92, 1.00),
			"light": Color(1.00, 0.84, 0.68),
			"energy": 0.80,
		},
		{
			"label": "白天",
			"bg": "res://assets/house/v4/scene_day_v16_2x.png",
			"ambient": Color(1.00, 1.00, 1.00),
			"light": Color(1.00, 0.78, 0.52),
			"energy": 0.45,
		},
		{
			"label": "黄昏",
			"bg": "res://assets/house/v4/scene_dusk_v16_2x.png",
			"ambient": Color(0.97, 0.83, 0.72),
			"light": Color(1.00, 0.68, 0.42),
			"energy": 1.00,
		},
		{
			"label": "夜晚",
			"bg": "res://assets/house/v4/scene_night_v16_2x.png",
			"ambient": Color(0.64, 0.60, 0.66),
			"light": Color(1.00, 0.66, 0.38),
			"energy": 1.30,
		},
	]
	if bg_overrides.size() == 4:
		for i in 4:
			_presets[i]["bg"] = bg_overrides[i]
