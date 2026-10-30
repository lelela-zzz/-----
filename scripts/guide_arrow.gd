extends Control
class_name GuideArrow
## 屏幕边缘罗盘箭头 —— 指引系统的**表现层**。
##
## 只做一件事：把 QuestGuide 算好的「下一跳目标点」画成一枚持续指向的黄色箭头。
## 跨图路线怎么算的，这里一概不管 —— 以后换箭头样式 / 加小地图引导，
## 都不用碰寻路逻辑。
##
## 显示规则（用户 2026-10-27 要求"**不断**指向下一个传送点"）：
##  · 目标在屏幕外 → **贴边罗盘**：箭头贴到安全区边界，绕自身中心指向它；
##  · 目标在屏幕内 → **地标箭头**：悬在目标正上方、朝下指（视野里一眼找到门）；
##  · 距离 ≤ ARRIVE_DIST → 收起（门口本来就有 [E] 提示 / 踩上去直接传送）；
##  · 有模态面板（对话 / 任务清单 / 酿造…）开着 → 藏起来，不和 UI 抢地方。
##
## 坐标：挂在 HUD/UIRoot 下，用 640×384 逻辑坐标；目标点由
## get_global_transform_with_canvas() 换算 —— 相机缩放、限位都不会算歪。
##
## 跨图时不用做任何特殊处理：踩门换图后 current_scene 变了，
## QuestGuide 自动重算，箭头就跟着改指新图的下一跳。

const ARROW_TEX: String = "res://assets/ui/guide_arrow.png"
const ARROW_SIZE: int = 16

## 安全区：箭头贴边时离屏幕边缘留这么远（逻辑像素）。
const EDGE_MARGIN: float = 20.0

## 走到离目标多近算"到了"。
const ARRIVE_DIST: float = 26.0

## 目标在屏幕内时，标记悬在它上方多高。
## 分两种情况：门的触发框中心不高，抬 30 就够（别飘到半空显得脱节）；
## 目的地是 NPC 时节点原点是**脚底**，角色约 60px 高，得抬过 60 才不压在身上。
const MARK_LIFT_DOOR: float = 30.0
const MARK_LIFT_DEST: float = 64.0

## 上下轻微浮动，提示"这是活的指引"；幅度控制在 2px 内，别晃眼。
const BOB_AMP: float = 2.0
const BOB_SPEED: float = 2.4

var _sprite: TextureRect = null
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 父容器 UIRoot 本身就是 640×384 的设计画布，铺满它即可。
	# ⚠️ 用 set_anchors_and_offsets_preset：set_anchors_preset 默认
	# keep_offsets=true，新控件尺寸会是 0×0。也别在设完锚点后再写 size（引擎会警告）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	_sprite = TextureRect.new()
	# 顺序有讲究：**先设 expand_mode 再设 size**（见 UiStyle.icon 的注释）
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.texture = load(ARROW_TEX) as Texture2D
	_sprite.custom_minimum_size = Vector2i(ARROW_SIZE, ARROW_SIZE)
	_sprite.size = Vector2i(ARROW_SIZE, ARROW_SIZE)
	_sprite.pivot_offset = Vector2(ARROW_SIZE * 0.5, ARROW_SIZE * 0.5)
	_sprite.visible = false
	add_child(_sprite)


func _process(delta: float) -> void:
	_t += delta
	var show: bool = false
	if QuestGuide.valid() and get_tree().get_nodes_in_group("modal_ui").is_empty():
		var player: Node2D = QuestGuide.player_node()
		if player != null:
			var rs: float = WindowScale.render_scale().x
			if rs <= 0.0:
				rs = 1.0
			# 玩家 → 罗盘原点；目标 → 箭头要指的位置（都换算到 640×384 逻辑坐标）
			var origin: Vector2 = player.get_global_transform_with_canvas().origin / rs
			var target: Vector2 = QuestGuide.world_to_canvas(player, QuestGuide.waypoint()) / rs
			var d: Vector2 = target - origin
			var safe: Rect2 = Rect2(EDGE_MARGIN, EDGE_MARGIN,
					640.0 - EDGE_MARGIN * 2.0, 384.0 - EDGE_MARGIN * 2.0)
			if d.length() > ARRIVE_DIST:
				if safe.has_point(target):
					var lift: float = MARK_LIFT_DEST if QuestGuide.kind() == "dest" \
							else MARK_LIFT_DOOR
					_place_marker(target, lift)
				else:
					_place_compass(origin, d, safe)
				show = true
	_sprite.visible = show


## 目标在屏幕内：箭头悬在它正上方、朝下指（地标样式），并夹回安全区免得飞出边。
func _place_marker(target: Vector2, lift: float) -> void:
	var p: Vector2 = target - Vector2(0.0, lift)
	p.x = clampf(p.x, EDGE_MARGIN, 640.0 - EDGE_MARGIN)
	p.y = clampf(p.y, EDGE_MARGIN, 384.0 - EDGE_MARGIN)
	_sprite.position = p - Vector2(ARROW_SIZE * 0.5, ARROW_SIZE * 0.5)
	_sprite.position.y += sin(_t * BOB_SPEED) * BOB_AMP
	_sprite.rotation = PI


## 目标在屏幕外：箭头贴到安全区边界，绕自身中心指向目标。
func _place_compass(origin: Vector2, d: Vector2, safe: Rect2) -> void:
	var p: Vector2 = _edge_point(origin, d, safe)
	_sprite.position = p - Vector2(ARROW_SIZE * 0.5, ARROW_SIZE * 0.5)
	_sprite.position.y += sin(_t * BOB_SPEED) * BOB_AMP
	# 素材朝上（rotation=0 时指上）；方向向量的 angle 以 +x 为 0 → 补 90°
	_sprite.rotation = d.angle() + PI * 0.5


## 从 origin 沿 d 方向射出去，撞到安全区 rect 的那个点。
static func _edge_point(origin: Vector2, d: Vector2, rect: Rect2) -> Vector2:
	if d.length_squared() <= 0.000001:
		return origin
	var t: float = INF
	if d.x > 0.0:
		t = minf(t, (rect.position.x + rect.size.x - origin.x) / d.x)
	elif d.x < 0.0:
		t = minf(t, (rect.position.x - origin.x) / d.x)
	if d.y > 0.0:
		t = minf(t, (rect.position.y + rect.size.y - origin.y) / d.y)
	elif d.y < 0.0:
		t = minf(t, (rect.position.y - origin.y) / d.y)
	if is_inf(t):
		return origin
	return origin + d * t
