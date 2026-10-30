class_name UiStyle
extends RefCounted
## 像素 UI 的统一语言：字体、色板、控件工厂。
##
## 三条纪律（和美术管线一致）：
##  1. **只用色板里的颜色**（assets/palette/hearthvale-palette-v4.json）。
##     UI 组里有 gold / danger / success，其余借 structure / cloth / light 组。
##  2. **尺寸全整数**。字体 12px 是缝合像素字体的设计字号；标题用 24px = 2×，
##     正好是整数倍，不会糊。
##  3. **图标只用整除缩放**：64→32（÷2）、60×80 的锅→30×40（÷2）。
##     非整数缩放会让 Nearest 采样出大小不一的像素块。

const FONT_PATH: String = "res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.woff2"

## 描边黑
const INK: Color = Color(0.094118, 0.094118, 0.094118)
## 陈年阴影 —— 面板底
const SHADOW: Color = Color(0.125490, 0.125490, 0.094118)
## 深褐 —— 分隔线、选中行底
const BROWN: Color = Color(0.227451, 0.164706, 0.133333)
## 面板底 —— 比陈年阴影略亮一档，字压在下面才不糊
const PANEL_BG: Color = Color(0.152941, 0.117647, 0.090196)
## 皮革亮 —— 面板的暖色包边
const LEATHER_LIGHT: Color = Color(0.541176, 0.392157, 0.250980)
## 亚麻亮 —— 正文
const LINEN: Color = Color(0.784314, 0.760784, 0.705882)
## 亚麻暗 —— 次要文字
const LINEN_DARK: Color = Color(0.541176, 0.521569, 0.470588)
## 铁件暗面 —— 不可用
const METAL_DARK: Color = Color(0.478431, 0.509804, 0.564706)
## 火光 —— 强调、进度条
const FIRE: Color = Color(0.909804, 0.588235, 0.235294)
## 火心 —— 标题
const FIRE_CORE: Color = Color(0.964706, 0.815686, 0.541176)
## 货币
const GOLD: Color = Color(0.788235, 0.635294, 0.152941)
## 亮黄 —— "这里有东西可互动"的提示（头顶感叹号）。
## 比 GOLD 亮、比 FIRE_CORE 更纯黄，不偏橙红（用户 2026-10-30 明确要黄色）。
const YELLOW: Color = Color(1.0, 0.847059, 0.156863)

const BODY_SIZE: int = 12
const TITLE_SIZE: int = 24

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font = load(FONT_PATH) as Font
	t.default_font_size = BODY_SIZE
	_theme = t
	return t


## 纯色底 + 1px 硬描边的样式盒（像素 UI 不要圆角、不要渐变）。
static func box(bg: Color, border: Color = BROWN, border_width: int = 1) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(0)
	return s


static func label(text: String, color: Color = LINEN, size: int = BODY_SIZE) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	# 显式挂字体：世界坐标里的浮动提示（NPC 的「[E] 交谈」、锅的「[E] 酿造」）
	# 挂在 Node2D 下，拿不到 Control 的 theme，只靠主题会退回内置字体 → 中文变方框。
	l.add_theme_font_override("font", theme().default_font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 带描边的浮动提示（世界坐标里那行「[E] 酿造」）。
static func outlined_label(text: String, color: Color = FIRE_CORE, size: int = BODY_SIZE) -> Label:
	var l: Label = label(text, color, size)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 3)
	return l


static func panel(bg: Color, border: Color = BROWN) -> Panel:
	var p: Panel = Panel.new()
	p.add_theme_stylebox_override("panel", box(bg, border))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func rect(color: Color) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 图标控件。size 必须整除原图（64→32、60×80→30×40），Nearest 才不糊。
##
## 顺序有讲究：**先设 expand_mode 再设 size**。TextureRect 默认的
## EXPAND_KEEP_SIZE 会把最小尺寸锁成纹理原始大小，此时把 size 写成 32 会被静默
## 拦回 64，后面再改 expand_mode 也不会缩回去 —— 图标就会糊满一格。
static func icon(tex: Texture2D, target: Vector2i) -> TextureRect:
	var t: TextureRect = TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture = tex
	t.custom_minimum_size = Vector2(target)
	t.size = Vector2(target)
	return t


