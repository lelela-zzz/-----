extends Control
## 显示设置（F10 面板）验收：比例档 / 存读 / 面板交互 / 文案不越框。
##
## A 路线后渲染基准是 1280×768（逻辑 640×384 ×2），窗口用"显示比例"表达
## （100% = 1280×768，150% = 1920×1152）。
##
## headless 可跑：WindowScale 在无头模式下不碰真实窗口，只走纯逻辑，
## 所以这里能断言"选了 200% 也会被夹回屏幕放得下的档"这类规则。
## 用例结束后把设置还原成默认并写盘，别在开发机上留下奇怪配置。

const PANEL: String = "res://scenes/ui/settings_panel.tscn"
const INNER_W: int = 396          # FRAME 内宽（400 - 描边 4）
const VAL_RIGHT: float = 386.0    # settings_panel.VAL_RIGHT

var passed: int = 0
var failed: int = 0
var panel: Node = null


func _ready() -> void:
	TestView.logic_resolution()
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	WindowScale.reset_to_defaults()

	_check_defaults()
	_check_scales()
	_check_persist()
	_check_stretch()
	_check_panel()

	_restore()
	_finish()


# ---- 用例 ------------------------------------------------------------------

func _check_defaults() -> void:
	_report("默认：窗口化 / 自适应 / 整数档",
			WindowScale.display_scale == 0.0 and not WindowScale.fullscreen
			and not WindowScale.fill_screen, _state())
	_report("默认比例 = 屏幕放得下的最大档",
			is_equal_approx(WindowScale.resolved_scale(), WindowScale.fit_scale()),
			"%s vs %s" % [WindowScale.resolved_scale(), WindowScale.fit_scale()])
	_report("窗口尺寸 = 1280×768 × 比例",
			WindowScale.window_size() == _px_for(WindowScale.resolved_scale()),
			str(WindowScale.window_size()))


func _check_scales() -> void:
	var list: Array[float] = WindowScale.scales()
	var fit: float = WindowScale.fit_scale()
	_report("档位从 100% 起", list.size() > 0 and is_equal_approx(list[0], 1.0), str(list))
	_report("档位到「屏幕放得下」为止（不列越屏选项）",
			is_equal_approx(list[list.size() - 1], fit), "%s / fit=%s" % [str(list), fit])

	var usable: Rect2i = WindowScale._usable_rect()
	var all_fit: bool = true
	for s: float in list:
		var px: Vector2i = _px_for(s)
		if px.x > usable.size.x or px.y > usable.size.y:
			all_fit = false
	_report("每档都放得进可用区", all_fit, "可用区 %s" % str(usable.size))

	# 手改超屏档位（换了小显示器后读到旧配置）要被夹回来
	WindowScale.set_display_scale(2.0)
	_report("越屏档位自动夹回最大档",
			WindowScale.resolved_scale() <= fit + 0.001
			and WindowScale.window_size().y <= usable.size.y,
			"要 200%% → 实际 %d%% / 尺寸 %s" % [roundi(WindowScale.resolved_scale() * 100.0),
					str(WindowScale.window_size())])

	WindowScale.set_display_scale(-3.0)
	_report("负数比例夹到 0（自适应）", WindowScale.display_scale == 0.0,
			str(WindowScale.display_scale))

	WindowScale.set_display_scale(1.0)
	_report("固定 100% = 1280×768", WindowScale.window_size() == Vector2i(1280, 768),
			str(WindowScale.window_size()))
	_report("档位文案带百分比与像素尺寸",
			WindowScale.scale_text(1.0).contains("100%")
			and WindowScale.scale_text(1.0).contains("1280×768"),
			WindowScale.scale_text(1.0))
	_report("自适应档文案标明「自适应」",
			WindowScale.scale_text(0.0).contains("自适应"), WindowScale.scale_text(0.0))


func _check_persist() -> void:
	var all_scales: Array[float] = WindowScale.scales()
	var target: float = all_scales[all_scales.size() - 1]
	WindowScale.set_display_scale(target)
	WindowScale.set_fullscreen(true)
	WindowScale.set_fill_screen(true)

	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(WindowScale.CONFIG_PATH)
	_report("改动立刻写盘", err == OK, "err=%d" % err)
	_report("盘上记下了比例 / 全屏 / 铺满",
			is_equal_approx(float(cfg.get_value(WindowScale.CFG_SECTION, "display_scale", -1.0)), target)
			and bool(cfg.get_value(WindowScale.CFG_SECTION, "fullscreen", false))
			and bool(cfg.get_value(WindowScale.CFG_SECTION, "fill_screen", false)),
			"scale=%s fullscreen=%s fill=%s" % [
					cfg.get_value(WindowScale.CFG_SECTION, "display_scale", -1.0),
					cfg.get_value(WindowScale.CFG_SECTION, "fullscreen", false),
					cfg.get_value(WindowScale.CFG_SECTION, "fill_screen", false)])

	# 假装是下次启动：内存清空后再读盘
	WindowScale.display_scale = 0.0
	WindowScale.fullscreen = false
	WindowScale.fill_screen = false
	WindowScale.load_settings()
	_report("下次启动读回同样的设置",
			is_equal_approx(WindowScale.display_scale, target) and WindowScale.fullscreen
			and WindowScale.fill_screen,
			"scale=%s fullscreen=%s fill=%s" % [WindowScale.display_scale,
					WindowScale.fullscreen, WindowScale.fill_screen])

	WindowScale.reset_to_defaults()


