class_name QuestPanel
extends UiPanel
## 任务清单面板：按 Q 打开（或点左上角那枚笔记本图标）。
##
## 显示规则（2026-10-30 改，用户拍板：**逐步揭示**）：
##  · 一个任务 = 任务栏里的**一段**（标题 + 若干步骤）。
##  · 一次最多露**两条** —— 刚做完的那条（标题 ✓ 压暗，留着看一眼战果）
##    + 正在做的这条（◆ 火心色）。还没轮到的任务全部藏着，不糊一脸也不剧透。
##  · 正在做的这条一完成：上上条挤掉，刚做完的留在屏上当"已完成"，
##    第三条补进来 —— 如此往复，直到全部做完（那时屏上只剩最后一条）。
##    这套窗口由 QuestLog.visible() 给，别跟 pending()（追踪卡要真实未完成数）混用。
##  · 段内已完成的步骤照旧显示 ✓（看得出进度），未完成的排在后面。
##  · 每段高度按内容**实算**（旧版固定 62px，步骤一多就压到下一格、溢出框外）。
##
## 2026-10-27 改：内容区改为**可滚动**（ScrollContainer + 内层撑高）。
##  标题/分隔线固定在外框顶部，下方内容超出框高时鼠标滚轮上下滑动，永不溢出框；
##  不再用「还有 N 项」兜底行 —— 所有未完成任务都在清单里，滑下去就能看到。
##
## 追踪功能（用户要求）：每段标题右侧多一枚「追踪 / 取消追踪」按钮，点一下
## 就把这段设为"当前追踪"（全局唯一，再点别的会顶掉旧的、点自己会取消）。
## 被追踪的段：标题加 ★、染金色、整段垫一层浅色高亮，一眼认得出来。
## 数据写在 QuestLog（set_tracked / tracked_id / is_tracked / tracked_changed），
## 后续任务指引（地图黄色感叹号）会读 QuestLog.tracked_quest() + 任务的 dest。
##
## 这一层只读：不提供"放弃任务"之类的操作 —— 序章任务没有可放弃的，
## 等任务复杂到需要管理时再补。

const FRAME: Rect2 = Rect2(88, 48, 464, 288)
const HEADER_H: int = 42          # 标题(8) + 分隔线(40) 之下，内容区起点（外框局部坐标）
const INNER_TOP: int = 4          # 内层内容距滚动区顶的留白
const HEAD_WITH_DESC: int = 30    # 有描述时，步骤区相对段顶的偏移
const HEAD_NO_DESC: int = 16      # 没描述时
const STEP_H: int = 14
const BLOCK_PAD: int = 6          # 段底留白
const BLOCK_GAP: int = 6          # 段与段之间
const BOTTOM_PAD: int = 12        # 内容区底部留白
const TEXT_W: int = 412           # 正文可用宽度，超出即截断加 …
const TRACK_BTN_W: int = 60       # 每段「追踪 / 取消追踪」按钮宽

