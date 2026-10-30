class_name SaveHint
extends Control
## 左上角的存档提示条（挂在 HUD/UIRoot，任务书下面那一条）。
##
## 为什么做成常驻小条而不是只写进操作说明：存档是"随时想按就按"的动作，
## 玩家不会记得键位。这块和任务书（QuestTracker）用同一套语言 ——
## 深木底 + 皮革包边 + 12px 像素字，只占 138×22，不挡地面。
##
## 三种状态都给反馈：
##   · 平时：暗亚麻「[F5] 存档」
##   · 悬停：字变火心色 + 包边亮起（可点）
##   · 刚存过：整条闪一下火光（Story.toast 之外的第二重确认）

const WIDTH: int = 96
const HEIGHT: int = 18
const MARGIN_LEFT: int = 8
const MARGIN_TOP: int = 62     # 任务书 8..58，往下让 4px
## 设置条排在本条下面（SettingsHint 复用这两个值算自己的 y）
const ROW_GAP: int = 4

var _plate: Panel = null
var _accent: ColorRect = null
var _label: Label = null


func _ready() -> void:
	add_to_group("save_hint")
	position = Vector2(MARGIN_LEFT, MARGIN_TOP)
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 顶层 HUD 在 CanvasLayer 下没有主题，像素字要显式挂字体（见 UiStyle.label）
	theme = UiStyle.theme()
	_build()
	# 存完一档，条子自己亮一下 —— 玩家不用去看有没有弹字
	SaveGame.saved.connect(_on_saved)


func _build() -> void:
	_plate = UiStyle.panel(
			Color(UiStyle.SHADOW.r, UiStyle.SHADOW.g, UiStyle.SHADOW.b, 0.84),
			UiStyle.BROWN)
	_plate.position = Vector2.ZERO
	_plate.size = Vector2(WIDTH, HEIGHT)
	add_child(_plate)

	# 左侧一小段火光色短杠：和菜单/面板的"选中竖条"是同一个记号
	_accent = UiStyle.rect(UiStyle.FIRE)
	_accent.position = Vector2(1, 1)
	_accent.size = Vector2(2, HEIGHT - 2)
	add_child(_accent)

	_label = UiStyle.label("[F5] 存档", UiStyle.LINEN_DARK)
	_label.position = Vector2(9, 3)
	_label.size = Vector2(WIDTH - 11, 12)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(on: bool) -> void:
	if _label == null:
		return
	_label.add_theme_color_override("font_color",
			UiStyle.FIRE_CORE if on else UiStyle.LINEN_DARK)
	_plate.add_theme_stylebox_override("panel",
			UiStyle.box(Color(UiStyle.SHADOW.r, UiStyle.SHADOW.g, UiStyle.SHADOW.b, 0.92),
					UiStyle.FIRE if on else UiStyle.BROWN))


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		# 点一下等于按 F5：走同一条入口，别在这里另开一份面板
		if Story != null and Story.has_method("open_save_panel"):
			Story.open_save_panel()


## 存过档：整条闪一下（0.9→0.35 淡回来），提示"刚才那下成了"
func _on_saved(_slot: int) -> void:
	if _label == null:
		return
	_label.add_theme_color_override("font_color", UiStyle.FIRE_CORE)
	var tw: Tween = create_tween()
	tw.tween_interval(0.9)
	tw.tween_method(_fade_label, 1.0, 0.0, 0.5)


func _fade_label(t: float) -> void:
	var base: Color = UiStyle.LINEN_DARK
	var hot: Color = UiStyle.FIRE_CORE
	_label.add_theme_color_override("font_color", hot.lerp(base, t))
