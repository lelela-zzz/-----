class_name PropLayer
extends Node2D
## 家具层：读 props.json 生成"精灵 + 碰撞框"，并参与 y 排序。
##
## 两套锚点是分开的，这是本次改造的核心：
##   · **渲染排序锚点 = sprite 的 sort_y**（节点 position.y）
##       地面件取脚下那条线（框底），贴墙件取框顶 → 永远排在角色后面
##   · **碰撞判定锚点 = collision_rect**（手量的设计值，可以和画面不一样宽）
## 角色同理：节点原点在脚底、碰撞只有脚下一小块，上半身只参与排序、不参与阻挡。
##
## 光照：家具是按四个时段各抠一套贴图（tools/derive_prop_phases.py），
## 跟着背景一起换图，而不是吃实时光——烘焙光已经算在贴图里了。
## 每个 prop 两个精灵：底板 from 帧 + 浮层 to 帧拉 alpha，和背景的淡入方式一致，
## 所以换时段时家具和地板是一起渗过去的，不会"家具先变、地板后变"。

@export_group("Data")
## props 数据文件（精灵矩形 + 碰撞框 + 排序线，单一来源）。
@export_file("*.json") var props_path: String = "res://assets/house/v4/objects/props.json"
## 时段贴图目录：文件名 = props 条目 name + 时段后缀（_dawn/""/_dusk/_night）。
@export var textures_dir: String = "res://assets/house/v4/objects/"
## 按 LightingDirector 的 PHASE_DAWN / DAY / DUSK / NIGHT 顺序取贴图后缀
const PHASE_SUFFIX: Array[String] = ["_dawn", "", "_dusk", "_night"]

@export var lighting_path: NodePath = ^"../Lighting"
## 贴图相对 866 基准的缩放：2× 贴图目录传 0.5（图翻倍、显示尺寸不变）。
## sprite_rect / sort_y / 碰撞框仍然全是基准坐标，所以传 0.5 不会动任何碰撞。
@export var texture_scale: float = 1.0
## 打开后在画面里描出精灵范围（青）与碰撞框（红）。
@export var show_debug: bool = false

var _bodies: StaticBody2D = null
var _props: Array[Dictionary] = []


func _ready() -> void:
	_build()
	var lighting: LightingDirector = get_node_or_null(lighting_path) as LightingDirector
	if lighting == null:
		push_warning("PropLayer：没找到 LightingDirector（%s），家具将固定用白天贴图" % lighting_path)
	else:
		lighting.transition_changed.connect(_on_transition)
		# Sorted 在树里排在 Lighting 前面，这里的 _ready 比 Lighting 早，
		# 所以延后一帧再同步一次初始状态
		_sync_initial.call_deferred(lighting)