var _scroll: ScrollContainer = null
var _inner: Control = null


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	var title: Label = UiStyle.label("任务清单", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(14, 8)
	_frame.add_child(title)

	UiStyle.divider(_frame, 8, 40, int(FRAME.size.x) - 16)

	# 可滚动内容区：标题/分隔线之下、内框之内，超出框高即滚轮上下滑。
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(0, HEADER_H)
	_scroll.size = Vector2(FRAME.size.x - 4, (FRAME.size.y - 4) - HEADER_H)
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_theme_stylebox_override("panel", UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	_frame.add_child(_scroll)
	call_deferred("_style_scrollbar")   # 滚动条节点在 _scroll 进树后才创建

	_inner = Control.new()
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.size = Vector2(_scroll.size.x, 0)
	_scroll.add_child(_inner)

	_fill()
	# 面板开着时进度也可能变（买东西、酿造完成…）——跟着重画，
	# 做完的那段当场消失，剩下的自动顶上来。
	QuestLog.changed.connect(_on_log_changed)
	# 追踪状态切换也要跟着重画（按钮文案 / 高亮都要变）。
	QuestLog.tracked_changed.connect(_on_log_changed)


## 把竖向滚动条染成火光/皮革色，跟面板一套语言（默认灰条在皮革底上太跳）。
## 直接在滚动条节点上盖样式盒最稳 —— 给 ScrollContainer 设 theme 的方式滚条节点不一定吃得到。
func _style_scrollbar() -> void:
	if _scroll == null:
		return
	var bar: ScrollBar = _scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.add_theme_stylebox_override("scrollbar", UiStyle.box(UiStyle.SHADOW, UiStyle.BROWN))
	bar.add_theme_stylebox_override("grabber", UiStyle.box(UiStyle.FIRE, UiStyle.INK))
	bar.add_theme_stylebox_override("grabber_highlight", UiStyle.box(UiStyle.FIRE_CORE, UiStyle.INK))


## 数据变了就整块重画（任务量是几十条的量级，重建比逐条 diff 便宜也好写）。
## 重画前记一下滚动位置、画完还原 —— 否则点一下"追踪"就跳回顶部，
## 列表一长很恼人。追踪只改标题前缀/按钮文案，段高不变，还原是精确的。
func _on_log_changed() -> void:
	if _inner == null or not is_inside_tree():
		return
	var pos: int = 0
	if _scroll != null:
		pos = _scroll.scroll_vertical
	_clear_content()
	_fill()
	if _scroll != null:
		_scroll.scroll_vertical = pos


func _clear_content() -> void:
	for c: Node in _inner.get_children():
		_inner.remove_child(c)
		c.queue_free()


func _fill() -> void:
	# 逐步揭示的窗口：最多两条 —— 刚做完的那条 + 正在做的这条。
	# 没轮到的任务全部藏着（QuestLog.visible()），不是把所有未完成的都摊出来。
	var quests: Array[Dictionary] = QuestLog.visible()
	if quests.is_empty():
		var text: String = "暂时没有任务。" if QuestLog.all().is_empty() else "所有任务都完成了。"
		var empty: Label = UiStyle.label(text, UiStyle.LINEN_DARK)
		empty.position = Vector2(14, INNER_TOP)
		_inner.add_child(empty)
		_inner.custom_minimum_size = Vector2(_scroll.size.x, INNER_TOP + 20)
		_inner.size = Vector2(_scroll.size.x, INNER_TOP + 20)
		return

	# 全部未完成任务都画进内层；内层高度 = 内容总高，超出滚动区即滚。
	var y: int = INNER_TOP

	for q: Dictionary in quests:
		var h: int = _block_height(q)
		if y > INNER_TOP:
			UiStyle.divider(_inner, 12, y - 4, int(_scroll.size.x) - 40)
		_draw_block(q, y)
		y += h + BLOCK_GAP

	# ScrollContainer 用子节点的 custom_minimum_size 决定滚动范围（不是 size），
	# 所以这里必须设 custom_minimum_size，否则布局一跑内层被压成 0、滚不动。
	var total_h: int = y + BOTTOM_PAD
	_inner.custom_minimum_size = Vector2(_scroll.size.x, total_h)
	_inner.size = Vector2(_scroll.size.x, total_h)
	_style_scrollbar()


## 一段 = 标题（+ 描述）+ 若干步骤，高度按内容实算。
func _block_height(q: Dictionary) -> int:
	var steps: Array = q.get("steps", [])
	var head: int = HEAD_WITH_DESC if str(q.get("desc", "")) != "" else HEAD_NO_DESC
	return head + steps.size() * STEP_H + BLOCK_PAD


func _draw_block(q: Dictionary, y: int) -> void:
	var steps: Array = q.get("steps", [])
	var desc: String = str(q.get("desc", ""))
	var head: int = HEAD_WITH_DESC if desc != "" else HEAD_NO_DESC
	var qid: String = str(q["id"])
	var tracked: bool = QuestLog.is_tracked(qid)
	# 留在窗口里的上一条是"刚做完的战果"，标题换成 ✓ 并压暗，和正在做的那条区分开。
	var finished: bool = QuestLog.is_finished(q)

	# 被追踪的段：整段垫一层浅色高亮，配合金色 ★ 标题，一眼认得出。
	if tracked:
		var h: int = _block_height(q)
		var hl: ColorRect = UiStyle.rect(
				Color(UiStyle.FIRE_CORE.r, UiStyle.FIRE_CORE.g, UiStyle.FIRE_CORE.b, 0.12))
		hl.position = Vector2(6, y - 3)
		hl.size = Vector2(_scroll.size.x - 12, h + 4)
		_inner.add_child(hl)

	# 标题：追踪段 ★ 金色 > 已完成的 ✓ 暗色 > 正在做的 ◆ 火心色；右侧给按钮留出宽度。
	var prefix: String = "★ " if tracked else ("✓ " if finished else "◆ ")
	var title_color: Color = UiStyle.GOLD if tracked \
			else (UiStyle.LINEN_DARK if finished else UiStyle.FIRE_CORE)
	var title: Label = UiStyle.label(
			_clip(prefix + str(q["title"]), TEXT_W - TRACK_BTN_W - 18), title_color)
	title.position = Vector2(12, y)
	_inner.add_child(title)

	# 每段一枚「追踪 / 取消追踪」按钮，点一下切换（QuestLog.set_tracked 自带顶替/取消）。
	var btn: Button = _track_button(tracked)
	btn.position = Vector2(_scroll.size.x - TRACK_BTN_W - 4, y - 1)
	btn.pressed.connect(_on_track_pressed.bind(qid))
	_inner.add_child(btn)

	if desc != "":
		var dl: Label = UiStyle.label(_clip(desc), UiStyle.LINEN_DARK)
		dl.position = Vector2(28, y + 15)
		_inner.add_child(dl)

	for k: int in steps.size():
		var s: Dictionary = steps[k] as Dictionary
		var row: Label = UiStyle.label(_clip(QuestTracker._step_text(s)),
				UiStyle.LINEN_DARK if bool(s["done"]) else UiStyle.LINEN)
		row.position = Vector2(28, y + head + k * STEP_H)
		_inner.add_child(row)


## 追段按钮：扁平、硬边、像素字，和面板一套语言。追踪中=深色底金边、字转火心；
## 未追踪=皮革底、亚麻字。点一下由 _on_track_pressed 调 QuestLog.set_tracked。
func _track_button(tracked: bool) -> Button:
	var btn: Button = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2i(TRACK_BTN_W, 18)
	btn.size = Vector2i(TRACK_BTN_W, 18)
	btn.text = "取消追踪" if tracked else "追踪"
	btn.add_theme_font_override("font", UiStyle.theme().default_font)
	btn.add_theme_font_size_override("font_size", UiStyle.BODY_SIZE)
	btn.add_theme_color_override("font_color",
			UiStyle.FIRE_CORE if tracked else UiStyle.LINEN)
	for st: String in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st,
				UiStyle.box(
						UiStyle.SHADOW if tracked else UiStyle.BROWN,
						UiStyle.FIRE_CORE if tracked else UiStyle.LEATHER_LIGHT))
	btn.add_theme_stylebox_override("disabled",
			UiStyle.box(UiStyle.SHADOW, UiStyle.METAL_DARK))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


## 点「追踪 / 取消追踪」：交给 QuestLog，自带顶替旧追踪 / 再点自己取消。
func _on_track_pressed(id: String) -> void:
	QuestLog.set_tracked(id)


## 超宽就截断加省略号 —— 像素 UI 不换行，戳出框外比截断难看。
static func _clip(text: String, max_w: int = TEXT_W) -> String:
	var font: Font = UiStyle.theme().default_font
	if font == null or not font.has_method("get_string_size"):
		return text
	if font.get_string_size(text, UiStyle.BODY_SIZE).x <= float(max_w):
		return text
	for i: int in range(text.length() - 1, 0, -1):
		var cut: String = text.substr(0, i) + "…"
		if font.get_string_size(cut, UiStyle.BODY_SIZE).x <= float(max_w):
			return cut
	return "…"


func _on_key(_keycode: int) -> bool:
	# Q 再按一次也视为关闭，和 Esc 一样
	if _keycode == KEY_Q:
		close()
		return true
	return false