func _check_stretch() -> void:
	WindowScale.set_display_scale(1.0)
	_report("100%（整数倍）用整数缩放，像素最锐", WindowScale.stretch() == "integer",
			WindowScale.stretch())

	WindowScale.set_display_scale(1.5)
	if WindowScale.resolved_scale() > 1.01 and not is_equal_approx(WindowScale.resolved_scale(), 1.0):
		_report("半档（如 150%）改用非整数插值", WindowScale.stretch() == "fractional",
				"%s / %s" % [WindowScale.resolved_scale(), WindowScale.stretch()])

	WindowScale.set_fullscreen(true)
	WindowScale.set_fill_screen(true)
	_report("全屏 + 铺满 = 非整数插值", WindowScale.stretch() == "fractional",
			WindowScale.stretch())
	WindowScale.reset_to_defaults()


func _check_panel() -> void:
	_open()
	var texts: Array[String] = _labels()

	_report("面板列出三项设置",
			_has(texts, "显示模式") and _has(texts, "窗口大小") and _has(texts, "全屏缩放"),
			"%s" % str(texts))
	_report("带操作提示", _has(texts, "[W/S] 选") and _has(texts, "[Esc] 返回"),
			"%s" % str(texts))
	_report("初始选中第一行", panel.get("_index") == 0, str(panel.get("_index")))
	_report("窗口化状态显示「窗口化」", _has(texts, "窗口化"), "%s" % str(texts))

	# 窗口大小：A 往左一档，从「自适应」回绕到最后一档
	press(KEY_S)
	_report("S 下移到第二行", panel.get("_index") == 1, str(panel.get("_index")))
	press(KEY_A)
	var all_scales: Array[float] = WindowScale.scales()
	var top: float = all_scales[all_scales.size() - 1]
	_report("A/D 能真实改显示比例", is_equal_approx(WindowScale.display_scale, top),
			"要 %s / 实际 %s" % [top, WindowScale.display_scale])

	# 全屏：回到第一行切换
	press(KEY_W)
	press(KEY_D)
	_report("第一行 A/D 切换成全屏", WindowScale.fullscreen, _state())

	texts = _labels()
	_report("全屏后「窗口大小」标为不适用", _has(texts, "不适用"), "%s" % str(texts))
	_report("全屏后「全屏缩放」可改并显示当前值",
			_has(texts, "整数倍"), "%s" % str(texts))

	# 全屏时窗口大小改不动
	press(KEY_S)
	var before: float = WindowScale.display_scale
	press(KEY_D)
	_report("全屏时窗口大小改不动（置灰行不响应）",
			is_equal_approx(WindowScale.display_scale, before),
			"%s → %s" % [before, WindowScale.display_scale])

	# 全屏缩放：再下一行 → 切铺满
	press(KEY_S)
	press(KEY_D)
	_report("全屏缩放切到铺满后立刻生效",
			WindowScale.fill_screen and WindowScale.stretch() == "fractional",
			"%s / %s" % [str(WindowScale.fill_screen), WindowScale.stretch()])
	texts = _labels()
	_report("切铺满后文案跟着变", _has(texts, "铺满"), "%s" % str(texts))

	_report("所有数值文案都在框内", _values_fit(), _overflow_detail())

	press(KEY_W)
	press(KEY_W)
	press(KEY_D)
	_report("再切回窗口化：窗口大小恢复可改（不再标不适用）",
			not WindowScale.fullscreen and not _has(_labels(), "不适用"), _state())

	_close()


# ---- 工具 ------------------------------------------------------------------

func press(keycode: int) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	panel._on_key(keycode)


func _open() -> void:
	_close()
	var ps: PackedScene = load(PANEL) as PackedScene
	panel = ps.instantiate()
	add_child(panel)


func _close() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = null


## 某个比例对应的窗口像素
func _px_for(scale: float) -> Vector2i:
	return Vector2i(roundi(float(WindowScale.RENDER_SIZE.x) * scale),
			roundi(float(WindowScale.RENDER_SIZE.y) * scale))


## 面板里所有 Label 的文本
func _labels() -> Array[String]:
	var out: Array[String] = []
	if panel == null or not is_instance_valid(panel):
		return out
	_collect(panel, out)
	return out


func _collect(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	for child: Node in node.get_children():
		_collect(child, out)


func _has(list: Array[String], needle: String) -> bool:
	for t: String in list:
		if t.contains(needle):
			return true
	return false


## 每个值 Label 都要右对齐在 VAL_RIGHT 上、且不越出面板内宽
func _values_fit() -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	for row: Dictionary in panel.get("_rows"):
		var lb: Label = row["value"] as Label
		var right: float = lb.position.x + float(UiStyle.text_width(lb.text))
		if right > float(VAL_RIGHT) + 0.5 or right > float(INNER_W) + 0.5:
			return false
	return true


func _overflow_detail() -> String:
	if panel == null or not is_instance_valid(panel):
		return "面板不在"
	var worst: String = ""
	var max_right: float = 0.0
	for row: Dictionary in panel.get("_rows"):
		var lb: Label = row["value"] as Label
		var right: float = lb.position.x + float(UiStyle.text_width(lb.text))
		if right > max_right:
			max_right = right
			worst = lb.text
	return "最右「%s」到 x=%.0f（上限 %d）" % [worst, max_right, int(VAL_RIGHT)]


func _state() -> String:
	return "scale=%s fullscreen=%s fill=%s" % [WindowScale.display_scale,
			WindowScale.fullscreen, WindowScale.fill_screen]


func _restore() -> void:
	WindowScale.reset_to_defaults()
	WindowScale.save_settings()


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])


func _finish() -> void:
	print("[settings] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
