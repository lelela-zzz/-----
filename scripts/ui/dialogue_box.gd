extends UiPanel
## 对话框：屏幕下方一条，头像 + 名字 + 一句一行。
##
## 复用 UiPanel 的三件事：铺满屏幕的输入遮蔽、Esc 关闭、冻结玩家
## （对话时不冻结，玩家能一边走一边"聊"，这显然不对）。
##
## 逐字显示不用 Timer：UiPanel 已经是每帧可用的 Control，用累加器更准 ——
## 也不受 Engine.time_scale 的影响。

## 逐字速度（字/秒）。中文一屏 20 来字，45 已经偏快，但读起来顺。
const CHARS_PER_SECOND: float = 45.0

## 由 Npc 在 add_child 之前写入。
var speaker: String = ""
var role: String = ""
var lines: PackedStringArray = []
var portrait: Texture2D = null

var _name_label: Label = null
var _role_label: Label = null
var _text_label: Label = null
var _portrait_rect: TextureRect = null
var _index: int = 0
var _revealed: float = 0.0
var _full_len: int = 0


func _build() -> void:
	# 贴画布底的一条，宽度 = 画布宽 − 左右各 16。位置由 UiPanel.bottom_bar 统一算，
	# 面板整体再由 UiPanel._fit_canvas 按屏幕等比放大 —— 换分辨率不用改这里。
	var bar: Rect2 = bottom_bar(108)
	var frame: Panel = UiStyle.panel(UiStyle.SHADOW, UiStyle.BROWN)
	frame.position = bar.position
	frame.size = bar.size
	add_child(frame)

	# 头像底板：30x60 = 60x120 的一半，整除缩放，Nearest 采样不糊
	var slot: Panel = UiStyle.panel(UiStyle.BROWN, UiStyle.BROWN)
	slot.position = Vector2(8, 10)
	slot.size = Vector2(36, 66)
	frame.add_child(slot)

	if portrait != null:
		_portrait_rect = UiStyle.icon(portrait, Vector2i(30, 60))
		_portrait_rect.position = Vector2(3, 3)
		slot.add_child(_portrait_rect)

	_name_label = UiStyle.label(speaker, UiStyle.FIRE_CORE, UiStyle.BODY_SIZE)
	_name_label.position = Vector2(60, 8)
	frame.add_child(_name_label)

	_role_label = UiStyle.label(role, UiStyle.LINEN_DARK, UiStyle.BODY_SIZE)
	_role_label.position = Vector2(60 + _text_width(speaker) + 10, 8)
	frame.add_child(_role_label)

	UiStyle.divider(frame, 60, 26, 540)

	_text_label = UiStyle.label("", UiStyle.LINEN, UiStyle.BODY_SIZE)
	_text_label.position = Vector2(60, 34)
	_text_label.size = Vector2(538, 62)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame.add_child(_text_label)

	_show_line(0)


func _text_width(s: String) -> int:
	var f: Font = UiStyle.theme().default_font
	return int(f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.BODY_SIZE).x)


func _process(delta: float) -> void:
	if _text_label == null or _full_len <= 0:
		return
	if _text_label.visible_characters >= _full_len and _text_label.visible_characters != -1:
		return
	_revealed = minf(_revealed + delta * CHARS_PER_SECOND, float(_full_len))
	_text_label.visible_characters = int(_revealed)


func _show_line(i: int) -> void:
	if _text_label == null:
		return
	var text: String = lines[i] if i < lines.size() else ""
	_text_label.text = text
	_full_len = text.length()
	_revealed = 0.0
	_text_label.visible_characters = 0


func _fully_revealed() -> bool:
	return _text_label == null or _text_label.visible_characters == -1 \
			or _text_label.visible_characters >= _full_len


func _on_key(keycode: int) -> bool:
	if keycode != KEY_E and keycode != KEY_SPACE and keycode != KEY_ENTER \
			and keycode != KEY_KP_ENTER:
		return false
	if not _fully_revealed():
		# 第一下先把这句显示完，第二下才翻页 —— 手快的人不会漏字
		_revealed = float(_full_len)
		_text_label.visible_characters = -1
		return true
	_index += 1
	if _index >= lines.size():
		close()
		return true
	_show_line(_index)
	return true
