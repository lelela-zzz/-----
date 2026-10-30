class_name BrewingPanel
extends UiPanel
## 酿造面板：左边三个锅位，右边配方列表。
##
## 交互刻意做成"键盘优先、零鼠标"：W/S 选配方，E 开酿，R 收酒，Esc 走人。
##
## 面板不持有任何游戏状态 —— 槽位和时间都在 BrewingService，材料在 Inventory，
## 配方在 ItemDB。这一层只负责把它们的现状画出来，并把按键翻译成调用。
##
## ── 为"以后还要加酒、加料"留的三处口子 ─────────────────────────────
## 1. **配方条数不设上限**：右边固定 5 个行控件（这是屏幕能放下的高度），
##    通过 ListWindow 决定"第 r 行该显示第几条"。加到 12 条配方也只是多滚两下。
## 2. **每味料的料数不设上限**：一行里 1..MAX_ING 味料由 ingredient_columns()
##    按剩余宽度自动排布，放不下就依次降级成「焦麦×2」→「×2」→ 只留图标。
##    所以加一条四味料、五味料的配方不用改版面。
## 3. **酒名/料名长度不设上限**：名字栏宽度按所有配方里最长的那条算，
##    新加一个五字酒名，整列会一起右移，不会挤掉图标。
## ─────────────────────────────────────────────────────────────────
## 版面（相对内层内容区；内层 = 外框内缩 2px）：
##   580×292 → 表头 0..48 / 正文 48..262 / 页脚 262..288
##   左列 160 宽三个锅位；右列 392 宽五条可见配方，每行 36 高

const FRAME: Rect2 = Rect2(30, 46, 580, 292)

const SLOT_X: int = 8
const SLOT_W: int = 160
const SLOT_H: int = 60
const SLOT_TOP: int = 68
const SLOT_STEP: int = 65

const ROW_X: int = 176
const ROW_W: int = 392
const ROW_H: int = 36
const ROW_TOP: int = 68
const ROW_STEP: int = 38
## 一屏能放几条配方。比这多就滚动，行控件数量不跟着涨。
const VISIBLE_ROWS: int = 5
## 每条配方最多预留几味料的 UI 槽。超出的不会画（但也没见过 7 味料的酒）。
const MAX_ING: int = 6

const POT_EMPTY: String = "res://assets/items/pot/pot_empty.png"
const POT_FULL: String = "res://assets/items/pot/pot_full.png"

const WINE_ICON_X: int = 4
const NAME_X: int = 44
## 料区左边界相对行左缘（名字栏宽度算完再定，见 _measure_name_column）
var _ing_start: int = 100
## 料区右边界相对行左缘
const ING_END_PAD: int = 8

var _recipes: Array[String] = []
var _window: ListWindow = ListWindow.new()
var _slot_ui: Array[Dictionary] = []
var _row_ui: Array[Dictionary] = []
var _money: Label = null
var _dur_head: Label = null
var _indicator: Label = null
var _message: Label = null
var _message_frames: int = 0
## 当前这行字是不是"被动提示"（会自动更新/清除），还是 _say 的一次性反馈
var _message_passive: bool = false


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)
	_recipes = ItemDB.recipe_ids()
	_measure_name_column()

	_header()
	_slot_column()
	_recipe_column()

	UiStyle.divider(_frame, 8, 262, int(FRAME.size.x) - 20)
	var hint: Label = UiStyle.label("[W/S] 选配方   [E] 开酿   [R] 收酒   [Esc] 关闭", UiStyle.LINEN_DARK)
	hint.position = Vector2(10, 268)
	_frame.add_child(hint)
	_message = UiStyle.label("", UiStyle.FIRE)
	_message.position = Vector2(330, 268)
	_message.size = Vector2(230, 14)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_message)

	_window.configure(_recipes.size(), VISIBLE_ROWS, true)
	_window.set_index(_first_affordable())
	_refresh_slots()
	_refresh_rows()


## 名字栏宽度 = 所有配方里最长的酒名。以后加一个五字酒名，整列自动右移。
func _measure_name_column() -> void:
	var widest: int = 0
	for rid: String in _recipes:
		var out_id: String = str(ItemDB.recipe(rid)["output"])
		widest = maxi(widest, UiStyle.text_width(ItemDB.item_name(out_id)))
	_ing_start = NAME_X + widest + 10


