extends Control
class_name SleepOverlay
## 「睡觉中」过场 —— 宵禁跨天（23:00 → 次日 07:30）之间那一下。
##
## 布局（640×384 设计画布，与 TravelOverlay 同一套坐标）：最上面「睡觉中」+ 点动画，
## 床在字下面，钟在右上角转。参考的是「跑路中」遮罩 —— 同样一层暗底、同样自绘钟面，
## 只是把"钟在中间"换成"床在中间、钟挪到右上角"。
##
## 为什么钟是「盘面不动、指针飞转」而不是整块钟表旋转：
##   像素画整体旋转在 Nearest 采样下会糊成锯齿（64×64 转 45° 尤其明显），
##   而细指针转动的劣化几乎看不出来 —— 观感上仍然是"钟表在转"，而且是"时间在走"。
##
## 这个类只管播，不管时间：播完发 finished，由 GameClock 去把日子推到新的一天。

## 播完（淡出结束）时发出。GameClock 收到后才真正跳时间。
signal finished

const DIM_ALPHA: float = 0.89          # 夜里睡觉，压得比「跑路中」更暗
const FADE_IN_SEC: float = 0.28
const HOLD_SEC: float = 2.00
const FADE_OUT_SEC: float = 0.32
## 指针在这段停留里转几圈 —— 转得多才像"睡了一夜"。
const SWEEPS: float = 2.0

const TITLE_TOP: float = 48.0
const TITLE_TEXT: String = "睡觉中"
## 设计画布宽度（640×384）。钟的右边距按它算，别依赖 _ready 时还没铺开的 size。
const CANVAS_WIDTH: float = 640.0
const TITLE_CENTER_X: float = 320.0
const DOT_STEP_SEC: float = 0.34       # 省略号每 0.34 秒加一个点，加到三个回头
const BED_TOP: float = 104.0
const CLOCK_MARGIN: Vector2 = Vector2(20.0, 20.0)

const BED_TEXTURE: Texture2D = preload("res://assets/ui/sleep_bed.png")

## headless（无窗口）下默认不播过场。
##
## 38 套回归里有一批「调 _roll_over_curfew 之后同帧断言 day+1」的同步用例
## （verify_day_cycle 就是），插一段 2.6 秒动画会把它们全打红。专项验收临时把它
## 置 true，就能验到"时钟确实会把过场拉起来"这条链路。
static var allow_in_headless: bool = false


## 盘面 + 指针。盘面用现成的 64×64 钟面，指针自绘 —— 只有自绘才能让指针转出多圈。
class ClockFace extends Control:
	const FACE_TEXTURE: Texture2D = preload("res://assets/props/clock_clean_32_2x.png")
	const FACE: float = 64.0
	const HAND: Color = Color(0.16, 0.11, 0.08, 1.0)

	## 已转的圈数（0 → SWEEPS），由 Tween 推进。
	var sweep: float = 0.0:
		set(value):
			sweep = value
			queue_redraw()

	func _draw() -> void:
		draw_texture_rect(FACE_TEXTURE, Rect2(Vector2.ZERO, Vector2(FACE, FACE)), false)
		var c: Vector2 = Vector2(FACE, FACE) * 0.5
		# 分针一圈 = 1 小时，时针一圈 = 12 小时，所以时针角 = 分针角 / 12。
		var m_ang: float = sweep * TAU - PI * 0.5
		var h_ang: float = sweep * TAU / 12.0 - PI * 0.5
		draw_line(c, _tip(c, m_ang, 22.0), HAND, 1.0, false)
		draw_line(c, _tip(c, h_ang, 14.0), HAND, 2.5, false)
		draw_rect(Rect2(c.x - 1.0, c.y - 1.0, 2.0, 2.0), HAND)

	func _tip(c: Vector2, ang: float, length: float) -> Vector2:
		return (c + Vector2(cos(ang), sin(ang)) * length).round()


var _face: ClockFace = null
var _dots: Label = null
var _dot_accum: float = 0.0
var _dot_count: int = 0
var _playing: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 与 TravelOverlay 同一个坑：set_anchors_preset 默认 keep_offsets=true，
	# 只改锚点不动偏移，尺寸还是 0×0 → 暗底铺不开。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 睡觉期间别让别的面板弹出来
	add_to_group("modal_ui")

	var dim: ColorRect = UiStyle.rect(
			Color(UiStyle.INK.r, UiStyle.INK.g, UiStyle.INK.b, DIM_ALPHA))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# 「睡觉中」整体居中，但字本身钉住不动 —— 省略号往右长，字才不会左右跳。
	var title_w: int = UiStyle.text_width(TITLE_TEXT, UiStyle.TITLE_SIZE)
	var dot_w: int = UiStyle.text_width("...", UiStyle.TITLE_SIZE)
	var left: float = TITLE_CENTER_X - float(title_w + dot_w) * 0.5
	var title: Label = UiStyle.outlined_label(TITLE_TEXT, UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(left, TITLE_TOP)
	title.size = Vector2(title_w, 32)
	add_child(title)

	_dots = UiStyle.outlined_label("", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	_dots.position = Vector2(left + title_w, TITLE_TOP)
	_dots.size = Vector2(dot_w, 32)
	add_child(_dots)

	var bed: TextureRect = UiStyle.icon(BED_TEXTURE, Vector2i(BED_TEXTURE.get_width(),
			BED_TEXTURE.get_height()))
	bed.position = Vector2(roundf(TITLE_CENTER_X - bed.size.x * 0.5), BED_TOP)
	add_child(bed)

	_face = ClockFace.new()
	_face.size = Vector2(ClockFace.FACE, ClockFace.FACE)
	# 用设计画布常量而不是 size.x：_ready 这一刻 anchors 铺开的尺寸还没算出来。
	_face.position = Vector2(CANVAS_WIDTH - ClockFace.FACE - CLOCK_MARGIN.x, CLOCK_MARGIN.y)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)


func _process(delta: float) -> void:
	if not _playing:
		return
	_dot_accum += delta
	if _dot_accum >= DOT_STEP_SEC:
		_dot_accum = 0.0
		_dot_count = (_dot_count + 1) % 4      # 0,1,2,3 → 再回到 0
		if _dots != null:
			_dots.text = ".".repeat(_dot_count)


## 开始播。调用方负责先 add_child —— 不在树里 create_tween 会报错。
func play() -> void:
	if _playing:
		return
	_playing = true
	_freeze(true)
	modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_IN_SEC)
	# 钟与暗底同时起步：指针在淡入这 0.28 秒里已经开始走了
	var spin: Tween = create_tween()
	if _face != null:
		spin.tween_property(_face, "sweep", SWEEPS, FADE_IN_SEC + HOLD_SEC) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(HOLD_SEC)
	tw.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC)
	tw.tween_callback(_on_done)


func _on_done() -> void:
	_playing = false
	_freeze(false)
	finished.emit()
	if is_inside_tree():
		queue_free()


## 播过场时把玩家钉住（和「跑路中」一致）。
func _freeze(frozen: bool) -> void:
	if not is_inside_tree():
		return
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n.has_method("set_frozen"):
			n.set_frozen(frozen)


## 当前有没有条件播（给 GameClock 判断用）。
static func can_play() -> bool:
	if DisplayServer.get_name() == "headless" and not allow_in_headless:
		return false
	return true


## 指针当前转了几圈（验收用）。
func sweep_amount() -> float:
	return _face.sweep if _face != null else 0.0


## 省略号当前点数（验收用）。
func dot_count() -> int:
	return _dot_count