func _build() -> void:
	var file: FileAccess = FileAccess.open(props_path, FileAccess.READ)
	if file == null:
		push_error("PropLayer：打不开 %s" % props_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PropLayer：props.json 解析失败")
		return

	_bodies = StaticBody2D.new()
	_bodies.name = "PropBodies"
	add_child(_bodies)

	for entry: Dictionary in (parsed as Dictionary)["props"]:
		_add_prop(entry)
	queue_redraw()


func _add_prop(entry: Dictionary) -> void:
	# has_sprite = false：用户图里没有这件（建筑类，如右侧背柜/楼梯），只留碰撞不建精灵
	# no_collision = true：纯前景视觉件（如下方入口门），不要碰撞，避免挡住门洞
	var has_sprite: bool = bool(entry.get("has_sprite", true))
	var no_collision: bool = bool(entry.get("no_collision", false))
	var alpha: float = clampf(float(entry.get("alpha", 1.0)), 0.0, 1.0)

	if not has_sprite:
		if not no_collision:
			_add_collision(entry)
		return

	var rect: Rect2 = _to_rect(entry["sprite_rect"])
	var sort_y: float = float(entry["sort_y"])
	var prop_name: String = str(entry["name"])

	var by_phase: Array[Texture2D] = []
	by_phase.resize(PHASE_SUFFIX.size())
	for i in PHASE_SUFFIX.size():
		var path: String = "%s%s%s.png" % [textures_dir, prop_name, PHASE_SUFFIX[i]]
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			push_error("PropLayer：缺贴图 %s（先跑 tools/derive_prop_phases.py）" % path)
			return
		by_phase[i] = tex

	var z: int = int(entry.get("z_index", 0))
	var base: Sprite2D = _make_sprite(by_phase[LightingDirector.PHASE_DAY], rect, sort_y, prop_name, z)
	var fade: Sprite2D = _make_sprite(by_phase[LightingDirector.PHASE_DAY], rect, sort_y, prop_name + "Fade", z)
	# 半透明"虚化"：base 直接压到目标 alpha；fade 在 _on_transition 里再乘 weight
	base.modulate = Color(1.0, 1.0, 1.0, alpha)
	fade.modulate = Color(1.0, 1.0, 1.0, 0.0)

	if not no_collision:
		_add_collision(entry)
	_props.append({"by_phase": by_phase, "base": base, "fade": fade, "alpha": alpha,
			"collision": _to_rect(entry["collision_rect"]) if not no_collision else Rect2()})


func _add_collision(entry: Dictionary) -> void:
	var body_rect: Rect2 = _to_rect(entry["collision_rect"])
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = body_rect.size
	var col: CollisionShape2D = CollisionShape2D.new()
	col.shape = shape
	col.position = body_rect.position + body_rect.size * 0.5
	_bodies.add_child(col)


## 精灵摆在 (rect.x, sort_y)：draw 起点再往下推 (rect.y - sort_y)，
## 这样图片落在 rect 原位，而节点 y 是排序用的脚部线。
## z_index 可选：给负值可把该件钉到更低图层（如贴墙架 sort_y 不可靠时强制垫底）。
func _make_sprite(tex: Texture2D, rect: Rect2, sort_y: float, node_name: String, z_index: int = 0) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = node_name
	sprite.texture = tex
	sprite.centered = false
	sprite.position = Vector2(rect.position.x, sort_y)
	# offset 会被 scale 一起缩，所以先按 scale 反算：视觉落点仍是 rect 原位
	sprite.scale = Vector2(texture_scale, texture_scale)
	sprite.offset = Vector2(0.0, (rect.position.y - sort_y) / texture_scale)
	sprite.z_index = z_index
	sprite.light_mask = 1          # 不吃炉火实时光：烘焙光已经在贴图里
	add_child(sprite)
	return sprite


func _sync_initial(lighting: LightingDirector) -> void:
	_on_transition(lighting.from_phase, lighting.to_phase, lighting.last_weight)


func _on_transition(from_phase: int, to_phase: int, weight: float) -> void:
	var a: int = clampi(from_phase, 0, PHASE_SUFFIX.size() - 1)
	var b: int = clampi(to_phase, 0, PHASE_SUFFIX.size() - 1)
	for prop: Dictionary in _props:
		var phases: Array[Texture2D] = prop["by_phase"]
		var base: Sprite2D = prop["base"]
		var fade: Sprite2D = prop["fade"]
		if base.texture != phases[a]:
			base.texture = phases[a]
		if fade.texture != phases[b]:
			fade.texture = phases[b]
		# 半透明"虚化"件：fade 的 alpha 同时受阶段权重和目标 alpha 影响
		var alpha: float = prop.get("alpha", 1.0)
		fade.modulate.a = clampf(weight, 0.0, 1.0) * alpha


func _to_rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


func _draw() -> void:
	if not show_debug:
		return
	for prop: Dictionary in _props:
		var sprite: Sprite2D = prop["base"]
		var size: Vector2 = sprite.texture.get_size()
		draw_rect(Rect2(sprite.offset + Vector2(0.0, sprite.position.y), size),
				Color(0.2, 1.0, 1.0, 0.8), false, 1.0)
		draw_rect(prop["collision"], Color(1.0, 0.3, 0.3, 0.9), false, 1.0)