# ---- 搭界面 --------------------------------------------------------------

func _header() -> void:
	var pot: TextureRect = UiStyle.icon(load(POT_FULL) as Texture2D, Vector2i(30, 40))
	pot.position = Vector2(10, 4)
	_frame.add_child(pot)

	var title: Label = UiStyle.label("酿酒", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(52, 12)
	_frame.add_child(title)

	_money = UiStyle.label("铜 0", UiStyle.GOLD)
	_money.position = Vector2(448, 18)
	_money.size = Vector2(112, 16)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_money)
	Inventory.copper_changed.connect(_on_copper_changed)
	_on_copper_changed(Inventory.copper)

	# 选中配方的时长（三味料吃掉了行尾，时长搬到表头中间）
	_dur_head = UiStyle.label("", UiStyle.LINEN_DARK)
	_dur_head.position = Vector2(150, 18)
	_dur_head.size = Vector2(280, 16)
	_dur_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(_dur_head)

	UiStyle.divider(_frame, 8, 48, int(FRAME.size.x) - 20)


func _slot_column() -> void:
	var head: Label = UiStyle.label("酿槽", UiStyle.LINEN_DARK)
	head.position = Vector2(10, 52)
	_frame.add_child(head)

	for i in BrewingService.SLOT_COUNT:
		var y: int = SLOT_TOP + i * SLOT_STEP
		var box: Panel = UiStyle.panel(UiStyle.SHADOW, UiStyle.BROWN)
		box.position = Vector2(SLOT_X, y)
		box.size = Vector2(SLOT_W, SLOT_H)
		_frame.add_child(box)

		var art: TextureRect = UiStyle.icon(load(POT_EMPTY) as Texture2D, Vector2i(30, 40))
		art.position = Vector2(SLOT_X + 8, y + 10)
		_frame.add_child(art)

		var state: Label = UiStyle.label("", UiStyle.LINEN)
		state.position = Vector2(SLOT_X + 46, y + 8)
		_frame.add_child(state)

		var detail: Label = UiStyle.label("", UiStyle.LINEN_DARK)
		detail.position = Vector2(SLOT_X + 46, y + 24)
		_frame.add_child(detail)

		var bar_bg: ColorRect = UiStyle.rect(UiStyle.BROWN)
		bar_bg.position = Vector2(SLOT_X + 46, y + 45)
		bar_bg.size = Vector2(112, 4)
		_frame.add_child(bar_bg)

		var bar_fill: ColorRect = UiStyle.rect(UiStyle.FIRE)
		bar_fill.position = bar_bg.position
		bar_fill.size = Vector2(0, 4)
		_frame.add_child(bar_fill)

		_slot_ui.append({"y": y, "icon": art, "state": state, "detail": detail, "fill": bar_fill})


## 只建 VISIBLE_ROWS 个行控件，之后靠 rebind 换内容 —— 配方加到多少条，
## 节点数都不变。
func _recipe_column() -> void:
	var head: Label = UiStyle.label("配方", UiStyle.LINEN_DARK)
	head.position = Vector2(ROW_X + 2, 52)
	_frame.add_child(head)

	_indicator = UiStyle.label("", UiStyle.METAL_DARK)
	_indicator.position = Vector2(ROW_X + 40, 52)
	_frame.add_child(_indicator)

	for r in VISIBLE_ROWS:
		var y: int = ROW_TOP + r * ROW_STEP

		var bg: ColorRect = UiStyle.rect(UiStyle.BROWN)
		bg.position = Vector2(ROW_X, y)
		bg.size = Vector2(ROW_W, ROW_H)
		bg.visible = false
		_frame.add_child(bg)

		var accent: ColorRect = UiStyle.rect(UiStyle.FIRE)
		accent.position = Vector2(ROW_X, y)
		accent.size = Vector2(2, ROW_H)
		accent.visible = false
		_frame.add_child(accent)

		var wine_icon: TextureRect = UiStyle.icon(load(POT_EMPTY) as Texture2D, Vector2i(32, 32))
		wine_icon.position = Vector2(ROW_X + WINE_ICON_X, y + 2)
		wine_icon.visible = false
		_frame.add_child(wine_icon)

		var name_label: Label = UiStyle.label("")
		name_label.position = Vector2(ROW_X + NAME_X, y + 12)
		name_label.visible = false
		_frame.add_child(name_label)

		# 料位池：每行预留 MAX_ING 组「图标 + 名字×份数」，绑定时决定显示几组
		var ings: Array[Dictionary] = []
		for k in MAX_ING:
			var ing_icon: TextureRect = UiStyle.icon(load(POT_EMPTY) as Texture2D, Vector2i(32, 32))
			ing_icon.visible = false
			_frame.add_child(ing_icon)

			var ing_name: Label = UiStyle.label("")
			ing_name.visible = false
			_frame.add_child(ing_name)

			ings.append({"icon": ing_icon, "name": ing_name})

		_row_ui.append({"y": y, "bg": bg, "accent": accent, "wine_icon": wine_icon,
				"name": name_label, "ings": ings, "bound": ""})


