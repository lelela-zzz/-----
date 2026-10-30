extends Control
class_name TravelOverlay
## 「跑路中」遮罩 —— M 地图快速前往的过场：中央一行字 + 下面一个转动的钟。
##
## 用户 2026-10-28 的要求：传送时要看得见"花了时间"，时钟从当前时刻转到
## 消耗时间后的对应时刻。所以这不是纯装饰 —— 动画结束时**真的**推进游戏时钟
## （`GameClock.advance`），并把时间随场景切换带过去。
##
## 为什么钟自己画、不复用 ClockHUD：
##  · ClockHUD 只有时针（只到小时），这里要分钟级连续转；
##  · ClockHUD 认的是 current_scene 里的 Clock，而这块遮罩要在切场景之前独立播完。
## 盘面仍用同一张 `clock_clean_32.png`，角度公式也与 ClockHUD 一致（12 点为 0°）。
##
## 为什么"切场景"也写在这里：发起它的 MapPanel 已经 `close()`（queue_free），
## 回调绑在面板上会变成 freed instance。遮罩自己的寿命盖住整段跑路，所以由它收尾。

const SWEEP_SEC: float = 1.15          # 指针转完用的真实时长
const TITLE_Y: float = 144.0           # 「跑路中」的 y（640×384 设计画布）
const FACE_CENTER: Vector2 = Vector2(320.0, 214.0)
const FACE_SIZE: float = 64.0
const DIM_ALPHA: float = 0.62


## 只画钟面和两根针的小控件（放在遮罩里，压在暗底之上、字之下）。
class ClockFace extends Control:
	const FACE_TEXTURE: Texture2D = preload("res://assets/props/clock_clean_32.png")
	const FACE: float = 64.0
	const HAND: Color = Color(0.16, 0.11, 0.08, 1.0)

	var start_min: int = 0      # 出发时刻（当天第几分钟）
	var minutes: int = 0        # 要消耗多久
	var sweep: float = 0.0:     # 0→1，由 Tween 推进
		set(v):
			sweep = v
			queue_redraw()

	func _draw() -> void:
		draw_texture_rect(FACE_TEXTURE, Rect2(Vector2.ZERO, Vector2(FACE, FACE)), false)
		var c: Vector2 = Vector2(FACE, FACE) * 0.5
		# 用**连续角度**而不是"现在几点"再取模：小时针 0.5°/分、分针 6°/分，
		# 从出发时刻一路加过去，跨零点也不会突然倒转一圈。
		var cur: float = float(start_min) + float(minutes) * sweep
		var h_ang: float = deg_to_rad(cur * 0.5 - 90.0)
		var m_ang: float = deg_to_rad(cur * 6.0 - 90.0)
		draw_line(c, _tip(c, m_ang, 26.0), HAND, 1.0, false)
		draw_line(c, _tip(c, h_ang, 17.0), HAND, 2.5, false)
		draw_rect(Rect2(c.x - 1.0, c.y - 1.0, 2.0, 2.0), HAND)

	func _tip(c: Vector2, ang: float, length: float) -> Vector2:
		return (c + Vector2(cos(ang), sin(ang)) * length).round()


var _face: ClockFace = null
var _clock_ref: GameClock = null
var _minutes: int = 0
var _path: String = ""
var _spawn: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# ⚠️ 必须用 set_anchors_and_offsets_preset：set_anchors_preset 默认
	# keep_offsets=true，只改锚点不动偏移，新控件尺寸仍是 0×0 → 暗底铺不开。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 跑路期间别让别的面板弹出来（也顺手让罗盘箭头闭嘴）
	add_to_group("modal_ui")

	var dim: ColorRect = UiStyle.rect(
			Color(UiStyle.INK.r, UiStyle.INK.g, UiStyle.INK.b, DIM_ALPHA))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_face = ClockFace.new()
	_face.position = FACE_CENTER - Vector2(FACE_SIZE, FACE_SIZE) * 0.5
	_face.size = Vector2(FACE_SIZE, FACE_SIZE)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	var title: Label = UiStyle.label("跑路中", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, TITLE_Y)
	title.size = Vector2(640, 32)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)


## 开始跑路。播完后推进时钟并切场景（target_path 为空 = 只走时间，测试用）。
func begin(clock: GameClock, start_hour: int, start_minute: int, minutes: int,
		target_path: String, spawn: Vector2) -> void:
	_clock_ref = clock
	_minutes = maxi(0, minutes)
	_path = target_path
	_spawn = spawn
	if _face != null:
		_face.start_min = start_hour * 60 + start_minute
		_face.minutes = _minutes
		_face.sweep = 0.0
	# 跑路这段时间不该被游戏时钟自己的 _process 偷偷加上几分钟
	if _clock_ref != null and is_instance_valid(_clock_ref):
		_clock_ref.running = false
	_freeze(true)
	var tw: Tween = create_tween()
	tw.tween_property(_face, "sweep", 1.0, SWEEP_SEC) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_finish)


func _finish() -> void:
	_apply()
	_freeze(false)
	if is_inside_tree():
		queue_free()


## 推进时间 → 记下出发时刻与落点 → 切场景（和走门共用 DoorArea 的静态通道）。
func _apply() -> void:
	if _clock_ref != null and is_instance_valid(_clock_ref):
		# 1 游戏分钟 = seconds_per_hour/60 现实秒
		_clock_ref.advance(float(_minutes) * _clock_ref.seconds_per_hour / 60.0)
		DoorArea.pending_hour = _clock_ref.hour
		DoorArea.pending_minute = _clock_ref.minute
		_clock_ref.running = true
	DoorArea.pending_position = _spawn
	DoorArea.has_pending = true
	DoorArea.pending_target = _path
	if not _path.is_empty():
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.change_scene_to_file.call_deferred(_path)


func _freeze(frozen: bool) -> void:
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n.has_method("set_frozen"):
			n.set_frozen(frozen)
