class_name PrologueCard
extends UiPanel
## 序言卡：进入游戏时的开场卷轴，黑底白字一页页翻。
##
## 剧情文本来自 data/story_prologue.json 的 intro 数组，一页一条。
## 整块黑底 + 居中排版，跟游戏里的木框面板刻意区分开 —— 这是"讲故事"，
## 不是"操作界面"。翻到最后自动关闭，Story 收到 closed 后接萃歌的开场对话。

var pages: PackedStringArray = []
var book_title: String = "序言"

var _cover: ColorRect = null
var _body: Label = null
var _page_label: Label = null
var _index: int = 0


func _build() -> void:
	_cover = UiStyle.rect(Color(0.055, 0.05, 0.047, 0.97))
	_cover.size = Vector2(640, 384)
	add_child(_cover)

	var head: Label = UiStyle.label(book_title, UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	head.position = Vector2(0, 46)
	head.size = Vector2(640, 30)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(head)

	var rule: ColorRect = UiStyle.rect(UiStyle.BROWN)
	rule.position = Vector2(250, 84)
	rule.size = Vector2(140, 1)
	add_child(rule)

	_body = UiStyle.label("", UiStyle.LINEN)
	_body.position = Vector2(96, 118)
	_body.size = Vector2(448, 190)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_body)

	_page_label = UiStyle.label("", UiStyle.LINEN_DARK)
	_page_label.position = Vector2(0, 330)
	_page_label.size = Vector2(640, 16)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_page_label)

	_show(0)


func _show(i: int) -> void:
	_index = clampi(i, 0, pages.size() - 1)
	if _body == null or pages.is_empty():
		return
	_body.text = pages[_index]
	_page_label.text = "%d / %d    [E] 继续" % [_index + 1, pages.size()]


func _on_key(keycode: int) -> bool:
	if keycode != KEY_E and keycode != KEY_SPACE and keycode != KEY_ENTER \
			and keycode != KEY_KP_ENTER:
		return false
	if _index + 1 >= pages.size():
		close()
		return true
	_show(_index + 1)
	return true