# ---- 每帧刷新 ------------------------------------------------------------

func _process(_delta: float) -> void:
	if _message_frames > 0:
		_message_frames -= 1
		if _message_frames == 0:
			_message.text = ""
	_refresh_slots()
	_refresh_rows()


func _refresh_slots() -> void:
	for i in _slot_ui.size():
		var slot: Dictionary = BrewingService.slots[i]
		var ui: Dictionary = _slot_ui[i]
		var art: TextureRect = ui["icon"]
		var state_label: Label = ui["state"]
		var detail: Label = ui["detail"]
		var fill: ColorRect = ui["fill"]
		var y: int = int(ui["y"])
		var state: int = int(slot["state"])

		if state == BrewingService.State.EMPTY:
			_set_art(art, load(POT_EMPTY) as Texture2D, Vector2i(30, 40), y, Vector2(8, 10))
			art.modulate = Color(1, 1, 1, 0.42)
			state_label.text = "空槽"
			state_label.add_theme_color_override("font_color", UiStyle.METAL_DARK)
			detail.text = "还空着"
			detail.add_theme_color_override("font_color", UiStyle.BROWN.lightened(0.25))
			fill.size = Vector2(0, 4)
			continue

		var out_id: String = str(slot["output"])
		_set_art(art, ItemDB.icon(out_id), Vector2i(32, 32), y, Vector2(7, 14))
		art.modulate = Color(1, 1, 1, 1)
		state_label.text = ItemDB.item_name(out_id)

		if state == BrewingService.State.READY:
			state_label.add_theme_color_override("font_color", UiStyle.FIRE_CORE)
			detail.text = "可以收了 [R]"
			detail.add_theme_color_override("font_color", UiStyle.FIRE)
			fill.size = Vector2(112, 4)
		else:
			state_label.add_theme_color_override("font_color", UiStyle.LINEN)
			detail.text = "剩 %d 秒" % ceili(BrewingService.remaining_seconds(i))
			detail.add_theme_color_override("font_color", UiStyle.LINEN_DARK)
			fill.size = Vector2(roundf(112.0 * BrewingService.progress(i)), 4)


func _set_art(art: TextureRect, tex: Texture2D, target: Vector2i, slot_y: int, inset: Vector2) -> void:
	if tex != null and art.texture != tex:
		art.texture = tex
	# 两种图标尺寸不同（锅 30×40 / 酒 32×32），最小尺寸要跟着走，否则会被上一张卡住
	art.custom_minimum_size = Vector2(target)
	art.size = Vector2(target)
	art.position = Vector2(SLOT_X + int(inset.x), slot_y + int(inset.y))


