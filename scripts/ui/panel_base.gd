class_name UiPanel
extends Control
## 所有全屏面板的基类：遮罩 + 居中硬边框 + 冻结玩家 + Esc 关闭。
##
## 子类只实现 _build()（摆控件）和 _on_key()（响应按键），
## 不用管铺满屏幕、不用管主题、不用管暂停玩家这些杂事。

signal closed

## 设计分辨率：所有面板内部的坐标都写在这一套数字里（16:10 的像素画布）。
## 真实渲染时 UIRoot 会整体放大 2×（1280×768），测试旁路下就是 1×（640×384）。
const DESIGN_SIZE: Vector2 = Vector2(640, 384)

## 实际采用的画布缩放（1 = 640×384，2 = 1280×768）。
var canvas_scale: float = 1.0

var _frame: Panel = null
var _open_frame: int = 0


func _ready() -> void:
	add_to_group("modal_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiStyle.theme()
	_open_frame = Engine.get_process_frames()
	_fit_canvas()
	_freeze_player(true)
	_build()
	# 打开它的那一次按键还在派发中，等一帧再收键，避免"按 E 开面板顺手又触发一次 E"。
	set_process_input(false)
	await get_tree().process_frame
	if is_inside_tree():
		set_process_input(true)


## 把自身锁成 DESIGN_SIZE 的设计画布，再按"可用区域多大"整体等比缩放。
##
## 为什么要有这一步：面板的父容器不一定是 UIRoot —— 挂到 CanvasLayer 上时
## FULL_RECT 会按 viewport（1280×768）算，面板里写死的 640 坐标就只占左上
## 四分之一、字号还是 1×，"换了分辨率就不适配"正是这么来的。
## 这里兜住：**不管谁当爹**，面板永远按 640×384 排版，再等比铺到可用区域。
## 正常情况下（父容器是 UIRoot）算出来就是 1×，行为与以前完全一致。
func _fit_canvas() -> void:
	var area: Vector2 = get_parent_area_size()
	if area.x <= 0.0 or area.y <= 0.0:
		area = size
	if area.x <= 0.0 or area.y <= 0.0:
		area = DESIGN_SIZE
	canvas_scale = minf(area.x / DESIGN_SIZE.x, area.y / DESIGN_SIZE.y)
	# 整数倍时取整：像素 UI 半像素缩放会糊（1× / 2× 是常态，取整不改变结果）
	if is_equal_approx(canvas_scale, roundf(canvas_scale)):
		canvas_scale = roundf(canvas_scale)
	if canvas_scale <= 0.0:
		canvas_scale = 1.0
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = DESIGN_SIZE
	scale = Vector2(canvas_scale, canvas_scale)
	pivot_offset = Vector2.ZERO
	# 可用区域比画布大时居中，别把面板贴在左上角留一大块空白
	position = (((area - DESIGN_SIZE * canvas_scale) * 0.5).floor()).maxf(0.0)


func close() -> void:
	if not is_inside_tree():
		return
	_freeze_player(false)
	closed.emit()
	queue_free()


func _build() -> void:
	pass


## 底部横条的通用矩形：贴画布底、左右留 margin、离底留 gap。
## 对话框（Npc 独白 / 支线多人对话）都用它 —— 尺寸只在这里算一次，
## 换设计高度时两条对话不会一个贴底一个悬空。
func bottom_bar(height: int, margin: int = 16, gap: int = 12) -> Rect2:
	return Rect2(margin, DESIGN_SIZE.y - float(height) - float(gap),
			DESIGN_SIZE.x - float(margin) * 2.0, float(height))


## 返回 true 表示这个键被用掉了（不再往下传）。
func _on_key(_keycode: int) -> bool:
	return false


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		accept_event()
		close()
		return
	if _on_key(key.keycode):
		accept_event()


func _freeze_player(frozen: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		if node.has_method("set_frozen"):
			node.set_frozen(frozen)
