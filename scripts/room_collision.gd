extends StaticBody2D
## 房间边界碰撞（坐标系 = 底图 scene_day_v15_1x.png 的 640x384 像素坐标）。
##
## 这里**只管墙**：`room_bounds` 是可行走矩形，四面墙由它自动生成。
## 只要这一个数字对，角色就永远走不出房间，边界永远是四条干净长边（滑行不卡）。
##
## 家具的碰撞框**不在这里** —— 它们跟家具精灵是同一条数据（props.json 的
## collision_rect），由 PropLayer 生成。理由：家具的"画"和"挡"必须一一对应，
## 分两个文件写迟早会漂。墙不一样，墙没有精灵，只能由边界推出来。

@export_group("Room")
## 可行走区域（x, y, w, h）。
@export var room_bounds: Rect2 = Rect2(24.0, 76.0, 599.0, 230.0)
## 外墙厚度，只影响碰撞体大小，不影响画面。
@export var wall_thickness: float = 64.0
@export_group("Door")
## 入口门洞（村庄）：底墙在此 x 范围开口（世界坐标，左右缘）。
@export var door_gap_x: Vector2 = Vector2(296.0, 342.0)
## 门槛线：门洞内可行走的最低脚底线（门板底/台阶）。
@export var door_sill_y: float = 378.0
## 北墙门洞（酒馆左上角通往地窖那扇门）：北墙在此 x 范围开口，整段墙厚全开。
## 设为空向量 = 北墙不开洞。
## 2026-10-28 起地窖改成"同一张图的上半层"，两间房靠这个门洞连通，
## 不再有 DoorArea 切场景。
@export var north_gap_x: Vector2 = Vector2.ZERO
## 地窖口：底墙在此 x 范围开口，直接下行（不砌门槛）。
## 设为空向量 = 不开地窖口。与村庄门洞共用一条底墙，两个口都支持。
@export var cellar_gap_x: Vector2 = Vector2.ZERO
## 打开后在画面里描出可行走框（青）。
@export var show_debug: bool = false


func _ready() -> void:
	for r: Rect2 in _wall_rects():
		_add_box(r)
	queue_redraw()


func _wall_rects() -> Array[Rect2]:
	var b: Rect2 = room_bounds
	var t: float = wall_thickness
	var x0: float = b.position.x - t
	var full_w: float = b.size.x + t * 2.0
	var x_end: float = x0 + full_w
	var y_bottom: float = b.end.y
	var rects: Array[Rect2] = []
	# 北墙：按 north_gap_x 切成左右两段（门洞处整段墙厚留空，人能平平地走过去）
	var y_top: float = b.position.y - t
	if north_gap_x.x < north_gap_x.y:
		if north_gap_x.x > x0:
			rects.append(Rect2(x0, y_top, north_gap_x.x - x0, t))
		if north_gap_x.y < x_end:
			rects.append(Rect2(north_gap_x.y, y_top, x_end - north_gap_x.y, t))
	else:
		rects.append(Rect2(x0, y_top, full_w, t))
	rects.append(Rect2(x0, b.position.y, t, b.size.y))
	rects.append(Rect2(b.end.x, b.position.y, t, b.size.y))
	# 底墙按门洞列表切成若干段（村庄口 + 地窖口，按 x 排序后逐段切）
	var gaps: Array[Vector2] = []
	if door_gap_x.x < door_gap_x.y:
		gaps.append(door_gap_x)
	if cellar_gap_x.x < cellar_gap_x.y:
		gaps.append(cellar_gap_x)
	gaps.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
	var cursor: float = x0
	for g: Vector2 in gaps:
		if g.x > cursor:
			rects.append(Rect2(cursor, y_bottom, g.x - cursor, t))
		cursor = g.y
	if cursor < x_end:
		rects.append(Rect2(cursor, y_bottom, x_end - cursor, t))
	# 村庄口砌门槛（防掉出地图）；地窖口不砌门槛，可直接下行
	if door_gap_x.x < door_gap_x.y:
		rects.append(Rect2(door_gap_x.x, door_sill_y,
				door_gap_x.y - door_gap_x.x, 384.0 - door_sill_y))
	return rects


func _add_box(r: Rect2) -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = r.size
	var col: CollisionShape2D = CollisionShape2D.new()
	col.shape = shape
	col.position = r.position + r.size * 0.5
	add_child(col)


func _draw() -> void:
	if not show_debug:
		return
	draw_rect(room_bounds, Color(0.2, 1.0, 1.0, 0.85), false, 1.0)
