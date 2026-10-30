class_name QuestTracker
extends Control
## 左上角常驻的任务入口：一枚「精装笔记本」图标按钮（点它 = 按 Q 打开任务清单）。
##
## 2026-10-26 改（用户要求：原来那张追踪卡挡住视野）：
## · **删掉**图标下方那张常驻追踪卡（任务标题 + 步骤列表）——它一直压在场景左上角，
##   把本该看到的地面和角色盖住了。任务内容只在「按 Q / 点书」的完整清单里看。
## · 任务状态改由这枚书自己表达，一眼能看见：
##    ① 图标 20px → **48px**（64 原图 ×0.75，NEAREST 采样；64 太大、32 会把缝线糊掉，48 折中）
##    ② 深色底板 + 皮革包边，白天亮底图上也能把书托出来
##    ③ 火光描边的**呼吸描边**：还有任务没做完时一圈橙边慢慢一亮一暗
##    ④ 右下角**数字角标**：还剩几段任务；全部做完时角标和描边一起消失
##    ⑤ 右边「任务追踪 [Q]」：有活儿时字色转火心亮色
##  整块 138×50，比原来那张 216×90 的实心卡片占地更小，也不再是实心色块。
##
## 挂载方式不变：Story 在场景切换时注入到各场景 HUD 下，四个场景共用同一份。
## 数据全在 QuestLog，这里只是它的一个只读视图 —— 监听 changed 刷角标。

const PLATE: int = 50            # 底板边长（图标 48 + 左右各 1px 包边）
const ICON_SIZE: int = 48        # 原图 64 → 48（0.75×，NEAREST 采样）
const WIDTH: int = 138
const HEIGHT: int = 50
const NOTEBOOK: String = "res://assets/items/icons/quest_notebook.png"
const QUEST_PANEL_SCENE: String = "res://scenes/ui/quest_panel.tscn"

var _btn: Button = null
var _rim: Panel = null
var _badge: Panel = null
var _badge_text: Label = null
var _head: Label = null


func _ready() -> void:
	position = Vector2(8, 8)
	size = Vector2(WIDTH, HEIGHT)
	# 整块区不吃鼠标：只有那枚按钮本身可点，其余位置不拦场景点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顶层 HUD 在 CanvasLayer 下没有主题 —— 和世界坐标 Label 同一个坑，显式挂字体
	theme = UiStyle.theme()
	_build()
	_refresh()
	QuestLog.changed.connect(_refresh)


