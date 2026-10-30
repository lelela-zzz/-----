class_name SettingsHint
extends Control
## 左上角的设置提示条（挂在 HUD/UIRoot，存档条下面那一条）。
##
## 和 SaveHint 同一套语言：深木底 + 火光短杠 + 12px 像素字，96×18。
## 点一下等于按 F6，走 Story.open_settings_panel() 同一条入口。

const WIDTH: int = 96
const HEIGHT: int = 18
const MARGIN_LEFT: int = 8
## 存档条 (8,62) 高 18，隔 4px 排下来
const MARGIN_TOP: int = SaveHint.MARGIN_TOP + SaveHint.HEIGHT + SaveHint.ROW_GAP

var _plate: Panel = null
var _label: Label = null


func _ready() -> void:
	add_to_group("settings_hint")
	position = Vector2(MARGIN_LEFT, MARGIN_TOP)
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiStyle.theme()
	_build()


func _build() -> void:
	_plate = UiStyle.panel(
			Color(UiStyle.SHADOW.r, UiStyle.SHADOW.g, UiStyle.SHADOW.b, 0.84),
			UiStyle.BROWN)
	_plate.position = Vector2.ZERO
	_plate.size = Vector2(WIDTH, HEIGHT)
	add_child(_plate)

	var accent: ColorRect = UiStyle.rect(UiStyle.FIRE)
	accent.position = Vector2(1, 1)
	accent.size = Vector2(2, HEIGHT - 2)
	add_child(accent)

	_label = UiStyle.label("[F6] 设置", UiStyle.LINEN_DARK)
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
		if Story != null and Story.has_method("open_settings_panel"):
			Story.open_settings_panel()
