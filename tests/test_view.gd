class_name TestView
extends RefCounted
## 验收脚本专用的"逻辑分辨率"开关。
##
## A 路线把内部渲染提到了 1280×768（640×384 逻辑 ×2）。像素级断言（遮挡判色、
## 边界位置、截图裁剪）都是按 640 坐标写的，所以验收脚本在实例化场景**之前**
## 调一次 logic_resolution()，把 root viewport 降回 640×384：
##   · 相机 zoom / UI 倍数都是按 viewport 自动算的，降回 640 后场景依然正确；
##   · 断言、观感图路径都不用改，历史图仍可对照。
##
## 想看真·2× 渲染请跑 tests/hd_shot.gd（它故意不调这个）。

const LOGIC: Vector2i = Vector2i(640, 384)


static func logic_resolution() -> void:
	# 关掉 WindowScale 的自动 apply —— 它是 autoload，可能在测试 _ready 之后
	# 才跑第一帧，会把 content_scale 又改回 1280
	WindowScale.force_logic_viewport = true
	var root: Window = Engine.get_main_loop().root as Window
	if root == null:
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = LOGIC
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