func _build() -> void:
	# ① 底板：深色木底 + 皮革包边，把书从亮底图上托出来
	var plate: Panel = UiStyle.panel(
			Color(UiStyle.SHADOW.r, UiStyle.SHADOW.g, UiStyle.SHADOW.b, 0.90),
			UiStyle.LEATHER_LIGHT)
	plate.position = Vector2.ZERO
	plate.size = Vector2(PLATE, PLATE)
	add_child(plate)

	# ② 书 = 按钮本体（64px 原图，压在底板里）
	_btn = Button.new()
	_btn.flat = true
	_btn.custom_minimum_size = Vector2i(ICON_SIZE, ICON_SIZE)
	_btn.size = Vector2i(ICON_SIZE, ICON_SIZE)
	_btn.position = Vector2(1, 1)
	_btn.tooltip_text = "打开任务清单（Q）"
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	# 悬停/按下给一圈描边，让"可点"看得见
	_btn.add_theme_stylebox_override("hover",
			UiStyle.box(Color(0, 0, 0, 0), UiStyle.FIRE_CORE))
	_btn.add_theme_stylebox_override("pressed",
			UiStyle.box(Color(0, 0, 0, 0), UiStyle.FIRE))
	var icon: TextureRect = UiStyle.icon(load(NOTEBOOK) as Texture2D,
			Vector2i(ICON_SIZE, ICON_SIZE))
	icon.position = Vector2.ZERO
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn.add_child(icon)
	_btn.pressed.connect(_on_icon_pressed)
	add_child(_btn)

	# ③ 火光描边（盖在底板最外圈，只在"还有活儿"时闪）—— 比整块发光干净，
	#    不会把书本身闪得看不清
	_rim = UiStyle.panel(Color(0, 0, 0, 0), UiStyle.FIRE)
	_rim.position = Vector2.ZERO
	_rim.size = Vector2(PLATE, PLATE)
	_rim.visible = false
	add_child(_rim)

	# ④ 数字角标（还剩几段任务），压进底板右下角内侧，不越框
	_badge = UiStyle.panel(UiStyle.FIRE, UiStyle.INK)
	_badge.position = Vector2(PLATE - 16, PLATE - 16)
	_badge.size = Vector2(16, 16)
	_badge.visible = false
	add_child(_badge)
	# 显式给满尺寸 + 顶部对齐：像素字 12px 的行高比格子高，居中会把字顶出角标边
	_badge_text = UiStyle.label("0", UiStyle.INK)
	_badge_text.position = Vector2(0, 1)
	_badge_text.size = Vector2(16, 14)
	_badge_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_badge.add_child(_badge_text)

	# ⑤ 书右边的字
	_head = UiStyle.label("任务追踪", UiStyle.LINEN_DARK)
	_head.position = Vector2(PLATE + 10, 9)
	add_child(_head)
	var key_hint: Label = UiStyle.label("[Q]", UiStyle.LINEN_DARK)
	key_hint.position = Vector2(PLATE + 10, 25)
	add_child(key_hint)

	# 描边呼吸：还有活儿时慢慢一亮一暗，注意别太刺眼
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(_rim, "modulate:a", 0.30, 0.85)
	tw.tween_property(_rim, "modulate:a", 1.00, 0.85)


## 按 QuestLog 的状态刷角标 / 描边 / 字色（唯一跟随任务变化的显示）。
func _refresh() -> void:
	var n: int = _badge_count()
	if _badge != null and is_instance_valid(_badge):
		_badge.visible = n > 0
		_badge_text.text = str(n) if n <= 9 else "9+"
	if _rim != null and is_instance_valid(_rim):
		_rim.visible = n > 0
	if _head != null and is_instance_valid(_head):
		_head.add_theme_color_override("font_color",
				UiStyle.FIRE_CORE if n > 0 else UiStyle.LINEN_DARK)


## 角标：**还剩几段没做完**。
## ⚠ 这里要用 pending()（真实的未完成数），不是任务清单的 visible() 窗口 ——
## 角标回答的是"总共还有多少活儿"，任务清单一次只聚焦露两条，两者本就不是一个口径。
func _badge_count() -> int:
	return QuestLog.pending().size()


## 点笔记本图标 → 弹出任务清单面板（与 Q 键同源：加到 HUD、模态判定一致）。
func _on_icon_pressed() -> void:
	# 已有模态面板（对话框 / 集市 / 酿造 / 其它任务面板）开着时不重复开
	if not get_tree().get_nodes_in_group("modal_ui").is_empty():
		return
	var hud: Node = get_parent()   # 追踪器挂在 HUD 下，父节点即 HUD
	if hud == null:
		return
	var ps: PackedScene = load(QUEST_PANEL_SCENE) as PackedScene
	if ps == null:
		push_error("QuestTracker：加载不了 %s" % QUEST_PANEL_SCENE)
		return
	hud.add_child(ps.instantiate())


## 「✓ 走出酒馆」 / 「· 生姜 2/4」 —— 计数没满的把进度缀在后面。
## （任务清单面板 quest_panel 也调这个，两处格式必须一致）
static func _step_text(s: Dictionary) -> String:
	var text: String = str(s["text"])
	var mark: String = "✓ " if bool(s["done"]) else "· "
	var need: int = int(s["need"])
	if need > 1 and not bool(s["done"]):
		text = "%s %d/%d" % [text, int(s["got"]), need]
	return mark + text