func _refresh_rows() -> void:
	_indicator.text = _window.indicator()

	for r in VISIBLE_ROWS:
		var ui: Dictionary = _row_ui[r]
		var idx: int = _window.first() + r
		if idx >= _recipes.size():
			_set_row_visible(ui, false)
			continue
		_set_row_visible(ui, true)

		var rid: String = _recipes[idx]
		if str(ui["bound"]) != rid:
			_bind_row(ui, rid)

		var ok: bool = BrewingService.has_inputs(rid)
		var selected: bool = idx == _window.index

		(ui["bg"] as ColorRect).visible = selected
		(ui["accent"] as ColorRect).visible = selected

		var name_color: Color = UiStyle.LINEN
		if not ok:
			name_color = UiStyle.METAL_DARK
		elif selected:
			name_color = UiStyle.FIRE_CORE
		(ui["name"] as Label).add_theme_color_override("font_color", name_color)

		if selected and _dur_head != null:
			_dur_head.text = "%s · 约 %d 秒" % [ItemDB.item_name(str(ItemDB.recipe(rid)["output"])),
					roundi(BrewingService.recipe_seconds(rid))]

		# 缺料时整行压暗；缺哪一味，就把那一格（图标 + 「名字 ×份数」）一起压暗
		(ui["wine_icon"] as TextureRect).modulate = Color(1, 1, 1, 1.0 if ok else 0.32)
		for ing: Dictionary in (ui["ings"] as Array):
			if not (ing["icon"] as TextureRect).visible:
				continue
			var enough: bool = Inventory.count(str(ing["id"])) >= int(ing["need"])
			(ing["icon"] as TextureRect).modulate = Color(1, 1, 1, 1.0 if enough else 0.3)
			(ing["name"] as Label).add_theme_color_override("font_color",
					UiStyle.LINEN_DARK if enough else UiStyle.METAL_DARK)

	# 底部那行提示只跟着"当前选中这条缺不缺料"走：
	# 缺就说缺什么、去哪儿找；不缺就把之前那句被动提示收掉，别让旧话挂着。
	if _message_frames == 0 and not _recipes.is_empty():
		if BrewingService.has_inputs(_recipes[_window.index]):
			if _message_passive:
				_message.text = ""
				_message_passive = false
		else:
			_passive_hint(_shortage_hint())


func _set_row_visible(ui: Dictionary, shown: bool) -> void:
	if shown:
		(ui["wine_icon"] as TextureRect).visible = true
		(ui["name"] as Label).visible = true
		return
	# 隐藏时连"已绑定"标记一起清掉，下次滚回来会重新绑、把料位恢复出来
	(ui["bg"] as ColorRect).visible = false
	(ui["accent"] as ColorRect).visible = false
	(ui["wine_icon"] as TextureRect).visible = false
	(ui["name"] as Label).visible = false
	for ing: Dictionary in (ui["ings"] as Array):
		(ing["icon"] as TextureRect).visible = false
		(ing["name"] as Label).visible = false
	ui["bound"] = ""


## 把一行控件绑到某条配方上：换图标、换文字、算料位落点。
func _bind_row(ui: Dictionary, rid: String) -> void:
	var y: int = int(ui["y"])
	var out_id: String = str(ItemDB.recipe(rid)["output"])

	var wine_icon: TextureRect = ui["wine_icon"]
	wine_icon.texture = ItemDB.icon(out_id)
	wine_icon.custom_minimum_size = Vector2(32, 32)
	wine_icon.size = Vector2(32, 32)

	var name_label: Label = ui["name"]
	name_label.text = ItemDB.item_name(out_id)

	var inputs: Array = ItemDB.recipe(rid)["inputs"]
	var names: Array[String] = []
	var counts: Array[int] = []
	for e: Variant in inputs:
		var d: Dictionary = e as Dictionary
		names.append(ItemDB.item_name(str(d["id"])))
		counts.append(int(d["count"]))

	var cols: Array[Dictionary] = ingredient_columns(names, counts, ROW_X + _ing_start,
			ROW_X + ROW_W - ING_END_PAD)

	var ings: Array[Dictionary] = ui["ings"]
	for k in ings.size():
		var ing: Dictionary = ings[k]
		var icon: TextureRect = ing["icon"]
		var label: Label = ing["name"]
		if k >= cols.size():
			icon.visible = false
			label.visible = false
			continue

		var col: Dictionary = cols[k]
		icon.texture = ItemDB.icon(str((inputs[k] as Dictionary)["id"]))
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size = Vector2(32, 32)
		icon.position = Vector2(int(col["icon_x"]), y + 2)
		icon.visible = true

		label.text = str(col["text"])
		label.position = Vector2(int(col["label_x"]), y + 12)
		label.visible = true

		ing["id"] = str((inputs[k] as Dictionary)["id"])
		ing["need"] = int((inputs[k] as Dictionary)["count"])

	ui["bound"] = rid


