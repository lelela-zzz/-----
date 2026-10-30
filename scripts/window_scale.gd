extends Node
## 显示设置中心（autoload：WindowScale）
##
## 【A 路线：内部 2× 渲染】渲染基准是 1280×768（= project.godot 的 viewport），
## 逻辑坐标仍是 640×384 —— 世界和 UI 一行数据都不用改：
##   · 相机 zoom 按「viewport / 640」自动补偿（PixelCamera）
##   · HUD 这一层 CanvasLayer 按同样的倍数放大（ClockHUD 里设）
##   · 底图换成 1280 源 + scale 0.5，于是 1 个源像素 = 1 个渲染像素 = 真细节
##
## 这里管三件事：窗口显示比例、全屏与否、全屏时是否铺满。
## 玩家在设置面板（F10）里改，选择存 user://display.cfg，下次启动照旧。
##
## 另：display/window/size/window_*_override 只在编辑器里跑时生效，导出后
## 会被忽略，所以窗口大小统一由这里决定，别再依赖它。

## 任何一项显示设置变了（面板据此刷新文字）
signal changed

## 渲染基准（= viewport 尺寸，640×384 逻辑 ×2）
const RENDER_SIZE: Vector2i = Vector2i(1280, 768)
## 逻辑坐标基准（世界 / UI 仍按这一套数字摆放）
const LOGIC_SIZE: Vector2i = Vector2i(640, 384)

## 可选显示比例。整数档（100% / 200%）走整数缩放最锐，半档靠非整数插值
const STEPS: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]
## 自适应档给标题栏 / 任务栏留的余量
const EDGE_MARGIN: int = 56

const CONFIG_PATH: String = "user://display.cfg"
const CFG_SECTION: String = "display"

## 验收/截图脚本用的旁路：true = 强制 viewport 回到 640×384 逻辑分辨率，
## 这样按 640 坐标写的像素断言不用改（tests/test_view.gd 会置位）
var force_logic_viewport: bool = false

## 0 = 自适应（取屏幕放得下的最大档），否则取 STEPS 里的一档
var display_scale: float = 0.0
var fullscreen: bool = false
## 全屏时是否放弃比例去铺满（false = 保持比例、可能带黑边）
var fill_screen: bool = false


func _ready() -> void:
	load_settings()
	if _headless():
		return
	# 等一帧，让主窗口真正创建完再动它
	await get_tree().process_frame
	apply()


# ---- 查询（面板 / 验收都读这些，纯函数不碰窗口）----------------------------

## 屏幕放得下的最大档（自适应就用它）
func fit_scale() -> float:
	var usable: Rect2i = _usable_rect()
	var avail: Vector2i = usable.size - Vector2i(EDGE_MARGIN, EDGE_MARGIN)
	var raw: float = minf(float(avail.x) / float(RENDER_SIZE.x),
			float(avail.y) / float(RENDER_SIZE.y))
	var best: float = 1.0
	for s: float in STEPS:
		if s <= raw + 0.001:
			best = s
	return best


## 面板里列出来的档位：屏幕放得下的那些（放不下的不列，免得选完被裁掉）
func scales() -> Array[float]:
	var out: Array[float] = []
	var top: float = fit_scale()
	for s: float in STEPS:
		if s <= top + 0.001:
			out.append(s)
	if out.is_empty():
		out.append(1.0)
	return out


## 实际生效的比例：自适应 = 最大档；固定档超出屏幕时夹回最大档
func resolved_scale() -> float:
	if display_scale <= 0.0:
		return fit_scale()
	return clampf(display_scale, 1.0, fit_scale())


## 渲染倍率（生产 = 1280/640 = 2；测试旁路下 = 1）。
## 相机 zoom / HUD 缩放都用它，别在 _ready 里去查 viewport —— 那时
## content_scale 可能还没生效，会读出旧尺寸。
func render_scale() -> Vector2:
	var base: Vector2i = LOGIC_SIZE if force_logic_viewport else RENDER_SIZE
	return Vector2(float(base.x) / float(LOGIC_SIZE.x), float(base.y) / float(LOGIC_SIZE.y))


func window_size() -> Vector2i:
	var s: float = resolved_scale()
	return Vector2i(roundi(float(RENDER_SIZE.x) * s), roundi(float(RENDER_SIZE.y) * s))


## 整数档才能用 INTEGER 缩放（像素最锐）；半档只能非整数插值
func stretch() -> String:
	if fullscreen and fill_screen:
		return "fractional"
	var s: float = resolved_scale()
	return "integer" if is_equal_approx(s, roundf(s)) else "fractional"