## 量一段 12px 像素字的宽度。
##
## 为什么不直接 get_string_size：headless 下 TextServer 是 dummy，量出来恒为 0，
## 排版逻辑就没法在无窗口验收里测。缝合像素是**等宽**字体，汉字正好 12px、
## 半角 6px，按码位数算反而精确且与渲染无关。
## 以后换字体只需改这一处（或给非等宽字体补一张宽度表）。
static func text_width(text: String, size: int = BODY_SIZE) -> int:
	var units: int = 0
	for i in text.length():
		units += 2 if text.unicode_at(i) > 0x7F else 1
	return units * (size / 2)


## 整块面板外框：暗色遮罩 + 居中硬边面板。返回**内容层**，调用方往里摆控件。
##
## 三层叠出来才有"窗口"的厚度：1px 描边黑 → 1px 暖色包边 → 深色面板。
## 只画一层的话，深面板压在暗化的场景上几乎看不出边界（实测对比度不够）。
static func framed(root: Control, frame_rect: Rect2, dim_alpha: float = 0.55) -> Panel:
	# 遮罩铺满 root（UiPanel 已经把自身锁成 640×384 设计画布），
	# 别写死 640×384 —— 将来换设计尺寸时这里要跟着走。
	var canvas: Vector2 = root.size
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		canvas = Vector2(640, 384)
	var dim: ColorRect = rect(Color(INK.r, INK.g, INK.b, dim_alpha))
	dim.size = canvas
	dim.position = Vector2.ZERO
	root.add_child(dim)

	var outline: Panel = panel(INK, INK)
	outline.position = frame_rect.position
	outline.size = frame_rect.size
	root.add_child(outline)

	var rim: Panel = panel(LEATHER_LIGHT, LEATHER_LIGHT)
	rim.position = frame_rect.position + Vector2(1, 1)
	rim.size = frame_rect.size - Vector2(2, 2)
	root.add_child(rim)

	var frame: Panel = panel(PANEL_BG, PANEL_BG)
	frame.position = frame_rect.position + Vector2(2, 2)
	frame.size = frame_rect.size - Vector2(4, 4)
	root.add_child(frame)
	return frame


## 1px 分隔线（横）。
static func divider(parent: Control, x: int, y: int, w: int, color: Color = BROWN) -> void:
	var line: ColorRect = rect(color)
	line.position = Vector2(x, y)
	line.size = Vector2(w, 1)
	parent.add_child(line)


## 当前场景的 UI 注入点 —— HUD 下的 UIRoot（640×384 逻辑坐标 + 整体放大）。
##
## **不要直接往 CanvasLayer（HUD 本身）里塞面板。** CanvasLayer 里的 Control
## 按 viewport（1280×768）算 rect，而所有面板都是按 640×384 画的：结果面板
## 只占屏幕左上四分之一、字还是 1× 大小 —— 这就是"换了分辨率对话框不适配"。
## UIRoot 是 640×384 的容器再整体 scale，面板挂进去才是 2× 铺满。
##
## 找不到 UIRoot 时退回 HUD 也不会崩：UiPanel 会按容器实际尺寸自己换算缩放。
static func ui_layer(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	var tree: SceneTree = from.get_tree()
	var scene: Node = tree.current_scene
	if scene != null:
		var ui: Node = scene.get_node_or_null("HUD/UIRoot")
		if ui != null:
			return ui
		var hud: Node = scene.get_node_or_null("HUD")
		if hud != null:
			return hud
	# 验收脚本把场景 add_child 进测试节点时，current_scene 可能不是它 —— 全树找。
	# 不用 Node.find_child：运行时实例化的节点 owner 为空，find_child 会漏。
	var found: Node = _find_named(tree.root, "UIRoot")
	if found != null:
		return found
	return _find_named(tree.root, "HUD")


## 按名字递归找节点（不依赖 owner，运行时拼出来的树也能找）。
static func _find_named(from: Node, want: String) -> Node:
	for child: Node in from.get_children():
		if String(child.name) == want:
			return child
		var deep: Node = _find_named(child, want)
		if deep != null:
			return deep
	return null