## 把 1..N 味料按剩余宽度排成一排。
##
## 依次尝试三档写法，取第一个放得下的：
##   ① 「焦麦 ×2」（最舒服）
##   ② 「焦麦×2」（去掉空格）
##   ③ 「×2」（只留份数，名字靠图标认）
## 三档都不行就只画图标、按等距铺开 —— 再多的料也不会画到行外。
##
## 纯函数，不碰节点，所以能在无窗口验收里直接断言"不重叠、不出界"。
static func ingredient_columns(names: Array[String], counts: Array[int],
		x_start: int, x_end: int) -> Array[Dictionary]:
	var n: int = names.size()
	if n == 0:
		return []
	var avail: int = x_end - x_start
	if avail <= 0:
		return []

	for mode in 3:
		var labels: Array[String] = []
		var widths: Array[int] = []
		for i in n:
			var label: String = ""
			match mode:
				0: label = "%s ×%d" % [names[i], counts[i]]
				1: label = "%s×%d" % [names[i], counts[i]]
				_: label = "×%d" % counts[i]
			labels.append(label)
			widths.append(UiStyle.text_width(label))
		for gap: int in [12, 10, 8, 6, 4, 2]:
			var total: int = gap * (n - 1)
			for w: int in widths:
				total += 32 + 4 + w
			if total <= avail:
				var out: Array[Dictionary] = []
				var x: int = x_start
				for i in n:
					out.append({"icon_x": x, "label_x": x + 36, "text": labels[i]})
					x += 32 + 4 + widths[i] + gap
				return out

	# 兜底：只留图标，等距铺开
	var step: int = maxi(34, floori(float(avail) / float(n)))
	var icons_only: Array[Dictionary] = []
	for i in n:
		icons_only.append({"icon_x": x_start + i * step, "label_x": x_start, "text": ""})
	return icons_only


# ---- 交互 ----------------------------------------------------------------

func _first_affordable() -> int:
	for i in _recipes.size():
		if BrewingService.has_inputs(_recipes[i]):
			return i
	return 0


func _on_copper_changed(value: int) -> void:
	if _money != null:
		_money.text = "铜 %d" % value


func _on_key(keycode: int) -> bool:
	match keycode:
		KEY_W, KEY_UP:
			_move(-1)
			return true
		KEY_S, KEY_DOWN:
			_move(1)
			return true
		KEY_E:
			_start()
			return true
		KEY_R:
			_collect()
			return true
	return false


func _move(step: int) -> void:
	if _recipes.is_empty():
		return
	_window.move(step)


func _start() -> void:
	if _recipes.is_empty():
		return
	var rid: String = _recipes[_window.index]
	if BrewingService.first_empty() < 0:
		_say("三口锅都在忙，先收一锅", UiStyle.FIRE)
		return
	if not BrewingService.has_inputs(rid):
		_say("材料不够，去集市买", UiStyle.FIRE)
		return
	if BrewingService.start(rid) >= 0:
		_say("投料了 —— %s" % ItemDB.item_name(str(ItemDB.recipe(rid)["output"])), UiStyle.LINEN)


func _collect() -> void:
	for i in BrewingService.SLOT_COUNT:
		if int(BrewingService.slots[i]["state"]) == BrewingService.State.READY:
			var out_id: String = BrewingService.collect(i)
			_say("收了一锅%s" % ItemDB.item_name(out_id), UiStyle.LINEN)
			return
	_say("还没有能收的", UiStyle.LINEN_DARK)


func _say(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message_frames = 120
	_message_passive = false


## 缺料时提示"去哪儿找"。产地是从数据里读的，所以集市下架、矿道新增都不用改这里。
## 先看当前选中的那条，再看别的，免得明明选着焦麦烈啤却提示另一种料。
func _shortage_hint() -> String:
	var order: Array[int] = [_window.index]
	for i in _recipes.size():
		if i != _window.index:
			order.append(i)
	for i: int in order:
		if i < 0 or i >= _recipes.size():
			continue
		for e: Variant in (ItemDB.recipe(_recipes[i])["inputs"] as Array):
			var d: Dictionary = e as Dictionary
			var id: String = str(d["id"])
			if Inventory.count(id) >= int(d["count"]):
				continue
			if ItemDB.obtain_of(id) == ItemDB.OBTAIN_MARKET:
				return "材料不够 —— 去村里的集市买"
			return "缺 %s —— %s才有" % [ItemDB.item_name(id), ItemDB.source_text(id)]
	return "材料不够"


func _passive_hint(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UiStyle.LINEN_DARK)
	_message_passive = true