## 面板上显示的那行字（"自适应 · 150%（1920×1152）"）
func scale_text(value: float) -> String:
	var s: float = fit_scale() if value <= 0.0 else clampf(value, 1.0, fit_scale())
	var px: Vector2i = Vector2i(roundi(float(RENDER_SIZE.x) * s), roundi(float(RENDER_SIZE.y) * s))
	var pct: int = roundi(s * 100.0)
	if value <= 0.0:
		return "自适应 · %d%%（%d×%d）" % [pct, px.x, px.y]
	if s < value - 0.001:
		return "%d%% 放不下（按 %d%%）" % [roundi(value * 100.0), pct]
	return "%d%%（%d×%d）" % [pct, px.x, px.y]


# ---- 修改 ------------------------------------------------------------------

func set_display_scale(value: float) -> void:
	value = 0.0 if value <= 0.0 else clampf(value, 1.0, STEPS[STEPS.size() - 1])
	if is_equal_approx(value, display_scale):
		return
	display_scale = value
	_commit()


func set_fullscreen(on: bool) -> void:
	if on == fullscreen:
		return
	fullscreen = on
	_commit()


func set_fill_screen(on: bool) -> void:
	if on == fill_screen:
		return
	fill_screen = on
	_commit()


## 改一项 → 立刻生效 + 写盘 + 通知界面
func _commit() -> void:
	apply()
	save_settings()
	changed.emit()


# ---- 应用到窗口 ------------------------------------------------------------

func apply() -> void:
	if _headless():
		return
	_apply_content_scale()
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print("[WindowScale] 全屏（%s 缩放）" % stretch())
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size: Vector2i = window_size()
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(_centre(size))
	print("[WindowScale] 窗口 %d×%d（%d%%，%s）" % [size.x, size.y,
			roundi(resolved_scale() * 100.0), stretch()])


## 主窗口的拉伸参数等价于 project.godot 的 stretch/*，只是可以在运行时切
func _apply_content_scale() -> void:
	var win: Window = get_tree().root
	if force_logic_viewport:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		win.content_scale_size = LOGIC_SIZE
		win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_size = RENDER_SIZE
	win.content_scale_stretch = (Window.CONTENT_SCALE_STRETCH_INTEGER
			if stretch() == "integer" else Window.CONTENT_SCALE_STRETCH_FRACTIONAL)


# ---- 存读 ------------------------------------------------------------------

func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(CFG_SECTION, "fullscreen", fullscreen)
	cfg.set_value(CFG_SECTION, "display_scale", display_scale)
	cfg.set_value(CFG_SECTION, "fill_screen", fill_screen)
	var err: int = cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("[WindowScale] 存不进 %s（err=%d）" % [CONFIG_PATH, err])


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	fullscreen = bool(cfg.get_value(CFG_SECTION, "fullscreen", fullscreen))
	fill_screen = bool(cfg.get_value(CFG_SECTION, "fill_screen", fill_screen))
	if cfg.has_section_key(CFG_SECTION, "display_scale"):
		display_scale = clampf(float(cfg.get_value(CFG_SECTION, "display_scale", 0.0)), 0.0, 2.0)
	elif cfg.has_section_key(CFG_SECTION, "window_scale"):
		# 兼容上一版存的整数倍数（1/2…）
		display_scale = 0.0 if int(cfg.get_value(CFG_SECTION, "window_scale", 0)) <= 0 else 1.0


## 恢复出厂（验收脚本用完要还原，别在开发机上留下奇怪的配置）
func reset_to_defaults() -> void:
	display_scale = 0.0
	fullscreen = false
	fill_screen = false


# ---- 内部 ------------------------------------------------------------------

func _headless() -> bool:
	# --headless 下没有真实显示器，所有窗口调用都跳过，验收脚本不受影响
	return DisplayServer.get_name() == "headless"


func _usable_rect() -> Rect2i:
	if not _headless():
		var r: Rect2i = DisplayServer.screen_get_usable_rect(
				DisplayServer.window_get_current_screen())
		if r.size.x > 0 and r.size.y > 0:
			return r
	# headless / 取不到屏幕时给个常见的 1080p，让纯逻辑验收有确定结果
	return Rect2i(Vector2i.ZERO, Vector2i(1920, 1080))


func _centre(size: Vector2i) -> Vector2i:
	var usable: Rect2i = _usable_rect()
	return usable.position + (usable.size - size) / 2
