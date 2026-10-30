class_name ClockHUD
extends Control
## 右上角的钟：带刻度的空盘面（assets/props/clock_clean_32.png）+ 运行时绘制的**时针**。
##
## 只做小时粒度：钟面只有一根时针（随分钟连续走位，读起来不跳），
## 下方数字也只显示小时（08），不显示分钟。
## 不用 clock_hands_32 / clock_hour_32：那两张的指针是烘死在图里的固定时刻，
## 没法走字；clock_no_hands_32 又没画刻度（只有边框），所以取 clock_clean_32 的盘面，指针在 _draw 里画。
##
## 坐标约定：控件局部 0~64 就是钟面，盘面按 2 倍最近邻铺满（32px 素材 → 64px），
## 指针尖端 round 到整像素，慢速走时不会出现亚像素抖动。

## 钟面边长（局部坐标，= 素材 32px 的 2 倍）。
const FACE_SIZE: float = 64.0
const FACE_TEXTURE: Texture2D = preload("res://assets/props/clock_clean_32.png")
const HAND_COLOR: Color = Color(0.16, 0.11, 0.08, 1.0)
const HOUR_HAND_LEN: float = 20.0
const HAND_WIDTH: float = 2.0

## 时间源路径（兜底用）。ClockPanel 位于 `HUD/UIRoot/ClockPanel`、Clock 在场景根，
## 故相对路径需上三级 `../../../Clock`；但优先走 `game_clock` 组认领（与 BrewingService
## 等系统同一套机制，换场景自动认新时钟），路径只在不依赖组时兜底。
@export var clock_path: NodePath = ^"../../../Clock"
## 钟面下方是否显示小时数字（32px 指针盘在小尺寸下不好读，默认开）。
@export var show_digits: bool = true

@onready var _digits: Label = $Digits

var _hour: int = 0
var _minute: int = 0


func _ready() -> void:
	_scale_hud_layer()
	_digits.visible = show_digits
	var clock: GameClock = _find_clock()
	if clock == null:
		# 极少数场景节点顺序导致 _ready 早于 Clock 进组：等一帧再认领
		await get_tree().process_frame
		clock = _find_clock()
	if clock == null:
		push_error("ClockHUD：找不到 GameClock（clock_path = %s）" % clock_path)
		return
	clock.time_changed.connect(_on_time_changed)
	_on_time_changed(clock.hour, clock.minute)


## 优先从 `game_clock` 组认领当前时钟（设计上的标准机制，跨场景自动跟随），
## 找不到再用 clock_path 兜底。
func _find_clock() -> GameClock:
	var g: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if g != null:
		return g
	return get_node_or_null(clock_path) as GameClock


## HUD 不受相机 zoom 影响，A 路线（viewport 2×）下要手动放大才铺满整屏。
## 缩的是 HUD 下的 UIRoot 容器（640×384 那套坐标），不能直接缩 CanvasLayer ——
## Control 的 anchor 按 viewport(1280) 算，再乘 scale 会把控件推出屏幕。
## 按 viewport 实际尺寸换算：viewport 降回 640×384（测试）时倍数自然是 1。
func _scale_hud_layer() -> void:
	var ui: Control = get_parent() as Control
	if ui == null:
		return
	ui.scale = WindowScale.render_scale()


func _on_time_changed(hour: int, minute: int) -> void:
	_hour = hour
	_minute = minute
	_digits.text = "%02d" % hour
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(FACE_TEXTURE, Rect2(0.0, 0.0, FACE_SIZE, FACE_SIZE), false)

	var center: Vector2 = Vector2(FACE_SIZE, FACE_SIZE) * 0.5
	# 12 点方向为 0°，屏幕上顺时针为正 → 减 90° 让 0° 指向上方；
	# 带上分钟做连续走位（8:30 指向 8 与 9 之间）
	var hour_angle: float = deg_to_rad((float(_hour % 12) + float(_minute) / 60.0) * 30.0 - 90.0)
	draw_line(center, _hand_tip(center, hour_angle, HOUR_HAND_LEN), HAND_COLOR, HAND_WIDTH, false)
	draw_rect(Rect2(center.x - 1.0, center.y - 1.0, 2.0, 2.0), HAND_COLOR)


func _hand_tip(center: Vector2, angle: float, length: float) -> Vector2:
	return (center + Vector2(cos(angle), sin(angle)) * length).round()
